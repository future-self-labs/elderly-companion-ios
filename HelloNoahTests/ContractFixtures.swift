import Foundation

/// Every JSON example from `elderly-companion-api/docs/api-v2.md`, made valid JSON (comments removed,
/// "..." placeholders filled in, nested `{ ConversationSummary }` etc. expanded with the documented shapes).
enum ContractFixtures {
    static let authResponse = """
    {
      "accessToken": "eyJhbGciOiJIUzI1NiJ9.e30.sig",
      "accessTokenExpiresAt": "2026-10-11T09:00:00Z",
      "refreshToken": "hnr_abc123",
      "caregiver": { "id": "c1", "name": "Anna de Vries", "email": "anna@example.com", "phoneNumber": null, "createdAt": "2026-10-11T08:00:00Z" },
      "isNewAccount": true
    }
    """

    static let pairingCode = """
    { "code": "482913", "expiresAt": "2026-10-11T08:15:00Z" }
    """

    static let pairDevice = """
    { "deviceToken": "hnd_xyz", "device": { "id": "d1" }, "elderly": { "id": "e1", "preferredName": "Wim", "noahName": "Noah" } }
    """

    static let me = """
    {
      "caregiver": { "id": "c1", "name": "Anna de Vries", "email": "anna@example.com", "phoneNumber": "+31612345678", "createdAt": "2026-10-01T08:00:00Z" },
      "elderly": [ { "id": "e1", "preferredName": "Wim", "role": "beheerder", "access": "active", "lastConversationAt": "2026-10-10T16:05:00Z", "openAlertCount": 1 } ]
    }
    """

    static let elderlyProfile = """
    {
      "id": "8E5C2D1A-4B7F-4C2A-9F3E-1A2B3C4D5E6F",
      "firstName": "Willem", "lastName": "de Vries", "preferredName": "Wim",
      "addressForm": "u",
      "gender": "man",
      "birthYear": 1941,
      "phoneNumber": "+31612345678",
      "city": "Haarlem",
      "livingSituation": "alleen",
      "about": "Oud-onderwijzer, houdt van tuinieren ...",
      "likes": ["tuinieren", "Ajax", "Toon Hermans"],
      "dislikes": ["politiek"],
      "topicsToRaise": ["de kleinkinderen", "zijn moestuin"],
      "topicsToAvoid": ["het overlijden van zijn broer"],
      "routines": "Staat om 7:30 op, wandelt na de lunch.",
      "caregiverNotes": "Heeft dinsdag een afspraak bij de huisarts.",
      "access": "active",
      "isBeta": false,
      "myRole": "beheerder",
      "createdAt": "2026-10-01T08:00:00Z"
    }
    """

    static let people = """
    { "items": [
      { "id": "p1", "name": "Anna", "relation": "dochter", "notes": "Belt elke zondag", "birthday": "1972-05-14", "isDeceased": false, "createdBy": "caregiver" },
      { "id": "p2", "name": "Margriet", "relation": "echtgenote", "notes": null, "birthday": null, "isDeceased": true, "createdBy": "noah" }
    ] }
    """

    static let settings = """
    {
      "noahName": "Noah",
      "voice": "vrouw",
      "speakingSpeed": 1.0,
      "maxConversationMinutes": 30,
      "noContactAlertDays": 2,
      "morningCall": { "enabled": false, "time": "09:30", "weekdays": [1,2,3,4,5,6,7] },
      "quietHours": { "start": "21:30", "end": "08:00" }
    }
    """

    static let emergencyContacts = """
    { "items": [ { "id": "ec1", "name": "Anna de Vries", "phoneNumber": "+31612345678", "relation": "dochter", "priority": 1, "notifyBySms": true, "notifyByCall": true } ] }
    """

    static let caregivers = """
    { "items": [ { "caregiverId": "c1", "name": "Anna de Vries", "role": "beheerder", "joinedAt": "2026-10-01T08:00:00Z", "isMe": true },
                 { "caregiverId": "c2", "name": "Mark", "role": "lezer", "joinedAt": "2026-10-02T08:00:00Z", "isMe": false } ] }
    """

    static let invitation = """
    { "code": "K7P-2QX", "url": "https://hellonoah.ai/uitnodiging/K7P-2QX", "expiresAt": "2026-10-18T08:00:00Z", "shareText": "Ik nodig je uit om mee te kijken bij Noah voor Wim: https://hellonoah.ai/uitnodiging/K7P-2QX" }
    """

    static let acceptInvitation = """
    { "elderly": { "id": "e1", "preferredName": "Wim" }, "role": "lezer" }
    """

    static let devices = """
    { "items": [ { "id": "d1", "deviceName": "iPhone van Wim", "platform": "ios", "pairedAt": "2026-10-01T08:00:00Z", "lastSeenAt": "2026-10-11T07:00:00.123Z" } ] }
    """

    static let conversationSummary = """
    { "id": "conv1", "startedAt": "2026-10-10T16:05:00Z", "durationSeconds": 734, "channel": "app",
      "summary": "Wim vertelde over ...", "moodScore": 4, "topics": ["moestuin", "kleindochter Sara"], "hasConcern": false }
    """

    static let alert = """
    { "id": "a1", "type": "lage_stemming", "severity": "waarschuwing",
      "title": "Wim klonk somber", "body": "In de laatste drie gesprekken ...",
      "conversationId": "conv1", "status": "open",
      "createdAt": "2026-10-10T17:00:00Z", "acknowledgedBy": null }
    """

    static let reminderOnce = """
    { "id": "r1", "title": "Pillen innemen", "notes": "De witte na het ontbijt", "type": "medicatie",
      "schedule": { "kind": "eenmalig", "at": "2026-10-14T13:30:00Z" },
      "delivery": "bellen", "active": true, "createdBy": "caregiver", "nextAt": "2026-10-14T13:30:00Z", "lastCompletedAt": null }
    """

    static let reminderDaily = """
    { "id": "r2", "title": "Pillen innemen", "notes": null, "type": "medicatie",
      "schedule": { "kind": "dagelijks", "time": "08:00" },
      "delivery": "in_gesprek", "active": true, "createdBy": "noah", "nextAt": "2026-10-12T06:00:00Z", "lastCompletedAt": "2026-10-11T06:00:00Z" }
    """

    static let reminderWeekly = """
    { "id": "r3", "title": "Wandelen", "notes": null, "type": "routine",
      "schedule": { "kind": "wekelijks", "time": "10:00", "weekdays": [2,4] },
      "delivery": "in_gesprek", "active": false, "createdBy": "caregiver", "nextAt": null, "lastCompletedAt": null }
    """

    static let lifeStoryEntry = """
    { "id": "ls1", "category": "familie", "title": "De trouwdag met Margriet", "content": "Het regende ...",
      "year": 1962, "people": ["Margriet"], "places": ["Haarlem"], "quote": "Niemand ging naar binnen.",
      "conversationId": "conv1", "createdBy": "noah", "createdAt": "2026-10-10T16:20:00Z" }
    """

    static var dashboard: String {
        """
        {
          "elderly": { "id": "e1", "preferredName": "Wim", "access": "active" },
          "lastConversationAt": "2026-10-10T16:05:00Z",
          "week": { "conversations": 9, "minutes": 142, "averageMood": 3.8 },
          "moodTrend": [ { "date": "2026-10-05", "mood": 4.0, "conversations": 2 }, { "date": "2026-10-06", "mood": null, "conversations": 0 } ],
          "latestConversation": \(conversationSummary),
          "openAlerts": [ \(alert) ],
          "upcomingReminders": [ \(reminderOnce) ],
          "lifeStory": { "entries": 23, "latest": \(lifeStoryEntry) }
        }
        """
    }

    static var conversationsPage: String {
        """
        { "items": [ \(conversationSummary) ], "nextCursor": "abc" }
        """
    }

    static let conversationDetail = """
    { "id": "conv1", "startedAt": "2026-10-10T16:05:00Z", "durationSeconds": 734, "channel": "telefoon_in",
      "summary": "Wim vertelde over ...", "moodScore": 4, "topics": ["moestuin", "kleindochter Sara"], "hasConcern": false,
      "moodIndicators": ["lachte veel"], "concerningSignals": [], "cognitiveClarity": 5,
      "mentionedPeople": ["Sara"], "mentionedPlaces": ["Zandvoort"], "mentionedDates": ["1962"],
      "emotionalMoments": ["werd stil bij het noemen van zijn broer"],
      "lifeStoryEntryIds": ["ls1"],
      "transcript": [ { "role": "noah", "text": "Goedemiddag Wim!", "atSeconds": 12 }, { "role": "oudere", "text": "Hallo Noah.", "atSeconds": 15 } ] }
    """

    static let mood = """
    { "days": [ { "date": "2026-10-10", "mood": 3.5, "conversations": 1, "cognitiveClarity": 4.5 }, { "date": "2026-10-11", "mood": null, "conversations": 0, "cognitiveClarity": null } ],
      "average": 3.7, "trend": "stabiel" }
    """

    static var lifeStoryPage: String {
        """
        { "items": [ \(lifeStoryEntry) ], "nextCursor": null }
        """
    }

    static var remindersList: String {
        """
        { "items": [ \(reminderOnce), \(reminderDaily), \(reminderWeekly) ] }
        """
    }

    static var alertsPage: String {
        """
        { "items": [ \(alert) ], "nextCursor": null }
        """
    }

    static let callNow = """
    { "status": "gestart" }
    """

    static let phoneLine = """
    { "phoneNumber": "+3197010203456", "displayNumber": "097 0102 3456", "instructions": "Bel dit nummer vanaf ... Noah herkent het nummer ..." }
    """

    static let subscription = """
    { "status": "intro", "productId": "ai.hellonoah.unlimited.monthly", "renewsAt": "2026-11-11T08:00:00Z", "expiresAt": null, "platform": "app_store", "paidByMe": true }
    """

    static var deviceMe: String {
        """
        { "elderly": { "id": "e1", "preferredName": "Wim", "addressForm": "u", "noahName": "Noah" },
          "access": "active", "lastConversationAt": "2026-10-10T16:05:00Z", "nextReminder": \(reminderDaily) }
        """
    }

    static let deviceConversation = """
    {
      "agentId": "agent_123",
      "conversationToken": "eyJ.conversation.token",
      "dynamicVariables": { "user_name": "Wim", "session_claim": "signed.claim", "previous_summary": "Over de moestuin", "turn_count": 3, "is_first": false },
      "overrides": { "agent": { "prompt": { "prompt": "Je bent Noah ..." }, "firstMessage": "Goedemiddag Wim!", "language": "nl" },
                     "tts": { "voiceId": "voice_abc", "speed": 1.0 } },
      "maxDurationSeconds": 1800
    }
    """

    static let error = """
    { "error": { "code": "inactive", "message": "Noah is nog niet actief. Vraag uw mantelzorger om hulp." } }
    """
}
