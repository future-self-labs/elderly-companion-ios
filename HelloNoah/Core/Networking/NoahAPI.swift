import Foundation

/// The whole API v2 surface the app uses. `LiveNoahAPI` talks to the backend, `MockNoahAPI`
/// implements the same contract in memory (launch argument `-useMockAPI YES`).
protocol NoahAPI: AnyObject {
    // Auth (§2)
    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthResponse
    func startPhoneSignIn(phoneNumber: String) async throws
    func verifyPhoneSignIn(phoneNumber: String, code: String) async throws -> AuthResponse
    func logout(refreshToken: String) async throws
    func createPairingCode(elderlyId: String) async throws -> PairingCode
    func pairDevice(code: String, deviceName: String) async throws -> PairDeviceResponse
    /// v2.3 self route: an SMS code (or a call that reads it out) to the older person's own number.
    func startElderSignUp(phoneNumber: String, channel: PhoneVerificationChannel) async throws
    /// v2.3: creates a self-managed profile, or pairs this phone to the caregiver-managed profile
    /// that already has this number.
    func verifyElderSignUp(_ request: ElderSignUpVerifyRequest) async throws -> ElderVerifyOutcome
    /// v2.4: answer "Kent u deze persoon?" after `status: "keuze_nodig"`.
    func claimElderSignUp(_ request: ElderClaimRequest) async throws -> ElderSignUpResponse

    // Me (§3.1)
    func me() async throws -> MeResponse
    func updateMe(name: String?, phoneNumber: String?) async throws -> Caregiver
    func registerPushToken(_ token: String, environment: String) async throws
    func deletePushToken(_ token: String) async throws
    func exportMe() async throws -> Data
    /// v2.4: `409 abonnement_actief` unless `subscriptionAcknowledged` (a profile it would delete
    /// still has a running store subscription).
    func deleteMe(subscriptionAcknowledged: Bool) async throws

    // Elderly profiles (§3.2)
    func createElderly(_ input: ElderlyProfileInput) async throws -> ElderlyProfile
    func elderly(id: String) async throws -> ElderlyProfile
    func updateElderly(id: String, _ input: ElderlyProfileInput) async throws -> ElderlyProfile
    /// v2.2: send a code to the older person's number (SMS, or read out in a call).
    func startPhoneVerification(elderlyId: String, channel: PhoneVerificationChannel) async throws -> PhoneVerificationStart
    /// v2.2: confirm the number with that code. Wrong/expired: `400 ongeldige_code`.
    func verifyPhone(elderlyId: String, code: String) async throws -> ElderlyProfile
    /// v2.4: `409 abonnement_actief` unless `subscriptionAcknowledged`; `403 profiel_van_oudere`
    /// for a profile the older person registered themselves.
    func deleteElderly(id: String, subscriptionAcknowledged: Bool) async throws
    func exportElderly(id: String) async throws -> Data
    /// v2.4: "ik heb mijn naaste verteld dat ik meelees" (`POST /elderly/:id/told-elderly`).
    func markToldElderly(elderlyId: String) async throws
    /// v2.4: switch Noah's scheduled calls back on after the older person said they want to stop
    /// (`PATCH /elderly/:id { "outboundPaused": false }`).
    func setOutboundPaused(elderlyId: String, paused: Bool) async throws -> ElderlyProfile

    // Important people (§3.3)
    func people(elderlyId: String) async throws -> [Person]
    func createPerson(elderlyId: String, _ input: PersonInput) async throws -> Person
    func updatePerson(elderlyId: String, personId: String, _ input: PersonInput) async throws -> Person
    func deletePerson(elderlyId: String, personId: String) async throws

    // Noah settings (§3.4)
    func settings(elderlyId: String) async throws -> NoahSettings
    /// Partial: send only what changed (`NoahSettingsPatch(from:to:)`).
    func updateSettings(elderlyId: String, _ patch: NoahSettingsPatch) async throws -> NoahSettings

    // Emergency contacts (§3.5)
    func emergencyContacts(elderlyId: String) async throws -> [EmergencyContact]
    func createEmergencyContact(elderlyId: String, _ input: EmergencyContactInput) async throws -> EmergencyContact
    func updateEmergencyContact(elderlyId: String, contactId: String, _ input: EmergencyContactInput) async throws -> EmergencyContact
    func deleteEmergencyContact(elderlyId: String, contactId: String) async throws
    func reorderEmergencyContacts(elderlyId: String, ids: [String]) async throws

    // Caregivers & invitations (§3.6)
    func caregivers(elderlyId: String) async throws -> [CaregiverMembership]
    func createInvitation(elderlyId: String, role: Role) async throws -> Invitation
    func acceptInvitation(code: String) async throws -> AcceptInvitationResponse
    func updateCaregiverRole(elderlyId: String, caregiverId: String, role: Role) async throws
    func removeCaregiver(elderlyId: String, caregiverId: String) async throws
    /// v2.4: invitations that were not used yet (beheerder).
    func pendingInvitations(elderlyId: String) async throws -> [PendingInvitation]
    func revokeInvitation(elderlyId: String, invitationId: String) async throws

    // Devices (§3.7)
    func devices(elderlyId: String) async throws -> [PairedDevice]
    func unpairDevice(elderlyId: String, deviceId: String) async throws
    /// v2.4: approve a new (restricted) phone of the older person.
    func approveDevice(elderlyId: String, deviceId: String) async throws

    // Dashboard, conversations, mood (§3.8–3.10)
    func dashboard(elderlyId: String) async throws -> Dashboard
    func conversations(elderlyId: String, cursor: String?, limit: Int) async throws -> Page<ConversationSummary>
    func conversation(id: String) async throws -> ConversationDetail
    /// v2.1: signed URL of the recording (`404 geen_opname` when there is none).
    func conversationAudio(conversationId: String) async throws -> ConversationAudio
    func mood(elderlyId: String, days: Int) async throws -> MoodOverview

    // Life story (§3.11)
    func lifeStory(elderlyId: String, category: LifeStoryCategory?, cursor: String?, limit: Int) async throws -> Page<LifeStoryEntry>
    func createLifeStoryEntry(elderlyId: String, _ input: LifeStoryInput) async throws -> LifeStoryEntry
    func updateLifeStoryEntry(entryId: String, _ input: LifeStoryInput) async throws -> LifeStoryEntry
    func deleteLifeStoryEntry(entryId: String) async throws

    // Reminders (§3.12)
    func reminders(elderlyId: String) async throws -> [Reminder]
    func createReminder(elderlyId: String, _ input: ReminderInput) async throws -> Reminder
    func updateReminder(reminderId: String, _ input: ReminderInput) async throws -> Reminder
    func deleteReminder(reminderId: String) async throws

    // Alerts (§3.13)
    func alerts(elderlyId: String, status: AlertListFilter, cursor: String?, limit: Int) async throws -> Page<NoahAlert>
    func acknowledgeAlert(alertId: String) async throws -> NoahAlert
    func resolveAlert(alertId: String, falseAlarm: Bool, note: String?) async throws -> NoahAlert

    // Calls & phone line (§3.14)
    func callNow(elderlyId: String, mode: ConversationMode) async throws -> CallNowResponse
    func phoneLine() async throws -> PhoneLine

    // Subscription (§3.15)
    func subscription(elderlyId: String) async throws -> Subscription
    func submitAppStoreTransaction(elderlyId: String, signedTransaction: String) async throws -> Subscription

    // Device endpoints (§4)
    func deviceMe() async throws -> DeviceMe
    func startDeviceConversation(mode: ConversationMode) async throws -> ConversationSession
    func deviceCallMe() async throws
    func deviceLifeStory(cursor: String?, limit: Int) async throws -> Page<LifeStoryEntry>
    /// v2.1: the older person's own recording, for "Mijn verhaal".
    func deviceConversationAudio(conversationId: String) async throws -> ConversationAudio
    func deviceReminders() async throws -> [Reminder]
    func registerDevicePushToken(_ token: String, environment: String) async throws
    func unpairThisDevice() async throws

    // Device endpoints for self-managed profiles (v2.3). Caregiver-managed profiles answer
    // `403 beheerd_door_mantelzorger`, except where noted.
    /// Allowed for both kinds of profile.
    func deviceProfile() async throws -> DeviceProfile
    func updateDeviceProfile(_ patch: DeviceProfilePatch) async throws -> DeviceProfile
    func deviceSettings() async throws -> NoahSettings
    func updateDeviceSettings(_ patch: NoahSettingsPatch) async throws -> NoahSettings
    func deviceEmergencyContacts() async throws -> [EmergencyContact]
    func createDeviceEmergencyContact(_ input: EmergencyContactInput) async throws -> EmergencyContact
    func updateDeviceEmergencyContact(contactId: String, _ input: EmergencyContactInput) async throws -> EmergencyContact
    func deleteDeviceEmergencyContact(contactId: String) async throws
    /// Allowed for both; `paidByMe` = paid via this device.
    func deviceSubscription() async throws -> Subscription
    func submitDeviceAppStoreTransaction(signedTransaction: String) async throws -> Subscription
    /// v2.4: a `beheerder` invitation needs `confirmed: true` (else `400 bevestiging_nodig`).
    func createDeviceInvitation(role: Role, confirmed: Bool) async throws -> Invitation
    /// Allowed for both.
    func deviceCaregivers() async throws -> [CaregiverMembership]
    func removeDeviceCaregiver(caregiverId: String) async throws
    func exportDevice() async throws -> Data
    /// Deletes the self profile and all its data. v2.4: `409 abonnement_actief` unless
    /// `subscriptionAcknowledged`.
    func deleteDeviceAccount(subscriptionAcknowledged: Bool) async throws

    // v2.4: transparency and control for the older person (both kinds of profile).
    func deviceTransparency() async throws -> DeviceTransparency
    func markTransparencySeen() async throws
    func updateSharing(_ level: SharingLevel) async throws -> DeviceTransparency
    /// Caregiver-managed: delete the profile after 14 days (caregivers are told).
    func requestDeletion(subscriptionAcknowledged: Bool) async throws -> DeletionRequest
    func withdrawDeletion() async throws
    func deviceDevices() async throws -> [PairedDevice]
    func approveDeviceFromDevice(deviceId: String) async throws
    func rejectDeviceFromDevice(deviceId: String) async throws
    func approveCaregiverRequest(id: String) async throws
    func rejectCaregiverRequest(id: String) async throws
    func revokeDeviceInvitation(id: String) async throws
    func reorderDeviceEmergencyContacts(ids: [String]) async throws
}

extension NoahAPI {
    func deleteMe() async throws { try await deleteMe(subscriptionAcknowledged: false) }
    func deleteElderly(id: String) async throws { try await deleteElderly(id: id, subscriptionAcknowledged: false) }
    func deleteDeviceAccount() async throws { try await deleteDeviceAccount(subscriptionAcknowledged: false) }
    func requestDeletion() async throws -> DeletionRequest { try await requestDeletion(subscriptionAcknowledged: false) }
    func createDeviceInvitation(role: Role) async throws -> Invitation {
        try await createDeviceInvitation(role: role, confirmed: role == .beheerder)
    }
}

enum AlertListFilter: String {
    case open
    case all
}
