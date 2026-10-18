import Foundation

/// `NoahAPI` against the real backend. Paths and bodies follow api-v2.md exactly.
final class LiveNoahAPI: NoahAPI {
    let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    private func page(_ cursor: String?, _ limit: Int) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return items
    }

    private func esc(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    // MARK: Auth

    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthResponse {
        try await client.send("POST", "/auth/apple", body: request, auth: .none)
    }

    func startPhoneSignIn(phoneNumber: String) async throws {
        try await client.sendVoid("POST", "/auth/phone/start", body: ["phoneNumber": phoneNumber], auth: .none)
    }

    func verifyPhoneSignIn(phoneNumber: String, code: String) async throws -> AuthResponse {
        try await client.send("POST", "/auth/phone/verify", body: ["phoneNumber": phoneNumber, "code": code], auth: .none)
    }

    func logout(refreshToken: String) async throws {
        try await client.sendVoid("POST", "/auth/logout", body: ["refreshToken": refreshToken], auth: .none)
    }

    func createPairingCode(elderlyId: String) async throws -> PairingCode {
        try await client.send("POST", "/elderly/\(esc(elderlyId))/pairing-codes", auth: .caregiver)
    }

    func pairDevice(code: String, deviceName: String) async throws -> PairDeviceResponse {
        struct Body: Encodable { let code: String; let deviceName: String; let platform: String }
        return try await client.send("POST", "/devices/pair", body: Body(code: code, deviceName: deviceName, platform: "ios"), auth: .none)
    }

    // MARK: Me

    func me() async throws -> MeResponse {
        try await client.send("GET", "/me", auth: .caregiver)
    }

    func updateMe(name: String?, phoneNumber: String?) async throws -> Caregiver {
        struct Body: Encodable { let name: String?; let phoneNumber: String? }
        return try await client.send("PATCH", "/me", body: Body(name: name, phoneNumber: phoneNumber), auth: .caregiver)
    }

    func registerPushToken(_ token: String, environment: String) async throws {
        try await client.sendVoid("POST", "/me/push-tokens", body: PushTokenRequest(token: token, platform: "ios", environment: environment), auth: .caregiver)
    }

    func deletePushToken(_ token: String) async throws {
        try await client.sendVoid("DELETE", "/me/push-tokens/\(esc(token))", auth: .caregiver)
    }

    func exportMe() async throws -> Data {
        try await client.sendData("GET", "/me/export", auth: .caregiver)
    }

    func deleteMe() async throws {
        try await client.sendVoid("DELETE", "/me", body: ["confirm": "VERWIJDER"], auth: .caregiver)
    }

    // MARK: Elderly

    func createElderly(_ input: ElderlyProfileInput) async throws -> ElderlyProfile {
        try await client.send("POST", "/elderly", body: input, auth: .caregiver)
    }

    func elderly(id: String) async throws -> ElderlyProfile {
        try await client.send("GET", "/elderly/\(esc(id))", auth: .caregiver)
    }

    func updateElderly(id: String, _ input: ElderlyProfileInput) async throws -> ElderlyProfile {
        try await client.send("PATCH", "/elderly/\(esc(id))", body: input, auth: .caregiver)
    }

    func deleteElderly(id: String) async throws {
        try await client.sendVoid("DELETE", "/elderly/\(esc(id))", body: ["confirm": "VERWIJDER"], auth: .caregiver)
    }

    func exportElderly(id: String) async throws -> Data {
        try await client.sendData("GET", "/elderly/\(esc(id))/export", auth: .caregiver)
    }

    // MARK: People

    func people(elderlyId: String) async throws -> [Person] {
        let response: ItemsResponse<Person> = try await client.send("GET", "/elderly/\(esc(elderlyId))/people", auth: .caregiver)
        return response.items
    }

    func createPerson(elderlyId: String, _ input: PersonInput) async throws -> Person {
        try await client.send("POST", "/elderly/\(esc(elderlyId))/people", body: input, auth: .caregiver)
    }

    func updatePerson(elderlyId: String, personId: String, _ input: PersonInput) async throws -> Person {
        try await client.send("PATCH", "/elderly/\(esc(elderlyId))/people/\(esc(personId))", body: input, auth: .caregiver)
    }

    func deletePerson(elderlyId: String, personId: String) async throws {
        try await client.sendVoid("DELETE", "/elderly/\(esc(elderlyId))/people/\(esc(personId))", auth: .caregiver)
    }

    // MARK: Settings

    func settings(elderlyId: String) async throws -> NoahSettings {
        try await client.send("GET", "/elderly/\(esc(elderlyId))/settings", auth: .caregiver)
    }

    func updateSettings(elderlyId: String, _ patch: NoahSettingsPatch) async throws -> NoahSettings {
        try await client.send("PATCH", "/elderly/\(esc(elderlyId))/settings", body: patch, auth: .caregiver)
    }

    // MARK: Emergency contacts

    func emergencyContacts(elderlyId: String) async throws -> [EmergencyContact] {
        let response: ItemsResponse<EmergencyContact> = try await client.send("GET", "/elderly/\(esc(elderlyId))/emergency-contacts", auth: .caregiver)
        return response.items.sorted { $0.priority < $1.priority }
    }

    func createEmergencyContact(elderlyId: String, _ input: EmergencyContactInput) async throws -> EmergencyContact {
        try await client.send("POST", "/elderly/\(esc(elderlyId))/emergency-contacts", body: input, auth: .caregiver)
    }

    func updateEmergencyContact(elderlyId: String, contactId: String, _ input: EmergencyContactInput) async throws -> EmergencyContact {
        try await client.send("PATCH", "/elderly/\(esc(elderlyId))/emergency-contacts/\(esc(contactId))", body: input, auth: .caregiver)
    }

    func deleteEmergencyContact(elderlyId: String, contactId: String) async throws {
        try await client.sendVoid("DELETE", "/elderly/\(esc(elderlyId))/emergency-contacts/\(esc(contactId))", auth: .caregiver)
    }

    func reorderEmergencyContacts(elderlyId: String, ids: [String]) async throws {
        try await client.sendVoid("PUT", "/elderly/\(esc(elderlyId))/emergency-contacts/order", body: ["ids": ids], auth: .caregiver)
    }

    // MARK: Caregivers & invitations

    func caregivers(elderlyId: String) async throws -> [CaregiverMembership] {
        let response: ItemsResponse<CaregiverMembership> = try await client.send("GET", "/elderly/\(esc(elderlyId))/caregivers", auth: .caregiver)
        return response.items
    }

    func createInvitation(elderlyId: String, role: Role) async throws -> Invitation {
        try await client.send("POST", "/elderly/\(esc(elderlyId))/invitations", body: ["role": role.rawValue], auth: .caregiver)
    }

    func acceptInvitation(code: String) async throws -> AcceptInvitationResponse {
        try await client.send("POST", "/invitations/accept", body: ["code": code], auth: .caregiver)
    }

    func updateCaregiverRole(elderlyId: String, caregiverId: String, role: Role) async throws {
        try await client.sendVoid("PATCH", "/elderly/\(esc(elderlyId))/caregivers/\(esc(caregiverId))", body: ["role": role.rawValue], auth: .caregiver)
    }

    func removeCaregiver(elderlyId: String, caregiverId: String) async throws {
        try await client.sendVoid("DELETE", "/elderly/\(esc(elderlyId))/caregivers/\(esc(caregiverId))", auth: .caregiver)
    }

    // MARK: Devices

    func devices(elderlyId: String) async throws -> [PairedDevice] {
        let response: ItemsResponse<PairedDevice> = try await client.send("GET", "/elderly/\(esc(elderlyId))/devices", auth: .caregiver)
        return response.items
    }

    func unpairDevice(elderlyId: String, deviceId: String) async throws {
        try await client.sendVoid("DELETE", "/elderly/\(esc(elderlyId))/devices/\(esc(deviceId))", auth: .caregiver)
    }

    // MARK: Dashboard, conversations, mood

    func dashboard(elderlyId: String) async throws -> Dashboard {
        try await client.send("GET", "/elderly/\(esc(elderlyId))/dashboard", auth: .caregiver)
    }

    func conversations(elderlyId: String, cursor: String?, limit: Int) async throws -> Page<ConversationSummary> {
        try await client.send("GET", "/elderly/\(esc(elderlyId))/conversations", query: page(cursor, limit), auth: .caregiver)
    }

    func conversation(id: String) async throws -> ConversationDetail {
        try await client.send("GET", "/conversations/\(esc(id))", auth: .caregiver)
    }

    func conversationAudio(conversationId: String) async throws -> ConversationAudio {
        try await client.send("GET", "/conversations/\(esc(conversationId))/audio", auth: .caregiver)
    }

    func mood(elderlyId: String, days: Int) async throws -> MoodOverview {
        try await client.send("GET", "/elderly/\(esc(elderlyId))/mood", query: [URLQueryItem(name: "days", value: String(days))], auth: .caregiver)
    }

    // MARK: Life story

    func lifeStory(elderlyId: String, category: LifeStoryCategory?, cursor: String?, limit: Int) async throws -> Page<LifeStoryEntry> {
        var query = page(cursor, limit)
        if let category, category != .unknown { query.append(URLQueryItem(name: "category", value: category.rawValue)) }
        return try await client.send("GET", "/elderly/\(esc(elderlyId))/life-story", query: query, auth: .caregiver)
    }

    func createLifeStoryEntry(elderlyId: String, _ input: LifeStoryInput) async throws -> LifeStoryEntry {
        try await client.send("POST", "/elderly/\(esc(elderlyId))/life-story", body: input, auth: .caregiver)
    }

    func updateLifeStoryEntry(entryId: String, _ input: LifeStoryInput) async throws -> LifeStoryEntry {
        try await client.send("PATCH", "/life-story/\(esc(entryId))", body: input, auth: .caregiver)
    }

    func deleteLifeStoryEntry(entryId: String) async throws {
        try await client.sendVoid("DELETE", "/life-story/\(esc(entryId))", auth: .caregiver)
    }

    // MARK: Reminders

    func reminders(elderlyId: String) async throws -> [Reminder] {
        let response: ItemsResponse<Reminder> = try await client.send("GET", "/elderly/\(esc(elderlyId))/reminders", auth: .caregiver)
        return response.items
    }

    func createReminder(elderlyId: String, _ input: ReminderInput) async throws -> Reminder {
        try await client.send("POST", "/elderly/\(esc(elderlyId))/reminders", body: input, auth: .caregiver)
    }

    func updateReminder(reminderId: String, _ input: ReminderInput) async throws -> Reminder {
        try await client.send("PATCH", "/reminders/\(esc(reminderId))", body: input, auth: .caregiver)
    }

    func deleteReminder(reminderId: String) async throws {
        try await client.sendVoid("DELETE", "/reminders/\(esc(reminderId))", auth: .caregiver)
    }

    // MARK: Alerts

    func alerts(elderlyId: String, status: AlertListFilter, cursor: String?, limit: Int) async throws -> Page<NoahAlert> {
        var query = page(cursor, limit)
        query.append(URLQueryItem(name: "status", value: status.rawValue))
        return try await client.send("GET", "/elderly/\(esc(elderlyId))/alerts", query: query, auth: .caregiver)
    }

    func acknowledgeAlert(alertId: String) async throws -> NoahAlert {
        try await client.send("POST", "/alerts/\(esc(alertId))/acknowledge", auth: .caregiver)
    }

    func resolveAlert(alertId: String, falseAlarm: Bool, note: String?) async throws -> NoahAlert {
        struct Body: Encodable { let falseAlarm: Bool; let note: String? }
        return try await client.send("POST", "/alerts/\(esc(alertId))/resolve", body: Body(falseAlarm: falseAlarm, note: note.nilIfBlank), auth: .caregiver)
    }

    // MARK: Calls & phone line

    func callNow(elderlyId: String, mode: ConversationMode) async throws -> CallNowResponse {
        try await client.send("POST", "/elderly/\(esc(elderlyId))/call-now", body: ConversationModeRequest(mode: mode), auth: .caregiver)
    }

    func phoneLine() async throws -> PhoneLine {
        try await client.send("GET", "/phone-line", auth: .caregiver)
    }

    // MARK: Subscription

    func subscription(elderlyId: String) async throws -> Subscription {
        try await client.send("GET", "/elderly/\(esc(elderlyId))/subscription", auth: .caregiver)
    }

    func submitAppStoreTransaction(elderlyId: String, signedTransaction: String) async throws -> Subscription {
        try await client.send("POST", "/subscriptions/app-store", body: ["elderlyId": elderlyId, "signedTransaction": signedTransaction], auth: .caregiver)
    }

    // MARK: Device

    func deviceMe() async throws -> DeviceMe {
        try await client.send("GET", "/device/me", auth: .device)
    }

    func startDeviceConversation(mode: ConversationMode) async throws -> ConversationSession {
        try await client.send("POST", "/device/conversation", body: ConversationModeRequest(mode: mode), auth: .device)
    }

    func deviceCallMe() async throws {
        try await client.sendVoid("POST", "/device/call-me", auth: .device)
    }

    func deviceLifeStory(cursor: String?, limit: Int) async throws -> Page<LifeStoryEntry> {
        try await client.send("GET", "/device/life-story", query: page(cursor, limit), auth: .device)
    }

    func deviceConversationAudio(conversationId: String) async throws -> ConversationAudio {
        try await client.send("GET", "/device/conversations/\(esc(conversationId))/audio", auth: .device)
    }

    func deviceReminders() async throws -> [Reminder] {
        let response: ItemsResponse<Reminder> = try await client.send("GET", "/device/reminders", auth: .device)
        return response.items
    }

    func registerDevicePushToken(_ token: String, environment: String) async throws {
        try await client.sendVoid("POST", "/device/push-tokens", body: PushTokenRequest(token: token, platform: "ios", environment: environment), auth: .device)
    }

    func unpairThisDevice() async throws {
        try await client.sendVoid("POST", "/device/unpair", auth: .device)
    }
}
