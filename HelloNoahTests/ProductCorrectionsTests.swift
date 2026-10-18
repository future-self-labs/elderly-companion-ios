import XCTest
@testable import HelloNoah

/// Contract v2.1 (2026-10-17): fair use instead of "unlimited", recording as a choice, story mode,
/// audio playback, reminders as a memory aid and honest privacy copy.
final class ProductCorrectionsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try NoahJSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: NoahJSON.encoder.encode(AnyEncodable(value))) as? [String: Any])
    }

    // MARK: 1. Fair use, one plan name, new product id

    func testPlanNameAndProductId() {
        XCTAssertEqual(Plan.displayName, "HelloNoah-abonnement")
        XCTAssertEqual(SubscriptionStore.productID, "ai.hellonoah.abonnement.maand")
        XCTAssertEqual(Plan.fairUseMonthlyMinutes, 600)
    }

    func testSubscriptionUsageDecodes() throws {
        let subscription = try decode(Subscription.self, ContractFixtures.subscriptionV21)
        let usage = try XCTUnwrap(subscription.usage)
        XCTAssertEqual(usage.minutesThisMonth, 212)
        XCTAssertEqual(usage.allowanceMinutes, 600)
        XCTAssertFalse(usage.overAllowance)
        XCTAssertEqual(usage.resetsAt, NoahJSON.parseDate("2026-10-31T23:00:00Z"), "offsets like +01:00 must parse")
        XCTAssertEqual(usage.fraction, 212.0 / 600, accuracy: 0.0001)
        XCTAssertEqual(DutchFormat.shortDate(try XCTUnwrap(usage.resetsAt)), "1 november 2026")
        // Before v2.1 there is no usage.
        XCTAssertNil(try decode(Subscription.self, ContractFixtures.subscription).usage)
    }

    func testFairUseCopyNeverClaimsUnlimited() {
        let text = ProductCopy.fairUse(name: "Wim", allowanceMinutes: 600)
        XCTAssertTrue(text.contains("10 uur per maand"), text)
        XCTAssertTrue(text.contains("gewoon bereikbaar"), text)
        XCTAssertFalse(text.lowercased().contains("onbeperkt"))
        XCTAssertEqual(DutchFormat.hours(minutes: 600), "10 uur")
        XCTAssertEqual(DutchFormat.hours(minutes: 90), "1,5 uur")
        XCTAssertEqual(DutchFormat.hours(minutes: 45), "45 minuten")
    }

    func testMockUsageAndOverAllowanceShortensConversations() async throws {
        let defaults = makeDefaults("ProductCorrections.over")
        defaults.set(true, forKey: "mockOverAllowance")
        let api = MockNoahAPI(defaults: defaults)
        let overSubscription = try await api.subscription(elderlyId: MockIDs.wim)
        let usage = try XCTUnwrap(overSubscription.usage)
        XCTAssertTrue(usage.overAllowance)
        // Noah keeps working, with 10-minute conversations.
        let session = try await api.startDeviceConversation(mode: .gesprek)
        XCTAssertEqual(session.maxDurationSeconds, Plan.cappedConversationMinutes * 60)

        let normal = MockNoahAPI(defaults: makeDefaults("ProductCorrections.normal"))
        let normalSubscription = try await normal.subscription(elderlyId: MockIDs.wim)
        let normalUsage = try XCTUnwrap(normalSubscription.usage)
        XCTAssertFalse(normalUsage.overAllowance)
        XCTAssertLessThan(normalUsage.minutesThisMonth, normalUsage.allowanceMinutes)
        XCTAssertNotNil(normalUsage.resetsAt)
    }

    // MARK: 2. Recording is a choice

    func testRecordingSettingDecodesAndEncodes() throws {
        let settings = try decode(NoahSettings.self, ContractFixtures.settingsV21)
        XCTAssertEqual(settings.recording, .levensverhaal)
        XCTAssertEqual(try object(settings)["recording"] as? String, "levensverhaal")

        // An older backend without the field: default "uit".
        XCTAssertEqual(try decode(NoahSettings.self, ContractFixtures.settings).recording, .uit)
        XCTAssertEqual(NoahSettings.defaults.recording, .uit)

        var all = settings
        all.recording = .alleGesprekken
        XCTAssertEqual(try object(all)["recording"] as? String, "alle_gesprekken")

        // A value this app doesn't know is never sent back.
        let future = try decode(NoahSettings.self, ContractFixtures.settingsV21.replacingOccurrences(of: "\"levensverhaal\"", with: "\"iets_nieuws\""))
        XCTAssertEqual(future.recording, .unknown)
        XCTAssertNil(try object(future)["recording"])
    }

    func testMockRecordsOnlyWhatTheSettingAllows() async throws {
        let api = MockNoahAPI(defaults: makeDefaults("ProductCorrections.recording"))
        // Wim: "alleen bij levensverhalen".
        let initial = try await api.settings(elderlyId: MockIDs.wim)
        XCTAssertEqual(initial.recording, .levensverhaal)
        var session = try await api.startDeviceConversation(mode: .gesprek)
        XCTAssertEqual(session.mode, .gesprek)
        XCTAssertFalse(session.recording)
        session = try await api.startDeviceConversation(mode: .levensverhaal)
        XCTAssertEqual(session.mode, .levensverhaal)
        XCTAssertTrue(session.recording)

        var settings = try await api.settings(elderlyId: MockIDs.wim)
        settings.recording = .alleGesprekken
        _ = try await api.updateSettings(elderlyId: MockIDs.wim, NoahSettingsPatch(settings))
        let everything = try await api.startDeviceConversation(mode: .gesprek)
        XCTAssertTrue(everything.recording)

        settings.recording = .uit
        _ = try await api.updateSettings(elderlyId: MockIDs.wim, NoahSettingsPatch(settings))
        let nothing = try await api.startDeviceConversation(mode: .levensverhaal)
        XCTAssertFalse(nothing.recording)
    }

    /// Only a beheerder can change the recording setting.
    func testLezerCannotChangeRecording() async throws {
        let api = MockNoahAPI(defaults: makeDefaults("ProductCorrections.lezer"))
        var settings = NoahSettings.defaults
        settings.recording = .alleGesprekken
        do {
            _ = try await api.updateSettings(elderlyId: MockIDs.riet, NoahSettingsPatch(settings))
            XCTFail("a lezer must not change recording")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "alleen_lezen")
        }
    }

    // MARK: 3. Story mode

    func testConversationModeAndAudioFlag() throws {
        let summary = try decode(ConversationSummary.self, ContractFixtures.conversationSummaryV21)
        XCTAssertEqual(summary.mode, .levensverhaal)
        XCTAssertTrue(summary.hasAudio)
        let detail = try decode(ConversationDetail.self, ContractFixtures.conversationSummaryV21)
        XCTAssertEqual(detail.mode, .levensverhaal)
        XCTAssertTrue(detail.hasAudio)
        // Before v2.1: no mode, no audio.
        let old = try decode(ConversationSummary.self, ContractFixtures.conversationSummary)
        XCTAssertNil(old.mode)
        XCTAssertFalse(old.hasAudio)
        XCTAssertEqual(ConversationMode.levensverhaal.label, "Verhaal-gesprek")
    }

    func testCallNowResponseAndFairUseAlert() throws {
        let response = try decode(CallNowResponse.self, ContractFixtures.callNowV21)
        XCTAssertEqual(response.mode, .levensverhaal)
        XCTAssertEqual(response.recording, true)
        XCTAssertNil(try decode(CallNowResponse.self, ContractFixtures.callNow).recording)
        let alert = try decode(NoahAlert.self, ContractFixtures.verbruikAlert)
        XCTAssertEqual(alert.type, .verbruik)
        XCTAssertEqual(alert.type.label, "Redelijk gebruik")
    }

    func testDeviceConversationCarriesModeAndRecording() throws {
        let session = try decode(ConversationSession.self, ContractFixtures.deviceConversationV21)
        XCTAssertEqual(session.mode, .levensverhaal)
        XCTAssertTrue(session.recording)
        XCTAssertFalse(try decode(ConversationSession.self, ContractFixtures.deviceConversation).recording)
    }

    func testRequestsSendModeAndUseAudioPaths() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let storage = InMemoryTokenStorage(
            caregiverTokens: CaregiverTokens(accessToken: "a", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"),
            deviceToken: "hnd_1")
        let api = LiveNoahAPI(client: APIClient(baseURL: URL(string: "https://api.test/api/v2")!, storage: storage, session: URLSession(configuration: configuration)))

        StubURLProtocol.handler = { _ in (200, ContractFixtures.deviceConversationV21) }
        _ = try await api.startDeviceConversation(mode: .levensverhaal)
        var request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v2/device/conversation")
        XCTAssertEqual(body(of: request), #"{"mode":"levensverhaal"}"#)

        StubURLProtocol.handler = { _ in (202, ContractFixtures.callNow) }
        _ = try await api.callNow(elderlyId: "e1", mode: .levensverhaal)
        request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v2/elderly/e1/call-now")
        XCTAssertEqual(body(of: request), #"{"mode":"levensverhaal"}"#)

        StubURLProtocol.handler = { _ in (200, ContractFixtures.conversationAudio) }
        let audio = try await api.conversationAudio(conversationId: "conv2")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/v2/conversations/conv2/audio")
        XCTAssertEqual(audio.url.absoluteString, "https://storage.example.eu/audio/conv2.m4a?sig=abc")
        XCTAssertEqual(audio.durationSeconds, 734)
        XCTAssertEqual(audio.expiresAt, NoahJSON.parseDate("2026-10-17T10:15:00Z"))

        StubURLProtocol.handler = { _ in (200, ContractFixtures.conversationAudio) }
        _ = try await api.deviceConversationAudio(conversationId: "conv2")
        request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v2/device/conversations/conv2/audio")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hnd_1")

        StubURLProtocol.handler = { _ in (404, #"{ "error": { "code": "geen_opname", "message": "Er is geen opname." } }"#) }
        do {
            _ = try await api.conversationAudio(conversationId: "conv1")
            XCTFail("expected 404")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "geen_opname")
        }
    }

    // MARK: 4. Audio playback

    func testLifeStoryAudioFragment() throws {
        let entry = try decode(LifeStoryEntry.self, ContractFixtures.lifeStoryEntryV21)
        XCTAssertEqual(entry.audio, LifeStoryAudio(conversationId: "conv2", startSeconds: 312, durationSeconds: 734))
        let fromStart = try decode(LifeStoryEntry.self, ContractFixtures.lifeStoryEntryV21.replacingOccurrences(of: "\"startSeconds\": 312", with: "\"startSeconds\": null"))
        XCTAssertNil(fromStart.audio?.startSeconds)
        XCTAssertNil(try decode(LifeStoryEntry.self, ContractFixtures.lifeStoryEntry).audio)
    }

    func testSignedURLExpiry() {
        let now = Date()
        XCTAssertFalse(RecordingPlayer.needsFreshURL(expiresAt: nil, now: now))
        XCTAssertFalse(RecordingPlayer.needsFreshURL(expiresAt: now.addingTimeInterval(600), now: now))
        XCTAssertTrue(RecordingPlayer.needsFreshURL(expiresAt: now.addingTimeInterval(10), now: now), "refresh a little before expiry")
        XCTAssertTrue(RecordingPlayer.needsFreshURL(expiresAt: now.addingTimeInterval(-60), now: now))
    }

    @MainActor
    func testPlayerStartsAtTheFragmentAndReportsMissingRecording() async {
        let player = RecordingPlayer(startSeconds: 312) {
            throw APIError.server(status: 404, code: "geen_opname", message: nil)
        }
        XCTAssertEqual(player.position, 312)
        await player.togglePlayback()
        XCTAssertEqual(player.error?.code, "geen_opname")
        XCTAssertEqual(APIError.server(status: 404, code: "geen_opname", message: nil).userMessage, "Er is geen opname van dit gesprek.")
    }

    func testMockServesRecordingsOnlyWhereTheyExist() async throws {
        let api = MockNoahAPI(defaults: makeDefaults("ProductCorrections.audio"))
        let page = try await api.conversations(elderlyId: MockIDs.wim, cursor: nil, limit: 100)
        let recorded = try XCTUnwrap(page.items.first { $0.hasAudio })
        XCTAssertEqual(recorded.mode, .levensverhaal)
        let audio = try await api.conversationAudio(conversationId: recorded.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.url.path))
        XCTAssertGreaterThan(audio.expiresAt ?? .distantPast, Date())
        let ownVoice = try await api.deviceConversationAudio(conversationId: recorded.id)
        XCTAssertEqual(ownVoice.url, audio.url)

        let unrecorded = try XCTUnwrap(page.items.first { !$0.hasAudio })
        do {
            _ = try await api.conversationAudio(conversationId: unrecorded.id)
            XCTFail("expected geen_opname")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "geen_opname")
            XCTAssertEqual(error.status, 404)
        }

        let story = try await api.lifeStory(elderlyId: MockIDs.wim, category: nil, cursor: nil, limit: 50).items
        let wedding = try XCTUnwrap(story.first { $0.title == "De trouwdag met Margriet" })
        XCTAssertEqual(wedding.audio?.conversationId, "C0A1B2C3-0000-4000-8000-000000000006")
        let weddingAudio = try await api.conversationAudio(conversationId: try XCTUnwrap(wedding.audio).conversationId)
        XCTAssertEqual(weddingAudio.durationSeconds, MockRecording.durationSeconds)
    }

    func testMockRecordingIsAValidWav() throws {
        let data = MockRecording.wavData()
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(data.count, 44 + Int(MockRecording.durationSeconds) * 11_025 * 2)
    }

    // MARK: 5. Reminders are a memory aid

    func testRemindersAreAMemoryAid() {
        XCTAssertEqual(ReminderType.medicatie.label, "Medicijnen (geheugensteun)")
        XCTAssertEqual(ProductCopy.reminderDisclaimer,
                       "Noah's herinneringen zijn een extra geheugensteuntje, naast wat er al is (zoals een medicijndoos, de apotheek, thuiszorg of je eigen berichtjes). Noah houdt geen medicijngebruik bij en is geen medisch hulpmiddel. Vertrouw er niet als enige op: een gemist gesprek of een storing kan altijd.")
        XCTAssertTrue(ProductCopy.elderReminderNote.contains("naast wat u al gebruikt"))
    }

    // MARK: 6. Honest privacy copy

    func testPrivacyCopyIsHonest() {
        XCTAssertEqual(ProductCopy.privacy,
                       "Gesprekken en gegevens worden versleuteld opgeslagen in de EU. Voor het gesprek zelf gebruikt Noah gespecialiseerde spraak- en AI-diensten; die bewaren geen gegevens langer dan nodig. Opnames alleen als jij dat aanzet én je naaste toestemming geeft.")
    }

    /// No shipped string may claim unlimited talking, "no recordings" or "all data in the EU".
    func testNoForbiddenClaimsInShippedStrings() throws {
        let bundle = Bundle(for: MockNoahAPI.self)
        var texts: [String] = []
        for table in ["Localizable", "InfoPlist"] {
            let path = try XCTUnwrap(bundle.path(forResource: table, ofType: "strings", inDirectory: nil, forLocalization: "nl")
                                        ?? bundle.path(forResource: table, ofType: "strings"), "\(table).strings missing")
            let dictionary = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            texts += Array(dictionary.keys) + Array(dictionary.values)
        }
        texts += [bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String ?? ""]
        XCTAssertGreaterThan(texts.count, 100)
        for text in texts {
            let lower = text.lowercased()
            for forbidden in ["onbeperkt", "unlimited", "geen geluidsopnames", "geluidsopnames worden niet", "alle gegevens staan"] {
                XCTAssertFalse(lower.contains(forbidden), "\"\(forbidden)\" in: \(text)")
            }
        }
    }

    // MARK: Helpers

    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(0.0, forKey: "mockLatency")
        defaults.set(MockIDs.anna, forKey: "mock.currentCaregiver")
        return defaults
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
