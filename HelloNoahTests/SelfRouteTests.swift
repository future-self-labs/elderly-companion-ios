import XCTest
@testable import HelloNoah

/// Contract v2.3 (2026-10-19) examples, made valid JSON.
extension ContractFixtures {
    static let elderSignUpNew = """
    { "deviceToken": "hnd_new", "device": { "id": "d9" },
      "elderly": { "id": "5B2E9F40-7C1D-4A8B-9E3F-0A1B2C3D4E5F", "preferredName": "", "noahName": "Noah" },
      "isNewProfile": true, "managedBy": "zelf", "somethingNew": 1 }
    """

    static let elderSignUpFamily = """
    { "deviceToken": "hnd_wim", "device": { "id": "d1" },
      "elderly": { "id": "e1", "preferredName": "Wim", "noahName": "Noah" },
      "isNewProfile": false, "managedBy": "mantelzorger" }
    """

    static let emergencyContact = """
    { "id": "E21", "name": "Ellen", "phoneNumber": "+31656781234", "relation": "dochter", "priority": 1, "notifyBySms": true, "notifyByCall": true }
    """

    static let deviceProfile = """
    { "preferredName": "Toos", "addressForm": "u", "phoneNumber": "+31645678901", "managedBy": "zelf", "access": "active" }
    """
}

/// v2.3 self route: models, requests and endpoints.
final class SelfRouteContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try NoahJSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: NoahJSON.encoder.encode(AnyEncodable(value))) as? [String: Any])
    }

    func testSignUpResponsesDecode() throws {
        let new = try decode(ElderSignUpResponse.self, ContractFixtures.elderSignUpNew)
        XCTAssertEqual(new.deviceToken, "hnd_new")
        XCTAssertEqual(new.elderly.preferredName, "")
        XCTAssertTrue(new.isNewProfile)
        XCTAssertEqual(new.managedBy, .zelf)
        XCTAssertTrue(new.needsOnboarding)
        XCTAssertFalse(new.isLinkedToFamily)

        let family = try decode(ElderSignUpResponse.self, ContractFixtures.elderSignUpFamily)
        XCTAssertEqual(family.managedBy, .mantelzorger)
        XCTAssertTrue(family.isLinkedToFamily)
        XCTAssertFalse(family.needsOnboarding)

        // A name may be missing for a brand-new profile; unknown values stay tolerant.
        let odd = try decode(ElderSignUpResponse.self, #"{ "deviceToken": "hnd", "device": { "id": "d" }, "elderly": { "id": "e" }, "managedBy": "iets_nieuws" }"#)
        XCTAssertEqual(odd.elderly.preferredName, "")
        XCTAssertEqual(odd.managedBy, .unknown)
        XCTAssertFalse(odd.isNewProfile)
        XCTAssertFalse(odd.needsOnboarding)
    }

    func testDeviceProfileAndManagedByDecode() throws {
        let profile = try decode(DeviceProfile.self, ContractFixtures.deviceProfile)
        XCTAssertEqual(profile.preferredName, "Toos")
        XCTAssertEqual(profile.addressForm, .u)
        XCTAssertTrue(profile.isSelfManaged)
        XCTAssertEqual(profile.access, .active)
        // Without managedBy (older backend) nobody gets the self-managed settings.
        let old = try decode(DeviceProfile.self, #"{ "preferredName": "Wim", "addressForm": "jij" }"#)
        XCTAssertFalse(old.isSelfManaged)
        XCTAssertEqual(old.addressForm, .jij)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.elderlyProfile.utf8)) as? [String: Any])
        XCTAssertNil(try decode(ElderlyProfile.self, ContractFixtures.elderlyProfile).managedBy)
        json["managedBy"] = "zelf"
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try NoahJSON.decoder.decode(ElderlyProfile.self, from: data).managedBy, .zelf)
    }

    func testManagedByOnMeAndDeviceMe() throws {
        let me = try decode(MeResponse.self, #"{ "caregiver": { "id": "c1" }, "elderly": [ { "id": "e1", "preferredName": "Toos", "role": "lezer", "access": "active", "managedBy": "zelf" } ] }"#)
        XCTAssertEqual(me.elderly.first?.managedBy, .zelf)
        let top = try decode(DeviceMe.self, #"{ "elderly": { "id": "e1", "preferredName": "Toos" }, "access": "active", "managedBy": "zelf" }"#)
        XCTAssertEqual(top.resolvedManagedBy, .zelf)
        let nested = try decode(DeviceMe.self, #"{ "elderly": { "id": "e1", "preferredName": "Wim", "managedBy": "mantelzorger" }, "access": "active" }"#)
        XCTAssertEqual(nested.resolvedManagedBy, .mantelzorger)
        XCTAssertNil(try decode(DeviceMe.self, ContractFixtures.deviceMe).resolvedManagedBy)
        XCTAssertEqual(try decode(NoahAlert.self, #"{ "id": "a", "type": "apparaat_gekoppeld", "severity": "info", "title": "De telefoon van Wim is gekoppeld", "status": "open", "createdAt": "2026-10-19T08:00:00Z" }"#).type, .apparaatGekoppeld)
    }

    func testSignUpRequestsEncodeOnlyWhatIsSet() throws {
        XCTAssertEqual(Set(try object(ElderSignUpStartRequest(phoneNumber: "+31612345678", channel: .sms)).keys), ["phoneNumber"])
        let call = try object(ElderSignUpStartRequest(phoneNumber: "+31201234567", channel: .call))
        XCTAssertEqual(call["channel"] as? String, "call")

        let bare = try object(ElderSignUpVerifyRequest(phoneNumber: "+31612345678", code: "123456"))
        XCTAssertEqual(Set(bare.keys), ["phoneNumber", "code", "platform"])
        XCTAssertEqual(bare["platform"] as? String, "ios")
        let blank = try object(ElderSignUpVerifyRequest(phoneNumber: "+31612345678", code: "123456", preferredName: "  ", addressForm: .unknown, deviceName: " "))
        XCTAssertEqual(Set(blank.keys), ["phoneNumber", "code", "platform"])
        XCTAssertEqual(try object(ElderSignUpVerifyRequest(phoneNumber: "+31612345678", code: "123456", deviceName: "iPhone van Toos"))["deviceName"] as? String, "iPhone van Toos")
        let full = try object(ElderSignUpVerifyRequest(phoneNumber: "+31612345678", code: "123456", preferredName: "Wim", addressForm: .jij))
        XCTAssertEqual(full["preferredName"] as? String, "Wim")
        XCTAssertEqual(full["addressForm"] as? String, "jij")

        XCTAssertTrue(DeviceProfilePatch().isEmpty)
        XCTAssertEqual(try object(DeviceProfilePatch(preferredName: " Toos ", addressForm: nil)) as NSDictionary, ["preferredName": "Toos"] as NSDictionary)
        XCTAssertEqual(try object(DeviceProfilePatch(preferredName: nil, addressForm: .u)) as NSDictionary, ["addressForm": "u"] as NSDictionary)
    }

    func testLiveRequestsUseTheContractPaths() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let storage = InMemoryTokenStorage(deviceToken: "hnd_self")
        let api = LiveNoahAPI(client: APIClient(baseURL: URL(string: "https://api.test/api/v2")!, storage: storage, session: URLSession(configuration: configuration)))

        StubURLProtocol.handler = { _ in (204, "") }
        try await api.startElderSignUp(phoneNumber: "+31612345678", channel: .sms)
        var request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v2/auth/elderly/phone/start")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(body(of: request), #"{"phoneNumber":"+31612345678"}"#)

        StubURLProtocol.handler = { _ in (200, ContractFixtures.elderSignUpNew) }
        let response = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31612345678", code: "123456"))
        request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v2/auth/elderly/phone/verify")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(response.needsOnboarding)

        // Wrong code: 400, never a sign-out or an unpaired phone.
        StubURLProtocol.handler = { _ in (400, #"{ "error": { "code": "ongeldige_code", "message": "Deze code klopt niet." } }"#) }
        do {
            _ = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31612345678", code: "000000"))
            XCTFail("expected 400")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "ongeldige_code")
            XCTAssertTrue(error.elderMessage.contains("Probeert u"))
        }
        XCTAssertEqual(storage.deviceToken, "hnd_self")

        let calls: [(String, String, () async throws -> Void)] = [
            ("GET", "/api/v2/device/profile", { _ = try await api.deviceProfile() }),
            ("PATCH", "/api/v2/device/profile", { _ = try await api.updateDeviceProfile(DeviceProfilePatch(preferredName: "Toos", addressForm: .u)) }),
            ("GET", "/api/v2/device/settings", { _ = try await api.deviceSettings() }),
            ("PATCH", "/api/v2/device/settings", { _ = try await api.updateDeviceSettings(NoahSettingsPatch(voiceOnly: .man)) }),
            ("GET", "/api/v2/device/emergency-contacts", { _ = try await api.deviceEmergencyContacts() }),
            ("POST", "/api/v2/device/emergency-contacts", { _ = try await api.createDeviceEmergencyContact(EmergencyContactInput(name: "Ellen", phoneNumber: "+31656781234")) }),
            ("PATCH", "/api/v2/device/emergency-contacts/E21", { _ = try await api.updateDeviceEmergencyContact(contactId: "E21", EmergencyContactInput(name: "Ellen", phoneNumber: "+31656781234")) }),
            ("DELETE", "/api/v2/device/emergency-contacts/E21", { try await api.deleteDeviceEmergencyContact(contactId: "E21") }),
            ("GET", "/api/v2/device/subscription", { _ = try await api.deviceSubscription() }),
            ("POST", "/api/v2/device/subscriptions/app-store", { _ = try await api.submitDeviceAppStoreTransaction(signedTransaction: "jws") }),
            ("POST", "/api/v2/device/invitations", { _ = try await api.createDeviceInvitation(role: .beheerder) }),
            ("GET", "/api/v2/device/caregivers", { _ = try await api.deviceCaregivers() }),
            ("DELETE", "/api/v2/device/caregivers/c1", { try await api.removeDeviceCaregiver(caregiverId: "c1") }),
            ("GET", "/api/v2/device/export", { _ = try await api.exportDevice() }),
            ("DELETE", "/api/v2/device/account", { try await api.deleteDeviceAccount() }),
        ]
        for (method, path, call) in calls {
            StubURLProtocol.handler = { request in
                switch request.url?.path ?? "" {
                case "/api/v2/device/profile": return (200, ContractFixtures.deviceProfile)
                case "/api/v2/device/settings": return (200, ContractFixtures.settings)
                case "/api/v2/device/emergency-contacts": return (request.httpMethod == "GET" ? 200 : 201, request.httpMethod == "GET" ? ContractFixtures.emergencyContacts : ContractFixtures.emergencyContact)
                case "/api/v2/device/emergency-contacts/E21": return (request.httpMethod == "DELETE" ? 204 : 200, request.httpMethod == "DELETE" ? "" : ContractFixtures.emergencyContact)
                case "/api/v2/device/subscription", "/api/v2/device/subscriptions/app-store": return (200, ContractFixtures.subscription)
                case "/api/v2/device/invitations": return (201, ContractFixtures.invitation)
                case "/api/v2/device/caregivers": return (200, ContractFixtures.caregivers)
                case "/api/v2/device/export": return (200, "{}")
                default: return (204, "")
                }
            }
            try await call()
            let request = try XCTUnwrap(StubURLProtocol.requests.first, path)
            XCTAssertEqual(request.httpMethod, method, path)
            XCTAssertEqual(request.url?.path, path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hnd_self", path)
            if path.hasSuffix("/account") { XCTAssertEqual(body(of: request), #"{"confirm":"VERWIJDER"}"#) }
            if path.hasSuffix("/app-store") { XCTAssertEqual(body(of: request), #"{"signedTransaction":"jws"}"#) }
            if path.hasSuffix("/invitations") { XCTAssertEqual(body(of: request), #"{"role":"beheerder"}"#) }
        }
    }

    func testElderMessagesForTheNewCodes() {
        let managed = APIError.server(status: 403, code: "beheerd_door_mantelzorger", message: nil).elderMessage
        XCTAssertTrue(managed.contains("Uw familie"), managed)
        XCTAssertFalse(APIError.isFormal(APIError.caregiverMessage(code: "abonnement_ander_profiel")!))
        for code in ["ongeldige_code", "te_veel_verzoeken", "sms_mislukt", "niet_beschikbaar"] {
            let text = APIError.server(status: 400, code: code, message: "Probeer het opnieuw").elderMessage
            XCTAssertTrue(APIError.isFormal(text), "\(code): \(text)")
        }
        // A self-managed person is never told to ask a caregiver.
        XCTAssertFalse(ConversationController.Failure.inactiveSelf.text.contains("mantelzorger"))
        XCTAssertTrue(ConversationController.Failure.inactiveSelf.isInactive)
        XCTAssertTrue(ConversationController.Failure.inactive.text.contains("mantelzorger"))
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

/// v2.3 point 4: the first product this Apple ID doesn't own; the 4th is explained.
final class ProductSelectionTests: XCTestCase {
    private let p = Plan.productIDs

    func testThreeProductsInSeparateGroups() {
        XCTAssertEqual(p, ["ai.hellonoah.abonnement.maand", "ai.hellonoah.abonnement.maand.2", "ai.hellonoah.abonnement.maand.3"])
        XCTAssertEqual(Plan.productID, "ai.hellonoah.abonnement.maand")
        XCTAssertEqual(Plan.maxPerAppleID, 3)
    }

    func testPicksTheFirstProductNotOwned() {
        XCTAssertEqual(ProductChoice.choose(owned: [], elderlyId: "c"), .buy(productID: p[0]))
        XCTAssertEqual(ProductChoice.choose(owned: [.init(productID: p[0], elderlyId: "a")], elderlyId: "c"), .buy(productID: p[1]))
        // Gaps are filled first (a cancelled first subscription frees "Noah").
        XCTAssertEqual(ProductChoice.choose(owned: [.init(productID: p[1], elderlyId: "b")], elderlyId: "c"), .buy(productID: p[0]))
        XCTAssertEqual(ProductChoice.choose(owned: [.init(productID: p[0], elderlyId: "a"), .init(productID: p[1], elderlyId: "b")], elderlyId: "c"),
                       .buy(productID: p[2]))
        // A purchase without appAccountToken still occupies its group.
        XCTAssertEqual(ProductChoice.choose(owned: [.init(productID: p[0], elderlyId: nil)], elderlyId: "c"), .buy(productID: p[1]))
        // Other products (old ids) never block a group.
        XCTAssertEqual(ProductChoice.choose(owned: [.init(productID: "ai.hellonoah.unlimited.monthly", elderlyId: "a")], elderlyId: "c"), .buy(productID: p[0]))
    }

    func testAlreadyPaidForThisProfile() {
        let owned: [OwnedSubscription] = [.init(productID: p[0], elderlyId: "a"), .init(productID: p[1], elderlyId: "8e5c2d1a-4b7f-4c2a-9f3e-1a2b3c4d5e6f")]
        XCTAssertEqual(ProductChoice.choose(owned: owned, elderlyId: "8E5C2D1A-4B7F-4C2A-9F3E-1A2B3C4D5E6F"), .alreadyForThisProfile(productID: p[1]))
    }

    func testTheFourthIsExplained() {
        let owned: [OwnedSubscription] = [.init(productID: p[0], elderlyId: "a"), .init(productID: p[1], elderlyId: "b"), .init(productID: p[2], elderlyId: "c")]
        let choice = ProductChoice.choose(owned: owned, elderlyId: "d")
        XCTAssertEqual(choice, .allInUse(owned: owned))
        XCTAssertNil(choice.productID)
        // ...but a profile that is among the three is "already paid", not "all in use".
        XCTAssertEqual(ProductChoice.choose(owned: owned, elderlyId: "C"), .alreadyForThisProfile(productID: p[2]))
    }

    @MainActor
    func testExplanationsSpeakToTheirReader() {
        let store = SubscriptionStore()
        let owned: [OwnedSubscription] = p.map { .init(productID: $0, elderlyId: nil) }
        store.audience = .caregiver
        let caregiver = store.allInUseExplanation(owned: owned, targetName: "Wim")
        XCTAssertTrue(caregiver.contains("betaal je al 3 abonnementen"), caregiver)
        store.audience = .elder
        let elder = store.allInUseExplanation(owned: owned, targetName: "Toos")
        XCTAssertTrue(elder.contains("Met deze Apple ID worden al 3 abonnementen betaald"), elder)
        XCTAssertNil(elder.range(of: "\\bje\\b", options: .regularExpression), elder)

        let formal = SubscriptionStore.redeemOutcome(for: .offline, formal: true)
        XCTAssertFalse(formal.finish)
        XCTAssertNil(formal.message.range(of: "\\b(je|jouw)\\b", options: .regularExpression))
        XCTAssertTrue(SubscriptionStore.redeemOutcome(for: .server(status: 400, code: "abonnement_ander_profiel", message: nil), formal: true).message.contains("uw Apple ID"))
    }

    func testMockJWSNamesTheProduct() {
        XCTAssertEqual(MockNoahAPI.productID(fromMockJWS: "mock-signed-transaction:\(p[2])"), p[2])
        XCTAssertEqual(MockNoahAPI.productID(fromMockJWS: "mock-signed-transaction"), p[0])
        XCTAssertEqual(MockNoahAPI.productID(fromMockJWS: "mock-signed-transaction:iets.anders"), p[0])
    }

    /// Mock mode simulates up to three purchases on one Apple ID, then explains; never StoreKit.
    @MainActor
    func testSimulatedPurchasesUseEachProductOnce() async throws {
        UserDefaults.standard.set(MockIDs.wim, forKey: "mockAppleIDPaysFor")
        defer { UserDefaults.standard.removeObject(forKey: "mockAppleIDPaysFor") }
        let store = SubscriptionStore()
        store.usesMockBackend = true
        store.start()
        var submitted: [String] = []
        store.submit = { _, jws in
            submitted.append(jws)
            return Subscription(status: .intro, productId: MockNoahAPI.productID(fromMockJWS: jws), platform: "app_store", paidByMe: true)
        }

        let v1 = await store.choice(for: MockIDs.wim)
        XCTAssertEqual(v1, .alreadyForThisProfile(productID: p[0]))
        let v2 = await store.purchase(elderlyId: MockIDs.wim)
        XCTAssertNil(v2)
        XCTAssertTrue(submitted.isEmpty)

        let second = await store.purchase(elderlyId: MockIDs.riet)
        XCTAssertEqual(second?.productId, p[1])
        let third = await store.purchase(elderlyId: MockIDs.toos)
        XCTAssertEqual(third?.productId, p[2])
        XCTAssertEqual(submitted, ["mock-signed-transaction:\(p[1])", "mock-signed-transaction:\(p[2])"])

        let fourth = await store.purchase(elderlyId: UUID().uuidString)
        XCTAssertNil(fourth)
        XCTAssertEqual(submitted.count, 2)
        XCTAssertTrue(store.errorMessage?.contains("Meer dan 3") == true, store.errorMessage ?? "")
    }
}

/// v2.3 mock: sign-up, self-managed device endpoints and the switch to caregiver-managed.
final class SelfRouteMockTests: XCTestCase {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(0.0, forKey: "mockLatency")
        defaults.set(MockIDs.anna, forKey: "mock.currentCaregiver")
        return defaults
    }

    func testSignUpCreatesASelfProfileOrPairsToTheFamily() async throws {
        let defaults = makeDefaults("SelfRoute.signUp")
        var token: String?
        let api = MockNoahAPI(defaults: defaults, deviceToken: { token })

        try await api.startElderSignUp(phoneNumber: "+31612349876", channel: .sms)
        do {
            _ = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31612349876", code: "000000"))
            XCTFail("000000 is rejected")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.code, "ongeldige_code")
        }

        let new = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31612349876", code: "123456"))
        XCTAssertTrue(new.needsOnboarding)
        token = new.deviceToken
        let profile = try await api.deviceProfile()
        XCTAssertTrue(profile.isSelfManaged)
        XCTAssertEqual(profile.phoneNumber, "+31612349876")
        let renamed = try await api.updateDeviceProfile(DeviceProfilePatch(preferredName: "Bep", addressForm: .jij))
        XCTAssertEqual(renamed.preferredName, "Bep")
        XCTAssertEqual(renamed.addressForm, .jij)

        // The number of a caregiver-managed profile pairs this phone to it.
        let family = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31623456789", code: "123456", preferredName: "Willem"))
        XCTAssertTrue(family.isLinkedToFamily)
        XCTAssertEqual(family.elderly.id, MockIDs.wim)
        XCTAssertEqual(family.elderly.preferredName, "Wim")

        // Signing up again with the self number signs the same person in.
        let again = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31612349876", code: "654321"))
        XCTAssertEqual(again.elderly.id, new.elderly.id)
        XCTAssertEqual(again.managedBy, .zelf)
        XCTAssertFalse(again.isNewProfile)

        // A relaunch (new mock, same defaults) still knows the self sign-up.
        let relaunched = MockNoahAPI(defaults: defaults, deviceToken: { token })
        let restored = try await relaunched.deviceProfile()
        XCTAssertEqual(restored.preferredName, "Bep")
        XCTAssertTrue(restored.isSelfManaged)
    }

    func testFreeFirstConversationThenInactive() async throws {
        var token: String?
        let api = MockNoahAPI(defaults: makeDefaults("SelfRoute.trial"), deviceToken: { token })
        let new = try await api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: "+31612340001", code: "123456"))
        token = new.deviceToken
        let before = try await api.deviceSubscription()
        XCTAssertEqual(before.freeConversationsLeft, 1)
        XCTAssertFalse(before.isPaidOrBeta)
        _ = try await api.startDeviceConversation(mode: .gesprek)
        do {
            _ = try await api.startDeviceConversation(mode: .gesprek)
            XCTFail("the trial is one conversation")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "inactive")
        }
        let paid = try await api.submitDeviceAppStoreTransaction(signedTransaction: "mock-signed-transaction:\(Plan.productIDs[1])")
        XCTAssertEqual(paid.productId, Plan.productIDs[1])
        let v3 = try await api.deviceMe().access
        XCTAssertEqual(v3, .active)
    }

    func testDeviceEndpointsOnlyForSelfManagedProfiles() async throws {
        let wimPhone = MockNoahAPI(defaults: makeDefaults("SelfRoute.wim"), deviceToken: { "hnd_mock_\(MockIDs.wim)" })
        let v4 = try await wimPhone.deviceProfile().isSelfManaged
        XCTAssertFalse(v4)
        let v5 = try await wimPhone.deviceSubscription().paidByMe
        XCTAssertEqual(v5, false)
        let v6 = try await wimPhone.deviceCaregivers().isEmpty
        XCTAssertFalse(v6)
        for call in [{ _ = try await wimPhone.deviceSettings() }, { _ = try await wimPhone.deviceEmergencyContacts() },
                     { _ = try await wimPhone.createDeviceInvitation(role: .lezer) }, { try await wimPhone.deleteDeviceAccount() }] as [() async throws -> Void] {
            do {
                try await call()
                XCTFail("caregiver-managed")
            } catch let error as APIError {
                XCTAssertEqual(error.status, 403)
                XCTAssertEqual(error.code, "beheerd_door_mantelzorger")
            }
        }
    }

    func testSelfManagedSettingsContactsInvitationsAndDeletion() async throws {
        let defaults = makeDefaults("SelfRoute.toos")
        let toos = MockNoahAPI(defaults: defaults, deviceToken: { "hnd_mock_\(MockIDs.toos)" })
        let v7 = try await toos.deviceProfile().isSelfManaged
        XCTAssertTrue(v7)

        let settings = try await toos.deviceSettings()
        var wanted = settings
        wanted.recording = .levensverhaal
        wanted.voice = .man
        let updated = try await toos.updateDeviceSettings(NoahSettingsPatch(from: settings, to: wanted))
        XCTAssertEqual(updated.recording, .levensverhaal)
        XCTAssertEqual(updated.voice, .man)

        let contact = try await toos.createDeviceEmergencyContact(EmergencyContactInput(name: "Buurman Piet", phoneNumber: "+31687650000"))
        let v8 = try await toos.deviceEmergencyContacts().count
        XCTAssertEqual(v8, 2)
        try await toos.deleteDeviceEmergencyContact(contactId: contact.id)
        let v9 = try await toos.deviceEmergencyContacts().count
        XCTAssertEqual(v9, 1)

        let caregivers = try await toos.deviceCaregivers()
        XCTAssertEqual(caregivers.map(\.name), ["Ellen Bakker"])
        try await toos.removeDeviceCaregiver(caregiverId: MockIDs.ellen)
        let v10 = try await toos.deviceCaregivers().isEmpty
        XCTAssertTrue(v10)

        // A "helpen beheren" invitation, once accepted, hands the settings to the caregiver.
        let invitation = try await toos.createDeviceInvitation(role: .beheerder)
        XCTAssertTrue(invitation.shareText?.hasPrefix("Ik gebruik Noah en nodig je uit") == true)
        let accepted = try await toos.acceptInvitation(code: invitation.code)
        XCTAssertEqual(accepted.role, .beheerder)
        let v11 = try await toos.deviceProfile().isSelfManaged
        XCTAssertFalse(v11)
        do {
            _ = try await toos.deviceSettings()
            XCTFail("now caregiver-managed")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "beheerd_door_mantelzorger")
        }

        // Deleting is only for self profiles, and removes everything.
        let other = MockNoahAPI(defaults: makeDefaults("SelfRoute.delete"), deviceToken: { "hnd_mock_\(MockIDs.toos)" })
        let export = try await other.exportDevice()
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: export) as? [String: Any])
        try await other.deleteDeviceAccount()
        await MainActor.run {} // let the mock settle
        let v12 = try await other.deviceProfile().preferredName
        XCTAssertNotEqual(v12, "Toos")
    }
}

/// v2.3: the older person's session decides between caregiver-managed and self-managed.
@MainActor
final class ElderSessionSelfTests: XCTestCase {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(0.0, forKey: "mockLatency")
        return defaults
    }

    func testSelfManagedSessionRedeemsOnlyItsOwnPurchases() async {
        let defaults = makeDefaults("ElderSession.toos")
        let store = SubscriptionStore()
        let session = ElderSession(api: MockNoahAPI(defaults: defaults, deviceToken: { "hnd_mock_\(MockIDs.toos)" }),
                                   reachability: Reachability(), subscriptions: store, defaults: defaults, makeEngine: { MockVoiceEngine() })
        XCTAssertFalse(session.isSelfManaged)
        await session.load()
        XCTAssertTrue(session.isSelfManaged)
        XCTAssertEqual(session.name, "Toos")
        XCTAssertEqual(store.audience, .elder)
        XCTAssertTrue(store.redeemsOnlyKnownProfiles)
        XCTAssertEqual(store.knownElderlyIds, [MockIDs.toos])
        XCTAssertNotNil(store.submit)
        XCTAssertTrue(session.makeConversationController().isSelfManaged)
    }

    func testCaregiverManagedSessionNeverRedeems() async {
        let defaults = makeDefaults("ElderSession.wim")
        let store = SubscriptionStore()
        let session = ElderSession(api: MockNoahAPI(defaults: defaults, deviceToken: { "hnd_mock_\(MockIDs.wim)" }),
                                   reachability: Reachability(), subscriptions: store, defaults: defaults, makeEngine: { MockVoiceEngine() })
        await session.load()
        XCTAssertFalse(session.isSelfManaged)
        XCTAssertNil(store.submit)
        XCTAssertTrue(store.knownElderlyIds.isEmpty)
        XCTAssertFalse(session.makeConversationController().isSelfManaged)
    }

    func testOnboardingSurvivesARelaunch() {
        let defaults = makeDefaults("ElderSession.onboarding")
        let api = MockNoahAPI(defaults: defaults)
        let first = ElderSession(api: api, reachability: Reachability(), subscriptions: SubscriptionStore(), defaults: defaults, makeEngine: { MockVoiceEngine() })
        XCTAssertFalse(first.isOnboarding)
        first.startOnboarding()
        let relaunched = ElderSession(api: api, reachability: Reachability(), subscriptions: SubscriptionStore(), defaults: defaults, makeEngine: { MockVoiceEngine() })
        XCTAssertTrue(relaunched.isOnboarding)
        relaunched.finishOnboarding()
        XCTAssertFalse(relaunched.isOnboarding)
        XCTAssertNotNil(relaunched.arrivalMessage)
        XCTAssertFalse(ElderSession(api: api, reachability: Reachability(), subscriptions: SubscriptionStore(), defaults: defaults, makeEngine: { MockVoiceEngine() }).isOnboarding)
    }

    func testElderSpeedChoices() {
        XCTAssertEqual(ElderSpeed.nearest(to: 0.85), .rustiger)
        XCTAssertEqual(ElderSpeed.nearest(to: 1.0), .normaal)
        XCTAssertEqual(ElderSpeed.nearest(to: 1.2), .vlotter)
        XCTAssertTrue(ElderSpeed.allCases.allSatisfy { NoahSettings.speedRange.contains($0.value) })
        XCTAssertEqual(Role.lezer.elderLabel, "Meekijken")
        XCTAssertEqual(Role.beheerder.elderLabel, "Helpen beheren")
    }
}
