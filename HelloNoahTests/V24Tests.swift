import XCTest
@testable import HelloNoah

/// API v2.4 (transparency for the older person, account protection, honest notifications) and the
/// client fixes of the 2026-11-14 audit.
final class ContractV24Tests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try NoahJSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testAlertDeliveryAndNewTypes() throws {
        let alert = try decode(NoahAlert.self, ContractFixtures.alert.replacingOccurrences(
            of: "\"acknowledgedBy\": null", with: "\"acknowledgedBy\": null, \"delivery\": { \"pushedDevices\": 0, \"sms\": 0, \"calls\": 0 }"))
        XCTAssertEqual(alert.delivery?.reachedNobody, true)
        XCTAssertTrue(alert.delivery!.caregiverText.contains("niemand"))
        XCTAssertEqual(AlertDelivery(pushedDevices: 2, sms: 1).caregiverText, "Verstuurd: een melding op 2 telefoons en 1 sms.")
        // Older backend: no delivery, nothing claimed.
        XCTAssertNil(try decode(NoahAlert.self, ContractFixtures.alert).delivery)
        for raw in ["privacy_gewijzigd", "wil_stoppen", "verwijderverzoek", "nummer_losgekoppeld"] {
            let decoded = try decode(NoahAlert.self, ContractFixtures.alert.replacingOccurrences(of: "\"lage_stemming\"", with: "\"\(raw)\""))
            XCTAssertNotEqual(decoded.type, .unknown, raw)
            XCTAssertNotEqual(decoded.type.label, "Melding", raw)
        }
    }

    func testProfileTransparencySharingPausedAndNoNumber() throws {
        let json = ContractFixtures.elderlyProfile
            .replacingOccurrences(of: "\"phoneNumber\": \"+31612345678\"", with: "\"phoneNumber\": null")
            .replacingOccurrences(of: "\"isBeta\": false", with: "\"isBeta\": false, \"transparency\": { \"noahToldAt\": null, \"appShownAt\": null, \"caregiverToldAt\": null }, \"sharing\": \"samenvattingen\", \"outboundPaused\": true, \"phoneVerified\": false")
        let profile = try decode(ElderlyProfile.self, json)
        XCTAssertNil(profile.phoneNumber)
        XCTAssertFalse(profile.hasPhoneNumber)
        XCTAssertFalse(profile.needsPhoneConfirmation, "no number: nothing to confirm")
        XCTAssertTrue(profile.needsTellingElderly)
        XCTAssertEqual(profile.sharing, .samenvattingen)
        XCTAssertEqual(profile.outboundPaused, true)
        // Older backend: no transparency, nothing to ask.
        XCTAssertFalse(try decode(ElderlyProfile.self, ContractFixtures.elderlyProfile).needsTellingElderly)
    }

    func testProfileInputNeverSendsAnEmptyNumber() throws {
        var input = ElderlyProfileInput()
        input.firstName = "Willem"
        input.preferredName = "Wim"
        let json = String(data: try NoahJSON.encoder.encode(input), encoding: .utf8)!
        XCTAssertFalse(json.contains("phoneNumber"), json)
        input.phoneNumber = "+31612345678"
        XCTAssertTrue(String(data: try NoahJSON.encoder.encode(input), encoding: .utf8)!.contains("+31612345678"))
    }

    func testHiddenConversationAndDevices() throws {
        let hidden = try decode(ConversationSummary.self, #"{ "id": "c", "startedAt": "2026-10-10T16:05:00Z", "durationSeconds": 60, "channel": "app", "summary": null, "moodScore": null, "hidden": true }"#)
        XCTAssertTrue(hidden.hidden)
        XCTAssertFalse(try decode(ConversationSummary.self, ContractFixtures.conversationSummary).hidden)
        let devices = try decode(ItemsResponse<PairedDevice>.self, #"{ "items": [ { "id": "d1", "deviceName": "iPhone", "platform": "ios", "pairedAt": null, "lastSeenAt": null, "restricted": true, "isThisDevice": true } ] }"#)
        XCTAssertTrue(devices.items[0].restricted)
        XCTAssertTrue(devices.items[0].isThisDevice)
        XCTAssertFalse(try decode(ItemsResponse<PairedDevice>.self, ContractFixtures.devices).items[0].restricted)
    }

    func testVerifyOutcomes() throws {
        let choice = try decode(ElderVerifyOutcome.self, #"{ "status": "keuze_nodig", "claimToken": "hnc_x", "expiresAt": "2026-11-15T10:00:00Z", "profile": { "preferredName": "Wim", "createdBy": "Anna de Vries" } }"#)
        guard case .choiceNeeded(let claim) = choice else { return XCTFail("expected keuze_nodig") }
        XCTAssertEqual(claim.claimToken, "hnc_x")
        XCTAssertEqual(claim.creatorFirstName, "Anna")

        let restricted = try decode(ElderVerifyOutcome.self, #"{ "status": "gekoppeld", "deviceToken": "hnd_x", "device": { "id": "d" }, "elderly": { "id": "e", "preferredName": "Wim", "noahName": "Noah" }, "isNewProfile": false, "managedBy": "mantelzorger", "restricted": true, "restrictedUntil": "2026-11-17T10:00:00Z" }"#)
        guard case .signedIn(let response) = restricted else { return XCTFail("expected a sign-in") }
        XCTAssertTrue(response.restricted)
        XCTAssertNotNil(response.restrictedUntil)

        // v2.3 response (no status) still signs in.
        guard case .signedIn(let old) = try decode(ElderVerifyOutcome.self, ContractFixtures.elderSignUpNew) else { return XCTFail() }
        XCTAssertFalse(old.restricted)
    }

    func testTransparencyAndAcceptStatus() throws {
        let transparency = try decode(DeviceTransparency.self, """
        { "managedBy": "mantelzorger", "caregivers": [ { "id": "c1", "name": "Anna", "role": "beheerder", "joinedAt": "2026-10-01T08:00:00Z" } ],
          "pendingInvitations": [ { "id": "i1", "role": "lezer", "createdAt": "2026-11-14T08:00:00Z", "expiresAt": "2026-11-15T08:00:00Z", "createdBy": "zelf" } ],
          "caregiverRequests": [ { "id": "r1", "name": "Mark", "role": "beheerder", "requestedAt": "2026-11-14T09:00:00Z" } ],
          "familySees": ["Een korte samenvatting van elk gesprek."], "sharing": "alles", "recording": "uit",
          "appShownAt": null, "deletionRequest": { "requestedAt": "2026-11-14T09:00:00Z", "executesAt": "2026-11-28T09:00:00Z" }, "selfRegistered": false }
        """)
        XCTAssertEqual(transparency.caregivers.first?.name, "Anna")
        XCTAssertTrue(transparency.pendingInvitations[0].isMadeByElderly)
        XCTAssertEqual(transparency.caregiverRequests.first?.role, .beheerder)
        XCTAssertNil(transparency.appShownAt)
        XCTAssertNotNil(transparency.deletionRequest?.executesAt)

        let waiting = try decode(AcceptInvitationResponse.self, #"{ "elderly": { "id": "e", "preferredName": "Toos" }, "role": "beheerder", "status": "wacht_op_bevestiging" }"#)
        XCTAssertTrue(waiting.isWaitingForApproval)
        XCTAssertFalse(try decode(AcceptInvitationResponse.self, ContractFixtures.acceptInvitation).isWaitingForApproval)
    }

    func testRequestBodies() throws {
        func json(_ value: some Encodable) throws -> String { String(data: try NoahJSON.encoder.encode(AnyEncodable(value)), encoding: .utf8)! }
        XCTAssertEqual(try json(DeleteConfirmation()), #"{"confirm":"VERWIJDER"}"#)
        XCTAssertEqual(try json(DeleteConfirmation(subscriptionAcknowledged: true)), #"{"confirm":"VERWIJDER","subscriptionAcknowledged":true}"#)
        XCTAssertEqual(try json(DeviceInvitationRequest(role: .lezer, confirmed: true)), #"{"role":"lezer"}"#)
        XCTAssertEqual(try json(DeviceInvitationRequest(role: .beheerder, confirmed: true)), #"{"confirmed":true,"role":"beheerder"}"#)
        XCTAssertEqual(try json(ElderClaimRequest(claimToken: "hnc", choice: .eigenProfiel, deviceName: " ")), #"{"choice":"eigen_profiel","claimToken":"hnc","platform":"ios"}"#)
        var patch = NoahSettingsPatch()
        patch.outboundPaused = false
        XCTAssertEqual(try json(patch), #"{"outboundPaused":false}"#)
    }
}

/// Live paths of the v2.4 endpoints.
final class LiveV24PathTests: XCTestCase {
    func testV24Paths() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let storage = InMemoryTokenStorage(deviceToken: "hnd_x")
        storage.caregiverTokens = CaregiverTokens(accessToken: "acc", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "hnr")
        let api = LiveNoahAPI(client: APIClient(baseURL: URL(string: "https://api.test/api/v2")!, storage: storage, session: URLSession(configuration: configuration)))
        let transparency = #"{ "caregivers": [], "familySees": [] }"#
        let calls: [(String, String, String?, () async throws -> Void)] = [
            ("POST", "/api/v2/elderly/e1/told-elderly", nil, { try await api.markToldElderly(elderlyId: "e1") }),
            ("PATCH", "/api/v2/elderly/e1", #"{"outboundPaused":false}"#, { _ = try await api.setOutboundPaused(elderlyId: "e1", paused: false) }),
            ("GET", "/api/v2/elderly/e1/invitations", nil, { _ = try await api.pendingInvitations(elderlyId: "e1") }),
            ("DELETE", "/api/v2/elderly/e1/invitations/i1", nil, { try await api.revokeInvitation(elderlyId: "e1", invitationId: "i1") }),
            ("POST", "/api/v2/elderly/e1/devices/d1/approve", nil, { try await api.approveDevice(elderlyId: "e1", deviceId: "d1") }),
            ("DELETE", "/api/v2/elderly/e1", #"{"confirm":"VERWIJDER","subscriptionAcknowledged":true}"#, { try await api.deleteElderly(id: "e1", subscriptionAcknowledged: true) }),
            ("DELETE", "/api/v2/me", #"{"confirm":"VERWIJDER"}"#, { try await api.deleteMe() }),
            ("GET", "/api/v2/device/transparency", nil, { _ = try await api.deviceTransparency() }),
            ("POST", "/api/v2/device/transparency/seen", nil, { try await api.markTransparencySeen() }),
            ("PATCH", "/api/v2/device/sharing", #"{"sharing":"alleen_meldingen"}"#, { _ = try await api.updateSharing(.alleenMeldingen) }),
            ("POST", "/api/v2/device/deletion-request", nil, { _ = try await api.requestDeletion() }),
            ("DELETE", "/api/v2/device/deletion-request", nil, { try await api.withdrawDeletion() }),
            ("GET", "/api/v2/device/devices", nil, { _ = try await api.deviceDevices() }),
            ("POST", "/api/v2/device/devices/d2/approve", nil, { try await api.approveDeviceFromDevice(deviceId: "d2") }),
            ("DELETE", "/api/v2/device/devices/d2", nil, { try await api.rejectDeviceFromDevice(deviceId: "d2") }),
            ("POST", "/api/v2/device/caregiver-requests/r1/approve", nil, { try await api.approveCaregiverRequest(id: "r1") }),
            ("POST", "/api/v2/device/caregiver-requests/r1/reject", nil, { try await api.rejectCaregiverRequest(id: "r1") }),
            ("DELETE", "/api/v2/device/invitations/i2", nil, { try await api.revokeDeviceInvitation(id: "i2") }),
            ("PUT", "/api/v2/device/emergency-contacts/order", #"{"ids":["b","a"]}"#, { try await api.reorderDeviceEmergencyContacts(ids: ["b", "a"]) }),
            ("DELETE", "/api/v2/device/account", #"{"confirm":"VERWIJDER","subscriptionAcknowledged":true}"#, { try await api.deleteDeviceAccount(subscriptionAcknowledged: true) }),
            ("POST", "/api/v2/auth/elderly/phone/claim", #"{"choice":"koppelen","claimToken":"hnc","platform":"ios"}"#, { _ = try await api.claimElderSignUp(ElderClaimRequest(claimToken: "hnc", choice: .koppelen)) }),
        ]
        for (method, path, expectedBody, call) in calls {
            StubURLProtocol.handler = { request in
                switch request.url?.path ?? "" {
                case "/api/v2/elderly/e1" where request.httpMethod == "PATCH": return (200, ContractFixtures.elderlyProfile)
                case "/api/v2/elderly/e1/invitations": return (200, #"{ "items": [] }"#)
                case "/api/v2/device/transparency", "/api/v2/device/sharing": return (200, transparency)
                case "/api/v2/device/deletion-request" where request.httpMethod == "POST": return (202, #"{ "requestedAt": "2026-11-14T09:00:00Z", "executesAt": "2026-11-28T09:00:00Z" }"#)
                case "/api/v2/device/devices": return (200, #"{ "items": [] }"#)
                case "/api/v2/auth/elderly/phone/claim": return (200, ContractFixtures.elderSignUpFamily)
                default: return (204, "")
                }
            }
            try await call()
            let request = try XCTUnwrap(StubURLProtocol.requests.first, path)
            XCTAssertEqual(request.httpMethod, method, path)
            XCTAssertEqual(request.url?.path, path)
            if let expectedBody { XCTAssertEqual(body(of: request), expectedBody, path) }
        }
    }

    func testOlderBackendRoutesAreRecognised() {
        XCTAssertTrue(APIError.server(status: 404, code: "niet_gevonden", message: nil).isFeatureUnavailable)
        XCTAssertTrue(APIError.server(status: 404, code: "http_404", message: nil).isFeatureUnavailable)
        XCTAssertFalse(APIError.server(status: 403, code: "alleen_lezen", message: nil).isFeatureUnavailable)
        XCTAssertFalse(APIError.offline.isFeatureUnavailable)
    }

    private func body(of request: URLRequest) -> String? {
        if let data = request.httpBody { return String(data: data, encoding: .utf8) }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8)
    }
}

/// The mock follows v2.4 like the backend, and degrades like an older backend.
final class MockV24Tests: XCTestCase {
    private func makeDefaults(_ name: String, v23: Bool = false) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(0.0, forKey: "mockLatency")
        defaults.set(MockIDs.anna, forKey: "mock.currentCaregiver")
        if v23 { defaults.set(true, forKey: "mockV23Backend") }
        return defaults
    }

    func testClaimFlow() async throws {
        var token: String?
        let api = MockNoahAPI(defaults: makeDefaults("V24.claim"), deviceToken: { token })
        let outcome = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31611223344", code: "123456"))
        guard case .choiceNeeded(let choice) = outcome else { return XCTFail("Bep's number asks first") }
        XCTAssertEqual(choice.profile?.createdBy, "Mark de Vries")
        let own = try await api.claimElderSignUp(ElderClaimRequest(claimToken: choice.claimToken, choice: .eigenProfiel))
        XCTAssertEqual(own.managedBy, .zelf)
        XCTAssertTrue(own.needsOnboarding)
        token = own.deviceToken
        let v1 = try await api.deviceProfile().phoneNumber
        XCTAssertEqual(v1, "+31611223344")

        let other = MockNoahAPI(defaults: makeDefaults("V24.claim2"), deviceToken: { nil })
        guard case .choiceNeeded(let again) = try await other.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31611223344", code: "123456")) else { return XCTFail() }
        let linked = try await other.claimElderSignUp(ElderClaimRequest(claimToken: again.claimToken, choice: .koppelen))
        XCTAssertEqual(linked.elderly.id, MockIDs.bep)
        XCTAssertTrue(linked.isLinkedToFamily)
        XCTAssertFalse(linked.restricted)
    }

    func testNewPhoneOnAProfileInUseIsRestricted() async throws {
        let api = MockNoahAPI(defaults: makeDefaults("V24.restricted"))
        let response = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31623456789", code: "123456")).signedInResponse()
        XCTAssertTrue(response.restricted)
        let devices = try await api.devices(elderlyId: MockIDs.wim)
        XCTAssertTrue(devices.contains { $0.restricted })
        let restricted = devices.first { $0.restricted }!
        try await api.approveDevice(elderlyId: MockIDs.wim, deviceId: restricted.id)
        let afterwards = try await api.devices(elderlyId: MockIDs.wim)
        XCTAssertFalse(afterwards.contains { $0.restricted })
    }

    func testSharingHidesWhatTheOlderPersonChose() async throws {
        let wimPhone = MockNoahAPI(defaults: makeDefaults("V24.sharing"), deviceToken: { "hnd_mock_\(MockIDs.wim)" })
        let page = try await wimPhone.conversations(elderlyId: MockIDs.wim, cursor: nil, limit: 50)
        XCTAssertTrue(page.items.contains { $0.hidden }, "one conversation was kept private")
        let first = try await wimPhone.conversation(id: page.items.first { !$0.hidden }!.id)
        XCTAssertFalse(first.transcript.isEmpty)

        let updated = try await wimPhone.updateSharing(.samenvattingen)
        XCTAssertEqual(updated.sharing, .samenvattingen)
        XCTAssertFalse(updated.familySees.contains { $0.contains("woord voor woord") })
        let summaryOnly = try await wimPhone.conversation(id: first.id)
        XCTAssertTrue(summaryOnly.transcript.isEmpty)
        XCTAssertNil(summaryOnly.cognitiveClarity)
        let alerts = try await wimPhone.alerts(elderlyId: MockIDs.wim, status: .open, cursor: nil, limit: 20).items
        XCTAssertTrue(alerts.contains { $0.type == .privacyGewijzigd }, "the family is told")

        _ = try await wimPhone.updateSharing(.alleenMeldingen)
        let onlyAlerts = try await wimPhone.conversation(id: first.id)
        XCTAssertTrue(onlyAlerts.hidden)
        XCTAssertNil(onlyAlerts.summary)
    }

    func testRequestsInvitationsAndDeletion() async throws {
        let defaults = makeDefaults("V24.requests")
        let toos = MockNoahAPI(defaults: defaults, deviceToken: { "hnd_mock_\(MockIDs.toos)" })
        do {
            _ = try await toos.createDeviceInvitation(role: .beheerder, confirmed: false)
            XCTFail("a beheerder invitation is confirmed first")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "bevestiging_nodig")
        }
        let invitation = try await toos.createDeviceInvitation(role: .lezer, confirmed: false)
        XCTAssertLessThan(invitation.expiresAt!.timeIntervalSinceNow, 86_400 + 60, "valid 24 hours")
        let pending = try await toos.deviceTransparency().pendingInvitations
        XCTAssertEqual(pending.count, 1)
        try await toos.revokeDeviceInvitation(id: pending[0].id)
        let v1 = try await toos.deviceTransparency().pendingInvitations
        XCTAssertTrue(v1.isEmpty)

        let wim = MockNoahAPI(defaults: makeDefaults("V24.wimDelete"), deviceToken: { "hnd_mock_\(MockIDs.wim)" })
        do {
            _ = try await wim.requestDeletion()
            XCTFail("the family still pays: confirmed first")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "abonnement_actief")
        }
        let request = try await wim.requestDeletion(subscriptionAcknowledged: true)
        XCTAssertNotNil(request.executesAt)
        let v2 = try await wim.deviceTransparency().deletionRequest
        XCTAssertNotNil(v2)
        try await wim.withdrawDeletion()
        let v3 = try await wim.deviceTransparency().deletionRequest
        XCTAssertNil(v3)
        // Export is the older person's right on both kinds of profile now.
        _ = try await wim.exportDevice()
    }

    func testCaregiverSideGuards() async throws {
        let api = MockNoahAPI(defaults: makeDefaults("V24.caregiver"))
        do {
            try await api.deleteElderly(id: MockIDs.wim)
            XCTFail("a running subscription is confirmed first")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "abonnement_actief")
        }
        let invitations = try await api.pendingInvitations(elderlyId: MockIDs.wim)
        XCTAssertFalse(invitations.isEmpty)
        try await api.revokeInvitation(elderlyId: MockIDs.wim, invitationId: invitations[0].id)
        let v1 = try await api.pendingInvitations(elderlyId: MockIDs.wim).isEmpty
        XCTAssertTrue(v1)
        for index in 0..<2 {
            _ = try await api.createEmergencyContact(elderlyId: MockIDs.wim, EmergencyContactInput(name: "Buur \(index)", phoneNumber: "+3161234567\(index)"))
        }
        do {
            _ = try await api.createEmergencyContact(elderlyId: MockIDs.wim, EmergencyContactInput(name: "Zesde", phoneNumber: "+31612345679"))
            XCTFail("at most 5")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "te_veel_noodcontacten")
        }
        let paused = try await api.setOutboundPaused(elderlyId: MockIDs.wim, paused: true)
        XCTAssertEqual(paused.outboundPaused, true)
        try await api.markToldElderly(elderlyId: MockIDs.wim)
        let profile = try await api.elderly(id: MockIDs.wim)
        XCTAssertNotNil(profile.transparency?.caregiverToldAt)
    }

    @MainActor
    func testOlderBackendHidesTheNewFeatures() async throws {
        let defaults = makeDefaults("V24.v23", v23: true)
        let api = MockNoahAPI(defaults: defaults, deviceToken: { "hnd_mock_\(MockIDs.wim)" })
        do {
            _ = try await api.deviceTransparency()
            XCTFail("older backend")
        } catch let error as APIError {
            XCTAssertTrue(error.isFeatureUnavailable)
        }
        let session = ElderSession(api: api, reachability: Reachability(), subscriptions: SubscriptionStore(), defaults: defaults, makeEngine: { MockVoiceEngine() })
        let snapshot = try await session.transparencySnapshot()
        XCTAssertFalse(snapshot.supportsControls)
        XCTAssertFalse(snapshot.members.isEmpty, "built from GET /device/caregivers")
        XCTAssertTrue(snapshot.familySees.contains { $0.contains("uitgeschreven tekst") })
        XCTAssertTrue(session.transparencyUnsupported)
        let profile = try await api.elderly(id: MockIDs.wim)
        XCTAssertNil(profile.transparency)
        XCTAssertFalse(profile.needsTellingElderly)
    }
}

/// Client fixes of the 2026-11-14 audit.
@MainActor
final class Audit20261114Tests: XCTestCase {
    private func profile(verified: Bool?, phone: String? = "+31612345678", told: Bool = true) -> ElderlyProfile {
        ElderlyProfile(id: "e", firstName: "Willem", preferredName: "Wim", addressForm: .u, phoneNumber: phone, access: .active,
                       phoneVerified: verified, transparency: Transparency(caregiverToldAt: told ? Date() : nil))
    }

    func testNextStepsCoverTheSetup() {
        let all = NextStepsCard.steps(profile: profile(verified: false, told: false), hasDevice: false, hasEmergencyContact: false).map(\.id)
        XCTAssertEqual(all, ["confirm", "tell", "pair", "contacts"])
        XCTAssertTrue(NextStepsCard.steps(profile: profile(verified: true), hasDevice: true, hasEmergencyContact: true).isEmpty)
        XCTAssertEqual(NextStepsCard.steps(profile: profile(verified: false, phone: nil), hasDevice: nil, hasEmergencyContact: nil).map(\.id), ["phone"])
    }

    func testWizardConfirmsTheNumberAndTellsTheOlderPerson() {
        let steps = ProfileWizardModel.Step.allCases
        XCTAssertEqual(steps[steps.firstIndex(of: .phone)! + 1], .confirmPhone)
        XCTAssertTrue(steps.firstIndex(of: .tellElderly)! < steps.firstIndex(of: .subscription)!)
        XCTAssertEqual(ProfileWizardModel.Step.preferences.title(name: "Wim"), "Waar praat Wim graag over?")
        XCTAssertEqual(ProfileWizardModel.Step.subscription.title(name: "Wim"), "Abonnement")
        XCTAssertFalse(PaywallView.activeText(name: "Jan", phoneConfirmed: false).contains("aan de telefoon"))
        XCTAssertTrue(PaywallView.activeText(name: "Jan", phoneConfirmed: true).contains("bellen"))
        let readAloud = TellElderlyPanel.readAloudText(name: "Wim", caregiverName: "Anna")
        XCTAssertTrue(readAloud.contains("computer"))
        XCTAssertTrue(readAloud.contains("woord voor woord"))
        XCTAssertTrue(readAloud.contains("alleen voor mij"))
    }

    func testNewPurchaseIsNeverCalledFreeOrFinishedOnAProfileMixUp() {
        let outcome = SubscriptionStore.redeemOutcome(for: .server(status: 400, code: "abonnement_ander_profiel", message: nil), isNewPurchase: true)
        XCTAssertFalse(outcome.finish)
        XCTAssertFalse(outcome.message.contains("niets extra afgeschreven"))
        XCTAssertTrue(outcome.message.contains(SupportContact.email))
    }

    func testTagDraftsAreCommittedOnSave() {
        let drafts = PendingTagDrafts()
        var tags: [String] = []
        let id = UUID()
        drafts.register(id) { tags.append("Tante Bep") }
        drafts.commitAll()
        XCTAssertEqual(tags, ["Tante Bep"])
        drafts.unregister(id)
        drafts.commitAll()
        XCTAssertEqual(tags.count, 1)
    }

    func testHonestCopy() {
        XCTAssertTrue(RecordingSetting.uit.explanation(name: "Wim").contains("uitgeschreven tekst"))
        XCTAssertTrue(FamilySees.sentences(sharing: .alles, recording: .uit).contains { $0.contains("woord voor woord") })
        XCTAssertFalse(FamilySees.sentences(sharing: .samenvattingen, recording: .uit).contains { $0.contains("woord voor woord") && !$0.hasPrefix("Niet") })
        XCTAssertTrue(FamilySees.sentences(sharing: .alleenMeldingen, recording: .levensverhaal).contains { $0.contains("Opnames") })
        // Towards the older person: "uw familie", never "uw mantelzorger"; self-managed: nobody to ask.
        for code in ["inactive", "telefoonnummer_niet_bevestigd", "telefoonnummer_niet_ondersteund", "apparaat_wacht_op_bevestiging", "te_veel_noodcontacten", "abonnement_actief"] {
            let error = APIError.server(status: 409, code: code, message: "Vraag uw mantelzorger om hulp.")
            XCTAssertFalse(error.elderMessage.contains("mantelzorger"), code)
            XCTAssertFalse(error.elderMessage(isSelfManaged: true).contains("familie"), code)
        }
        XCTAssertEqual(APIError.server(status: 400, code: "iets", message: "Vraag uw mantelzorger om hulp.").elderMessage, "Vraag uw familie om hulp.")
        XCTAssertFalse(APIError.caregiverMessage(code: "ongeldig_abonnement")!.contains("supportteam"))
        XCTAssertEqual(PairingCopy.welcomeButton, "Deze telefoon koppelen met een code")
        XCTAssertEqual(Weekdays.isoWeekday(of: DutchFormat.calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!), 1)
        XCTAssertFalse(EmergencyContactInput(name: "A", phoneNumber: "+31612345678", notifyBySms: false, notifyByCall: false).hasChannel)
    }

    func testLinksAreDutchAndOwn() {
        let config = AppConfig.current()
        XCTAssertEqual(config.termsURL.absoluteString, "https://hellonoah.ai/voorwaarden")
        XCTAssertEqual(config.privacyURL.absoluteString, "https://hellonoah.ai/privacy")
        XCTAssertEqual(config.supportURL.absoluteString, "https://hellonoah.ai/hulp")
        XCTAssertEqual(config.accountDeletionURL.absoluteString, "https://hellonoah.ai/account-verwijderen")
        XCTAssertEqual(DeepLink(url: URL(string: "https://hellonoah.ai/uitnodiging/k7p2qx")!), .invitation(code: "K7P-2QX"))
    }

    func testShippedStringsMakeNoFalsePromises() throws {
        let bundle = Bundle(for: MockNoahAPI.self)
        let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "nl")
                                    ?? bundle.path(forResource: "Localizable", ofType: "strings"))
        let dictionary = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        let texts = (Array(dictionary.keys) + Array(dictionary.values)).map { $0.lowercased() }
        for forbidden in ["supportteam", "dag en nacht", "meteen een melding", "u kunt mij altijd bellen", "telefoon of tablet",
                          "gebruiksvoorwaarden (eula)", "is voor iemand die met noah gaat praten", "wanneer u maar wilt"] {
            XCTAssertFalse(texts.contains { $0.contains(forbidden) }, forbidden)
        }
    }
}
