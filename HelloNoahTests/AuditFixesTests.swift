import XCTest
@testable import HelloNoah

/// Regression tests for the 2026-10-18 iOS and security audit fixes.
final class SettingsPatchTests: XCTestCase {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try NoahJSON.encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// H2: only changed fields are sent, so an unchanged `recording` never reaches the server.
    func testPatchSendsOnlyChangedFields() throws {
        var old = NoahSettings.defaults
        old.recording = .levensverhaal
        var new = old
        new.voice = .man
        let body = try json(NoahSettingsPatch(from: old, to: new))
        XCTAssertEqual(Set(body.keys), ["voice"])
        XCTAssertEqual(body["voice"] as? String, "man")
        XCTAssertTrue(NoahSettingsPatch(from: old, to: old).isEmpty)

        new.recording = .alleGesprekken
        let withRecording = NoahSettingsPatch(from: old, to: new)
        XCTAssertTrue(withRecording.changesRecording)
        XCTAssertEqual(try json(withRecording)["recording"] as? String, "alle_gesprekken")
    }

    /// M11: 0.8 + 8 × 0.05 is 1.2000000000000002 in Double, which the server rejects.
    func testSpeakingSpeedIsRoundedToTwoDecimals() throws {
        var speed = 0.8
        for _ in 0..<8 { speed += 0.05 }
        XCTAssertNotEqual(speed, 1.2)
        XCTAssertEqual(NoahSettings.roundedSpeed(speed), 1.2)
        var new = NoahSettings.defaults
        new.speakingSpeed = speed
        XCTAssertEqual(try json(NoahSettingsPatch(from: .defaults, to: new))["speakingSpeed"] as? Double, 1.2)
        XCTAssertEqual(try json(new)["speakingSpeed"] as? Double, 1.2)
        // A slider that went back to 1.0 is not a change.
        new.speakingSpeed = 0.95 + 0.05
        XCTAssertTrue(NoahSettingsPatch(from: .defaults, to: new).isEmpty)
    }

    /// H2: with recording unavailable on the server, other settings can still be saved.
    func testUnavailableRecordingDoesNotBlockOtherSettings() async throws {
        let defaults = UserDefaults(suiteName: "SettingsPatchTests")!
        defaults.removePersistentDomain(forName: "SettingsPatchTests")
        defaults.set(0.0, forKey: "mockLatency")
        defaults.set(MockIDs.anna, forKey: "mock.currentCaregiver")
        defaults.set(true, forKey: "mockRecordingUnavailable")
        let api = MockNoahAPI(defaults: defaults)

        let saved = try await api.settings(elderlyId: MockIDs.wim)
        XCTAssertEqual(saved.recording, .levensverhaal)
        var draft = saved
        draft.noahName = "Fleur"
        let updated = try await api.updateSettings(elderlyId: MockIDs.wim, NoahSettingsPatch(from: saved, to: draft))
        XCTAssertEqual(updated.noahName, "Fleur")
        XCTAssertEqual(updated.recording, .levensverhaal)

        draft.recording = .alleGesprekken
        do {
            _ = try await api.updateSettings(elderlyId: MockIDs.wim, NoahSettingsPatch(from: updated, to: draft))
            XCTFail("recording needs storage")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 503)
        }
    }
}

/// Security M8: tokens are this-device-only, and items of earlier versions are migrated.
final class KeychainAccessibilityTests: XCTestCase {
    func testOldItemsAreMigratedToThisDeviceOnly() {
        let keychain = Keychain(service: "ai.hellonoah.app.tests.migration")
        keychain.set(nil, for: "deviceToken")
        // As written by earlier versions.
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.service,
            kSecAttrAccount as String: "deviceToken",
            kSecValueData as String: Data("hnd_old".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(keychain.accessibility(of: "deviceToken"), kSecAttrAccessibleAfterFirstUnlock as String)

        XCTAssertEqual(keychain.migrateAccessibility(), 1)
        XCTAssertEqual(keychain.accessibility(of: "deviceToken"), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(keychain.get("deviceToken"), "hnd_old", "the token survives the migration")
        XCTAssertEqual(keychain.migrateAccessibility(), 0, "idempotent")

        keychain.set("hnd_new", for: "deviceToken")
        XCTAssertEqual(keychain.accessibility(of: "deviceToken"), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        keychain.set(nil, for: "deviceToken")
    }
}

/// H4/M6: only a temporary problem may say "betaling ontvangen, we activeren zodra…".
final class SubscriptionOutcomeTests: XCTestCase {
    func testRedeemOutcomes() {
        let offline = SubscriptionStore.redeemOutcome(for: .offline)
        XCTAssertFalse(offline.finish)
        XCTAssertTrue(offline.message.hasPrefix("Betaling ontvangen"))
        XCTAssertFalse(SubscriptionStore.redeemOutcome(for: .server(status: 503, code: "niet_beschikbaar", message: nil)).finish)

        let otherProfile = SubscriptionStore.redeemOutcome(for: .server(status: 400, code: "abonnement_ander_profiel", message: "Dit abonnement hoort bij een ander profiel."))
        XCTAssertTrue(otherProfile.finish)
        XCTAssertFalse(otherProfile.message.contains("Betaling ontvangen"))
        XCTAssertTrue(otherProfile.message.contains("één naaste"))

        let invalid = SubscriptionStore.redeemOutcome(for: .server(status: 400, code: "ongeldig_abonnement", message: nil))
        XCTAssertTrue(invalid.finish)
        XCTAssertFalse(invalid.message.contains("Betaling ontvangen"))

        XCTAssertFalse(SubscriptionStore.redeemOutcome(for: .sessionExpired).finish)
    }

    func testExistingEntitlementExplainsWhoIsPaidFor() {
        let existing = SubscriptionStore.ExistingEntitlement(elderlyId: "a", elderlyName: "Wim", isForThisProfile: false)
        let text = existing.explanation(for: "Riet")
        XCTAssertTrue(text.contains("voor Wim"))
        XCTAssertTrue(text.contains("voor Riet"))
        XCTAssertTrue(text.contains("niets afgeschreven"))
        XCTAssertTrue(SubscriptionStore.ExistingEntitlement(elderlyId: nil, elderlyName: nil, isForThisProfile: false)
            .explanation(for: nil).contains("een ander profiel"))
    }
}
