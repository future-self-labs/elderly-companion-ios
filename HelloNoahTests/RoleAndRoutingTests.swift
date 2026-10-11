import XCTest
@testable import HelloNoah

final class RoleGatingTests: XCTestCase {
    func testBeheerderCanDoEverything() {
        let p = Permissions(role: .beheerder)
        XCTAssertTrue(p.canView)
        XCTAssertTrue(p.canEditProfile)
        XCTAssertTrue(p.canEditSettings)
        XCTAssertTrue(p.canEditLifeStory)
        XCTAssertTrue(p.canEditReminders)
        XCTAssertTrue(p.canEditEmergencyContacts)
        XCTAssertTrue(p.canAcknowledgeAlerts)
        XCTAssertTrue(p.canResolveAlerts)
        XCTAssertTrue(p.canCallNow)
        XCTAssertTrue(p.canInvite)
        XCTAssertTrue(p.canManageDevices)
        XCTAssertTrue(p.canManageSubscription)
        XCTAssertTrue(p.canDeleteProfile)
    }

    /// Contract §1: a lezer can only GET and acknowledge alerts.
    func testLezerIsReadOnlyButCanAcknowledge() {
        let p = Permissions(role: .lezer)
        XCTAssertTrue(p.canView)
        XCTAssertTrue(p.canAcknowledgeAlerts)
        XCTAssertFalse(p.canEditProfile)
        XCTAssertFalse(p.canEditSettings)
        XCTAssertFalse(p.canEditLifeStory)
        XCTAssertFalse(p.canEditReminders)
        XCTAssertFalse(p.canEditEmergencyContacts)
        XCTAssertFalse(p.canEditPeople)
        XCTAssertFalse(p.canResolveAlerts)
        XCTAssertFalse(p.canCallNow)
        XCTAssertFalse(p.canInvite)
        XCTAssertFalse(p.canManageCaregivers)
        XCTAssertFalse(p.canManageDevices)
        XCTAssertFalse(p.canPair)
        XCTAssertFalse(p.canManageSubscription)
        XCTAssertFalse(p.canExportProfile)
        XCTAssertFalse(p.canDeleteProfile)
        XCTAssertFalse(p.canViewPeople)
        XCTAssertFalse(p.canViewSettings)
        XCTAssertFalse(p.canViewEmergencyContacts)
        XCTAssertFalse(p.canViewCaregivers)
        XCTAssertFalse(p.canViewDevices)
        XCTAssertFalse(p.canViewSubscription)
    }

    func testUnknownRoleGetsNothing() {
        let p = Permissions(role: .unknown)
        XCTAssertFalse(p.canView)
        XCTAssertFalse(p.canAcknowledgeAlerts)
        XCTAssertFalse(p.canEditReminders)
    }

    /// The mock enforces the same rules as the backend.
    func testMockRejectsWritesForLezer() async throws {
        let defaults = UserDefaults(suiteName: "RoleGatingTests")!
        defaults.removePersistentDomain(forName: "RoleGatingTests")
        defaults.set(0.0, forKey: "mockLatency")
        defaults.set(MockIDs.anna, forKey: "mock.currentCaregiver")
        let api = MockNoahAPI(defaults: defaults)

        let me = try await api.me()
        XCTAssertEqual(me.elderly.first { $0.id == MockIDs.riet }?.role, .lezer)
        XCTAssertEqual(me.elderly.first { $0.id == MockIDs.wim }?.role, .beheerder)

        // Reading the dashboard works for a lezer…
        _ = try await api.dashboard(elderlyId: MockIDs.riet)
        _ = try await api.elderly(id: MockIDs.riet)
        // …but not people, settings, contacts, caregivers, devices or the subscription (backend changelog).
        do {
            _ = try await api.people(elderlyId: MockIDs.riet)
            XCTFail("lezer must not read people")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "alleen_lezen")
        }
        // …writing doesn't.
        do {
            _ = try await api.updateSettings(elderlyId: MockIDs.riet, .defaults)
            XCTFail("lezer must not change settings")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
        }
        do {
            _ = try await api.callNow(elderlyId: MockIDs.riet)
            XCTFail("lezer must not trigger calls")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
        }
        // A beheerder can.
        let reminder = try await api.createReminder(elderlyId: MockIDs.wim, ReminderInput())
        XCTAssertEqual(reminder.createdBy, .caregiver)
    }

    func testMockLastBeheerderCannotBeRemoved() async throws {
        let defaults = UserDefaults(suiteName: "RoleGatingTests2")!
        defaults.set(0.0, forKey: "mockLatency")
        defaults.set(MockIDs.anna, forKey: "mock.currentCaregiver")
        let api = MockNoahAPI(defaults: defaults)
        do {
            try await api.removeCaregiver(elderlyId: MockIDs.wim, caregiverId: MockIDs.anna)
            XCTFail("expected last_beheerder")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "last_beheerder")
        }
    }
}

final class DeepLinkTests: XCTestCase {
    func testLinks() {
        XCTAssertEqual(DeepLink(url: URL(string: "hellonoah://praat")!), .talk)
        XCTAssertEqual(DeepLink(url: URL(string: "hellonoah://koppel/482913")!), .pair(code: "482913"))
        XCTAssertNil(DeepLink(url: URL(string: "hellonoah://koppel/12")!))
        XCTAssertEqual(DeepLink(url: URL(string: "hellonoah://uitnodiging/k7p-2qx")!), .invitation(code: "K7P-2QX"))
        XCTAssertEqual(DeepLink(url: URL(string: "https://hellonoah.ai/uitnodiging/K7P-2QX")!), .invitation(code: "K7P-2QX"))
        XCTAssertEqual(DeepLink(url: URL(string: "hellonoah://melding/a1?elderly=e1")!), .alert(id: "a1", elderlyId: "e1"))
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/uitnodiging/K7P-2QX")!))
        XCTAssertNil(DeepLink(url: URL(string: "hellonoah://onbekend")!))
    }
}
