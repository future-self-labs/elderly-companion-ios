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

/// Security H4/M10/M11: links never act on their own.
final class LinkSafetyTests: XCTestCase {
    func testOnlyTheWidgetTokenStartsAConversationDirectly() {
        let token = "0123456789abcdef0123456789abcdef0123456789abcdef"
        XCTAssertEqual(DeepLink(url: URL(string: "hellonoah://praat")!, widgetToken: token), .talk(verified: false))
        XCTAssertEqual(DeepLink(url: URL(string: "hellonoah://praat?bron=widget")!, widgetToken: token), .talk(verified: false))
        XCTAssertEqual(DeepLink(url: URL(string: "hellonoah://praat?bron=widget&t=wrong")!, widgetToken: token), .talk(verified: false))
        XCTAssertEqual(DeepLink(url: WidgetLaunch.talkURL(token: token), widgetToken: token), .talk(verified: true))
        // Without a stored token nothing is verified.
        XCTAssertEqual(DeepLink(url: WidgetLaunch.talkURL(token: token), widgetToken: nil), .talk(verified: false))
        // Story links always wait for the tap.
        XCTAssertEqual(DeepLink(url: URL(string: "hellonoah://verhaal")!, widgetToken: token), .story)
    }

    func testInvitationCodesAreValidated() {
        XCTAssertEqual(DeepLink(url: URL(string: "https://www.hellonoah.ai/uitnodiging/k7p2qx")!), .invitation(code: "K7P-2QX"))
        XCTAssertNil(DeepLink(url: URL(string: "hellonoah://uitnodiging/<script>")!))
        XCTAssertNil(DeepLink(url: URL(string: "hellonoah://uitnodiging/K7P-2QX-EXTRA")!))
        XCTAssertNil(DeepLink.normalizedInvitationCode("K7"))
        XCTAssertEqual(DeepLink.normalizedInvitationCode(" k7p-2qx "), "K7P-2QX")
    }

    @MainActor
    func testExternalTalkLinkNeedsConfirmation() {
        let session = ElderSession(api: MockNoahAPI(), reachability: Reachability(), makeEngine: { MockVoiceEngine() })
        session.requestConversation(needsConfirmation: true)
        XCTAssertTrue(session.isConversationPresented)
        XCTAssertTrue(session.conversationNeedsConfirmation)
        session.isConversationPresented = false
        // The big button on the home screen is itself the tap.
        session.requestConversation()
        XCTAssertFalse(session.conversationNeedsConfirmation)
    }
}

/// Audit M1: caregivers never see the server's "u"-texts meant for the older person.
final class CaregiverErrorCopyTests: XCTestCase {
    func testKnownCodesUseCaregiverCopy() {
        let inactive = APIError.server(status: 409, code: "inactive", message: "Noah is nog niet actief. Vraag uw mantelzorger om hulp.")
        XCTAssertEqual(inactive.userMessage, "Noah is nog niet actief voor dit profiel. Start eerst het abonnement.")
        XCTAssertEqual(inactive.elderMessage, "Noah is nog niet actief. Vraag uw mantelzorger om hulp.")
        XCTAssertEqual(APIError.server(status: 403, code: "alleen_lezen", message: "U kunt dit alleen bekijken.").userMessage,
                       "Je kijkt mee als lezer. Alleen een beheerder kan dit doen.")
        XCTAssertEqual(APIError.server(status: 401, code: "niet_ingelogd", message: "U bent niet (meer) ingelogd.").userMessage,
                       "Je bent uitgelogd. Log opnieuw in om verder te gaan.")
    }

    func testUnknownCodesUseNeutralServerTextOrFallback() {
        XCTAssertEqual(APIError.server(status: 400, code: "ongeldige_invoer", message: "Spreektempo moet tussen 0.8 en 1.2 liggen.").userMessage,
                       "Spreektempo moet tussen 0.8 en 1.2 liggen.")
        XCTAssertEqual(APIError.server(status: 409, code: "iets_nieuws", message: "Dit kunt u nu niet doen.").userMessage, "Dit kan nu niet.")
        XCTAssertTrue(APIError.isFormal("Vraag uw mantelzorger"))
        XCTAssertTrue(APIError.isFormal("U bent uitgelogd"))
        XCTAssertFalse(APIError.isFormal("Uitnodiging verlopen, vraag een nieuwe"))
    }

    func testCopyDoesNotOverclaim() throws {
        let bundle = Bundle(for: MockNoahAPI.self)
        let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "nl")
                                    ?? bundle.path(forResource: "Localizable", ofType: "strings"))
        let dictionary = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        let texts = (Array(dictionary.keys) + Array(dictionary.values)).map { $0.lowercased() }
        for forbidden in ["alles inbegrepen", "blijft bij een noodgeval aan de lijn", "helpt noah om beter te leren", "pillen innemen"] {
            XCTAssertFalse(texts.contains { $0.contains(forbidden) }, forbidden)
        }
        XCTAssertFalse(texts.contains("versleuteld opgeslagen in de eu"), "privacy line needs the honest wording")
    }
}

/// Backend v2.2: phone number confirmation, new error codes, agent-side session cap.
final class ContractV22Tests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try NoahJSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testProfileCarriesPhoneConfirmation() throws {
        let verified = try decode(ElderlyProfile.self, ContractFixtures.elderlyProfile.replacingOccurrences(
            of: "\"isBeta\": false", with: "\"isBeta\": false, \"phoneVerified\": false, \"phoneVerifiedAt\": null, \"phoneVerifiedVia\": null"))
        XCTAssertEqual(verified.phoneVerified, false)
        XCTAssertTrue(verified.needsPhoneConfirmation)
        // An older backend without the field never asks for confirmation.
        let old = try decode(ElderlyProfile.self, ContractFixtures.elderlyProfile)
        XCTAssertNil(old.phoneVerified)
        XCTAssertFalse(old.needsPhoneConfirmation)
        XCTAssertEqual(try decode(PhoneVerificationStart.self, #"{ "status": "verstuurd", "channel": "sms" }"#).isAlreadyConfirmed, false)
        XCTAssertTrue(try decode(PhoneVerificationStart.self, #"{ "status": "al_bevestigd" }"#).isAlreadyConfirmed)
    }

    func testConversationOverrideCarriesMaxDuration() throws {
        let json = #"{ "conversationToken": "t", "overrides": { "conversation": { "maxDurationSeconds": 600 } } }"#
        XCTAssertEqual(try decode(ConversationSession.self, json).overrides?.conversation?.maxDurationSeconds, 600)
    }

    func testMockConfirmsNumbersAndOnlyCallsConfirmedOnes() async throws {
        let defaults = UserDefaults(suiteName: "ContractV22Tests")!
        defaults.removePersistentDomain(forName: "ContractV22Tests")
        defaults.set(0.0, forKey: "mockLatency")
        defaults.set(MockIDs.anna, forKey: "mock.currentCaregiver")
        defaults.set(true, forKey: "mockPhoneUnverified")
        let api = MockNoahAPI(defaults: defaults)

        let profile = try await api.elderly(id: MockIDs.wim)
        XCTAssertTrue(profile.needsPhoneConfirmation)
        do {
            _ = try await api.callNow(elderlyId: MockIDs.wim, mode: .gesprek)
            XCTFail("unconfirmed numbers are not called")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "telefoonnummer_niet_bevestigd")
            XCTAssertTrue(error.userMessage.contains("Bevestig het nummer"))
            XCTAssertFalse(APIError.isFormal(error.userMessage))
        }
        let sent = try await api.startPhoneVerification(elderlyId: MockIDs.wim, channel: .sms)
        XCTAssertEqual(sent.status, "verstuurd")
        do {
            _ = try await api.verifyPhone(elderlyId: MockIDs.wim, code: "000000")
            XCTFail("wrong code")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 400, "a wrong code must not look like a sign-out (401)")
            XCTAssertEqual(error.code, "ongeldige_code")
        }
        let confirmed = try await api.verifyPhone(elderlyId: MockIDs.wim, code: "123456")
        XCTAssertEqual(confirmed.phoneVerified, true)
        XCTAssertEqual(confirmed.phoneVerifiedVia, "code")

        // A new number must be confirmed again.
        var input = ElderlyProfileInput(profile: confirmed)
        input.phoneNumber = "+31687654321"
        let changed = try await api.updateElderly(id: MockIDs.wim, input)
        XCTAssertEqual(changed.phoneVerified, false)
    }

    func testNewErrorCodesHaveCopyForBothAudiences() {
        for code in ["telefoonnummer_niet_bevestigd", "telefoonnummer_niet_ondersteund", "belgrens_bereikt", "te_veel_profielen", "demo_account", "te_groot"] {
            let message = APIError.server(status: 409, code: code, message: "Uw verzoek kan niet.").userMessage
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(APIError.isFormal(message), code)
        }
        XCTAssertTrue(APIError.server(status: 409, code: "telefoonnummer_niet_bevestigd", message: nil).elderMessage.contains("in de app"))
    }
}
