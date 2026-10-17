import Foundation

/// Every error the app shows comes through here, with a Dutch message.
enum APIError: Error, Equatable {
    /// The server answered with `{ "error": { "code", "message" } }`.
    case server(status: Int, code: String, message: String?)
    /// No connection / timeout.
    case offline
    /// The caregiver session ended (refresh token invalid) — the app signs out.
    case sessionExpired
    /// The device token was revoked — the phone is no longer paired.
    case deviceUnpaired
    /// The response could not be read.
    case decoding(String)
    /// Anything else (transport errors, unexpected statuses).
    case unexpected(String)
    case cancelled

    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }

    var status: Int? {
        if case .server(let status, _, _) = self { return status }
        return nil
    }

    var isOffline: Bool { self == .offline }

    /// Text for the caregiver interface (informal "je").
    var userMessage: String {
        switch self {
        case .server(let status, let code, let message):
            if let message, !message.isEmpty { return message }
            return Self.fallbackMessage(status: status, code: code)
        case .offline:
            return "Er is geen internetverbinding. Controleer je wifi of mobiele data en probeer het opnieuw."
        case .sessionExpired:
            return "Je bent uitgelogd. Log opnieuw in om verder te gaan."
        case .deviceUnpaired:
            return "Deze telefoon is niet meer gekoppeld."
        case .decoding:
            return "We konden het antwoord van de server niet lezen. Probeer het later opnieuw of werk de app bij."
        case .unexpected, .cancelled:
            return "Er ging iets mis. Probeer het over een paar minuten opnieuw."
        }
    }

    /// Text for the older person's interface (formal "u", calm).
    var elderMessage: String {
        switch self {
        case .offline:
            return "Er is nu geen internet. Probeert u het straks nog eens."
        case .server(_, "inactive", _):
            return "Noah is nog niet actief. Vraag uw mantelzorger om hulp."
        case .server(_, _, let message?) where !message.isEmpty:
            return message
        case .deviceUnpaired:
            return "Deze telefoon is niet meer gekoppeld. Vraag uw mantelzorger om hulp."
        default:
            return "Het lukt nu even niet. Probeert u het over een paar minuten nog eens."
        }
    }

    static func fallbackMessage(status: Int, code: String) -> String {
        switch code {
        case "alleen_lezen": return "Je kijkt mee als lezer. Alleen een beheerder kan dit doen."
        case "koppelcode_ongeldig": return "Deze koppelcode klopt niet of is verlopen. Maak een nieuwe code."
        case "ongeldige_code": return "Deze code klopt niet of is verlopen. Probeer het opnieuw."
        case "uitnodiging_ongeldig": return "Deze uitnodiging bestaat niet of is verlopen. Vraag om een nieuwe uitnodiging."
        case "te_veel_verzoeken": return "Even geduld: dit is net al gedaan. Probeer het over een paar minuten opnieuw."
        case "niet_geconfigureerd", "niet_beschikbaar": return "Dit is nu even niet beschikbaar. Probeer het later opnieuw."
        case "inloggen_mislukt": return "Inloggen is niet gelukt. Probeer het opnieuw."
        case "telefoonnummer_in_gebruik": return "Dit telefoonnummer is al in gebruik bij een ander account."
        case "inactive": return "Noah is nog niet actief voor dit profiel. Start eerst het abonnement."
        case "quiet_hours": return "Het is nu rusttijd. Noah belt niet tijdens de ingestelde rusttijden."
        case "phone_number_taken": return "Dit telefoonnummer hoort al bij een ander profiel."
        case "last_beheerder": return "Er moet altijd minstens één beheerder zijn."
        case "geen_opname": return "Er is geen opname van dit gesprek."
        case "invalid_code", "code_expired": return "Deze code klopt niet of is verlopen. Vraag een nieuwe code."
        case "rate_limited": return "Even geduld: te veel pogingen. Probeer het over een paar minuten opnieuw."
        default: break
        }
        switch status {
        case 400, 422: return "Niet alle gegevens zijn goed ingevuld."
        case 401: return "Je bent uitgelogd. Log opnieuw in."
        case 403: return "Je hebt geen rechten om dit te doen. Vraag de beheerder."
        case 404: return "Dit bestaat niet (meer)."
        case 409: return "Dit kan nu niet."
        case 429: return "Te veel pogingen. Probeer het over een paar minuten opnieuw."
        case 500...: return "Er is een storing bij HelloNoah. Probeer het later opnieuw."
        default: return "Er ging iets mis. Probeer het opnieuw."
        }
    }

    static func from(_ error: Error) -> APIError {
        if let apiError = error as? APIError { return apiError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .cancelled:
                return .cancelled
            default:
                return .unexpected(urlError.localizedDescription)
            }
        }
        if error is DecodingError { return .decoding(String(describing: error)) }
        return .unexpected(error.localizedDescription)
    }
}

/// What a caregiver may do for one elderly profile, from their role (contract §1).
struct Permissions: Equatable {
    let role: Role

    var isBeheerder: Bool { role == .beheerder }

    // Any role
    var canView: Bool { role != .unknown }
    var canAcknowledgeAlerts: Bool { role == .beheerder || role == .lezer }

    // Beheerder only. Per the backend's clarification of contract §1 a lezer cannot even *read*
    // people, settings, emergency contacts, caregivers, devices or the subscription.
    var canViewPeople: Bool { isBeheerder }
    var canViewSettings: Bool { isBeheerder }
    var canViewEmergencyContacts: Bool { isBeheerder }
    var canViewCaregivers: Bool { isBeheerder }
    var canViewDevices: Bool { isBeheerder }
    var canViewSubscription: Bool { isBeheerder }
    var canEditProfile: Bool { isBeheerder }
    var canEditSettings: Bool { isBeheerder }
    var canEditLifeStory: Bool { isBeheerder }
    var canEditReminders: Bool { isBeheerder }
    var canEditEmergencyContacts: Bool { isBeheerder }
    var canEditPeople: Bool { isBeheerder }
    var canResolveAlerts: Bool { isBeheerder }
    var canCallNow: Bool { isBeheerder }
    var canInvite: Bool { isBeheerder }
    var canManageCaregivers: Bool { isBeheerder }
    var canManageDevices: Bool { isBeheerder }
    var canPair: Bool { isBeheerder }
    var canManageSubscription: Bool { isBeheerder }
    var canExportProfile: Bool { isBeheerder }
    var canDeleteProfile: Bool { isBeheerder }
}
