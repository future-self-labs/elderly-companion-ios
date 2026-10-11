import XCTest
@testable import HelloNoah

/// Decodes every example of the API v2 contract into the app's models.
final class ContractDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        do {
            return try NoahJSON.decoder.decode(T.self, from: Data(json.utf8))
        } catch {
            XCTFail("Decoding \(T.self) failed: \(error)", file: file, line: line)
            throw error
        }
    }

    func testAuthResponse() throws {
        let auth = try decode(AuthResponse.self, ContractFixtures.authResponse)
        XCTAssertEqual(auth.refreshToken, "hnr_abc123")
        XCTAssertEqual(auth.caregiver?.name, "Anna de Vries")
        XCTAssertNil(auth.caregiver?.phoneNumber)
        XCTAssertTrue(auth.isNewAccount)
        XCTAssertEqual(auth.accessTokenExpiresAt, NoahJSON.parseDate("2026-10-11T09:00:00Z"))
    }

    func testPairing() throws {
        let code = try decode(PairingCode.self, ContractFixtures.pairingCode)
        XCTAssertEqual(code.code, "482913")
        let paired = try decode(PairDeviceResponse.self, ContractFixtures.pairDevice)
        XCTAssertEqual(paired.deviceToken, "hnd_xyz")
        XCTAssertEqual(paired.elderly.preferredName, "Wim")
        XCTAssertEqual(paired.elderly.noahName, "Noah")
    }

    func testMe() throws {
        let me = try decode(MeResponse.self, ContractFixtures.me)
        XCTAssertEqual(me.elderly.count, 1)
        XCTAssertEqual(me.elderly[0].role, .beheerder)
        XCTAssertEqual(me.elderly[0].access, .active)
        XCTAssertEqual(me.elderly[0].openAlertCount, 1)
    }

    func testElderlyProfile() throws {
        let profile = try decode(ElderlyProfile.self, ContractFixtures.elderlyProfile)
        XCTAssertEqual(profile.preferredName, "Wim")
        XCTAssertEqual(profile.addressForm, .u)
        XCTAssertEqual(profile.gender, .man)
        XCTAssertEqual(profile.livingSituation, .alleen)
        XCTAssertEqual(profile.likes, ["tuinieren", "Ajax", "Toon Hermans"])
        XCTAssertEqual(profile.topicsToAvoid.count, 1)
        XCTAssertEqual(profile.myRole, .beheerder)
        XCTAssertFalse(profile.isBeta)
        XCTAssertEqual(profile.fullName, "Willem de Vries")
    }

    func testPeople() throws {
        let people = try decode(ItemsResponse<Person>.self, ContractFixtures.people).items
        XCTAssertEqual(people.count, 2)
        XCTAssertEqual(people[0].birthday, "1972-05-14")
        XCTAssertEqual(people[1].createdBy, .noah)
        XCTAssertTrue(people[1].isDeceased)
    }

    func testNoahSettings() throws {
        let settings = try decode(NoahSettings.self, ContractFixtures.settings)
        XCTAssertEqual(settings.voice, .vrouw)
        XCTAssertEqual(settings.speakingSpeed, 1.0)
        XCTAssertEqual(settings.morningCall.weekdays, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(settings.quietHours.start, "21:30")
        XCTAssertEqual(settings, NoahSettings.defaults)
    }

    func testEmergencyContactsCaregiversInvitationsDevices() throws {
        let contacts = try decode(ItemsResponse<EmergencyContact>.self, ContractFixtures.emergencyContacts).items
        XCTAssertEqual(contacts.first?.priority, 1)
        let caregivers = try decode(ItemsResponse<CaregiverMembership>.self, ContractFixtures.caregivers).items
        XCTAssertEqual(caregivers.map(\.role), [.beheerder, .lezer])
        XCTAssertTrue(caregivers[0].isMe)
        let invitation = try decode(Invitation.self, ContractFixtures.invitation)
        XCTAssertEqual(invitation.code, "K7P-2QX")
        let accepted = try decode(AcceptInvitationResponse.self, ContractFixtures.acceptInvitation)
        XCTAssertEqual(accepted.role, .lezer)
        let devices = try decode(ItemsResponse<PairedDevice>.self, ContractFixtures.devices).items
        XCTAssertEqual(devices.first?.deviceName, "iPhone van Wim")
        XCTAssertNotNil(devices.first?.lastSeenAt, "fractional seconds must parse")
    }

    func testDashboard() throws {
        let dashboard = try decode(Dashboard.self, ContractFixtures.dashboard)
        XCTAssertEqual(dashboard.week.conversations, 9)
        XCTAssertEqual(dashboard.week.averageMood, 3.8)
        XCTAssertEqual(dashboard.moodTrend.count, 2)
        XCTAssertNil(dashboard.moodTrend[1].mood)
        XCTAssertEqual(dashboard.latestConversation?.channel, .app)
        XCTAssertEqual(dashboard.openAlerts.first?.type, .lageStemming)
        XCTAssertEqual(dashboard.upcomingReminders.count, 1)
        XCTAssertEqual(dashboard.lifeStory.entries, 23)
        XCTAssertEqual(dashboard.lifeStory.latest?.category, .familie)
    }

    func testConversations() throws {
        let page = try decode(Page<ConversationSummary>.self, ContractFixtures.conversationsPage)
        XCTAssertEqual(page.nextCursor, "abc")
        XCTAssertEqual(page.items.first?.durationSeconds, 734)
        let detail = try decode(ConversationDetail.self, ContractFixtures.conversationDetail)
        XCTAssertEqual(detail.channel, .telefoonIn)
        XCTAssertEqual(detail.cognitiveClarity, 5)
        XCTAssertEqual(detail.transcript.map(\.role), [.noah, .oudere])
        XCTAssertEqual(detail.transcript.first?.atSeconds, 12)
        XCTAssertEqual(detail.lifeStoryEntryIds, ["ls1"])
    }

    func testMood() throws {
        let mood = try decode(MoodOverview.self, ContractFixtures.mood)
        XCTAssertEqual(mood.trend, .stabiel)
        XCTAssertEqual(mood.average, 3.7)
        XCTAssertNil(mood.days[1].cognitiveClarity)
    }

    func testLifeStory() throws {
        let page = try decode(Page<LifeStoryEntry>.self, ContractFixtures.lifeStoryPage)
        XCTAssertNil(page.nextCursor)
        XCTAssertEqual(page.items.first?.quote, "Niemand ging naar binnen.")
        XCTAssertEqual(page.items.first?.year, 1962)
    }

    func testRemindersAllScheduleKinds() throws {
        let reminders = try decode(ItemsResponse<Reminder>.self, ContractFixtures.remindersList).items
        XCTAssertEqual(reminders.count, 3)
        XCTAssertEqual(reminders[0].schedule, .once(at: NoahJSON.parseDate("2026-10-14T13:30:00Z")!))
        XCTAssertEqual(reminders[1].schedule, .daily(time: "08:00"))
        XCTAssertEqual(reminders[2].schedule, .weekly(time: "10:00", weekdays: [2, 4]))
        XCTAssertEqual(reminders[0].delivery, .bellen)
        XCTAssertEqual(reminders[1].delivery, .inGesprek)
        XCTAssertFalse(reminders[2].active)
    }

    func testAlerts() throws {
        let page = try decode(Page<NoahAlert>.self, ContractFixtures.alertsPage)
        let alert = try XCTUnwrap(page.items.first)
        XCTAssertEqual(alert.severity, .waarschuwing)
        XCTAssertEqual(alert.status, .open)
        XCTAssertNil(alert.acknowledgedBy)
    }

    func testCallsPhoneLineSubscription() throws {
        XCTAssertEqual(try decode(CallNowResponse.self, ContractFixtures.callNow).status, "gestart")
        let line = try decode(PhoneLine.self, ContractFixtures.phoneLine)
        XCTAssertEqual(line.displayNumber, "097 0102 3456")
        let subscription = try decode(Subscription.self, ContractFixtures.subscription)
        XCTAssertEqual(subscription.status, .intro)
        XCTAssertTrue(subscription.status.grantsAccess)
        XCTAssertEqual(subscription.paidByMe, true)
    }

    func testDeviceEndpoints() throws {
        let me = try decode(DeviceMe.self, ContractFixtures.deviceMe)
        XCTAssertEqual(me.elderly.noahName, "Noah")
        XCTAssertEqual(me.nextReminder?.schedule, .daily(time: "08:00"))
        let session = try decode(ConversationSession.self, ContractFixtures.deviceConversation)
        XCTAssertEqual(session.conversationToken, "eyJ.conversation.token")
        XCTAssertEqual(session.dynamicVariables?["user_name"], .string("Wim"))
        XCTAssertEqual(session.dynamicVariables?["turn_count"], .int(3))
        XCTAssertEqual(session.dynamicVariables?["is_first"], .bool(false))
        XCTAssertEqual(session.overrides?.agent?.prompt?.prompt, "Je bent Noah ...")
        XCTAssertEqual(session.overrides?.agent?.language, "nl")
        XCTAssertEqual(session.overrides?.tts?.voiceId, "voice_abc")
        XCTAssertEqual(session.maxDurationSeconds, 1800)
    }

    func testErrorBody() throws {
        let error = APIClient.error(from: Data(ContractFixtures.error.utf8), status: 409)
        XCTAssertEqual(error, .server(status: 409, code: "inactive", message: "Noah is nog niet actief. Vraag uw mantelzorger om hulp."))
        XCTAssertEqual(error.elderMessage, "Noah is nog niet actief. Vraag uw mantelzorger om hulp.")
        XCTAssertEqual(APIClient.error(from: Data("not json".utf8), status: 500).userMessage, "Er is een storing bij HelloNoah. Probeer het later opnieuw.")
    }

    // MARK: Tolerance

    func testUnknownFieldsAndEnumValuesAreTolerated() throws {
        let json = """
        { "id": "a9", "type": "nieuw_type", "severity": "kritiek", "title": "Nieuw", "status": "gearchiveerd",
          "createdAt": "2026-10-11T08:00:00Z", "someFutureField": { "nested": true } }
        """
        let alert = try decode(NoahAlert.self, json)
        XCTAssertEqual(alert.type, .unknown)
        XCTAssertEqual(alert.severity, .unknown)
        XCTAssertEqual(alert.status, .unknown)
        XCTAssertNil(alert.body)
    }

    func testMissingArraysDecodeAsEmpty() throws {
        let json = """
        { "id": "c9", "startedAt": "2026-10-11T08:00:00Z", "channel": "telefoon_uit" }
        """
        let detail = try decode(ConversationDetail.self, json)
        XCTAssertEqual(detail.topics, [])
        XCTAssertEqual(detail.transcript, [])
        XCTAssertFalse(detail.hasConcern)
        XCTAssertEqual(detail.channel, .telefoonUit)
    }

    func testUnknownScheduleKind() throws {
        let json = """
        { "id": "r9", "title": "x", "type": "overig", "schedule": { "kind": "maandelijks", "day": 1 }, "delivery": "bellen", "active": true }
        """
        let reminder = try decode(Reminder.self, json)
        XCTAssertEqual(reminder.schedule, .unknown(kind: "maandelijks"))
    }

    // MARK: Encoding

    func testProfileInputEncodesExplicitNulls() throws {
        var input = ElderlyProfileInput()
        input.firstName = "Willem"
        input.preferredName = "Wim"
        input.phoneNumber = "+31612345678"
        input.city = "   "
        let object = try JSONSerialization.jsonObject(with: NoahJSON.encoder.encode(input)) as? [String: Any]
        XCTAssertEqual(object?["addressForm"] as? String, "u")
        XCTAssertTrue(object?["city"] is NSNull, "blank strings are sent as null so PATCH clears them")
        XCTAssertTrue(object?["birthYear"] is NSNull)
        XCTAssertEqual(object?["likes"] as? [String], [])
    }

    func testReminderInputEncodesScheduleShapes() throws {
        var input = ReminderInput()
        input.title = "Wandelen"
        input.schedule = .weekly(time: "10:00", weekdays: [4, 2])
        var object = try JSONSerialization.jsonObject(with: NoahJSON.encoder.encode(input)) as? [String: Any]
        var schedule = object?["schedule"] as? [String: Any]
        XCTAssertEqual(schedule?["kind"] as? String, "wekelijks")
        XCTAssertEqual(schedule?["weekdays"] as? [Int], [2, 4])
        XCTAssertEqual(object?["delivery"] as? String, "in_gesprek")

        input.schedule = .once(at: NoahJSON.parseDate("2026-10-14T13:30:00Z")!)
        object = try JSONSerialization.jsonObject(with: NoahJSON.encoder.encode(input)) as? [String: Any]
        schedule = object?["schedule"] as? [String: Any]
        XCTAssertEqual(schedule?["kind"] as? String, "eenmalig")
        XCTAssertEqual(schedule?["at"] as? String, "2026-10-14T13:30:00Z")
        XCTAssertNil(schedule?["time"])
    }

    func testPushTokenBody() throws {
        let data = try NoahJSON.encoder.encode(PushTokenRequest(token: "abc", platform: "ios", environment: "sandbox"))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"environment":"sandbox","platform":"ios","token":"abc"}"#)
    }
}
