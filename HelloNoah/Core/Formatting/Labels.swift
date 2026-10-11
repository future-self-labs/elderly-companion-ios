import Foundation

// Dutch display names for contract enums. Kept in one place so copy can be tuned centrally.

enum MoodText {
    /// 1…5 → "Somber" … "Heel goed".
    static func label(_ score: Double?) -> String {
        guard let score else { return "Onbekend" }
        switch score {
        case ..<1.5: return "Somber"
        case ..<2.5: return "Wat minder"
        case ..<3.5: return "Gemiddeld"
        case ..<4.5: return "Goed"
        default: return "Heel goed"
        }
    }

    static func clarity(_ score: Double?) -> String {
        guard let score else { return "Onbekend" }
        switch score {
        case ..<1.5: return "Erg verward"
        case ..<2.5: return "Wat verward"
        case ..<3.5: return "Wisselend"
        case ..<4.5: return "Helder"
        default: return "Heel helder"
        }
    }
}

extension MoodTrend {
    var label: String {
        switch self {
        case .stabiel: return "Stabiel"
        case .stijgend: return "Stijgend"
        case .dalend: return "Dalend"
        case .unknown: return "Onbekend"
        }
    }

    var systemImage: String {
        switch self {
        case .stabiel: return "arrow.right"
        case .stijgend: return "arrow.up.right"
        case .dalend: return "arrow.down.right"
        case .unknown: return "minus"
        }
    }
}

extension ConversationChannel {
    var label: String {
        switch self {
        case .app: return "Via de app"
        case .telefoonIn: return "Belde Noah"
        case .telefoonUit: return "Noah belde"
        case .unknown: return "Gesprek"
        }
    }

    var systemImage: String {
        switch self {
        case .app: return "iphone"
        case .telefoonIn: return "phone.arrow.down.left"
        case .telefoonUit: return "phone.arrow.up.right"
        case .unknown: return "bubble.left.and.bubble.right"
        }
    }
}

extension LifeStoryCategory {
    var label: String {
        switch self {
        case .jeugd: return "Jeugd"
        case .familie: return "Familie"
        case .werk: return "Werk"
        case .hobbys: return "Hobby's"
        case .reizen: return "Reizen"
        case .belangrijkeMomenten: return "Belangrijke momenten"
        case .dagelijksLeven: return "Dagelijks leven"
        case .unknown: return "Overig"
        }
    }

    var systemImage: String {
        switch self {
        case .jeugd: return "figure.and.child.holdinghands"
        case .familie: return "heart.fill"
        case .werk: return "briefcase.fill"
        case .hobbys: return "leaf.fill"
        case .reizen: return "airplane"
        case .belangrijkeMomenten: return "star.fill"
        case .dagelijksLeven: return "cup.and.saucer.fill"
        case .unknown: return "book.fill"
        }
    }
}

extension ReminderType {
    var label: String {
        switch self {
        case .medicatie: return "Medicatie"
        case .afspraak: return "Afspraak"
        case .verjaardag: return "Verjaardag"
        case .routine: return "Routine"
        case .overig: return "Overig"
        case .unknown: return "Herinnering"
        }
    }

    var systemImage: String {
        switch self {
        case .medicatie: return "pills.fill"
        case .afspraak: return "calendar"
        case .verjaardag: return "gift.fill"
        case .routine: return "sun.max.fill"
        case .overig, .unknown: return "bell.fill"
        }
    }
}

extension ReminderDelivery {
    var label: String {
        switch self {
        case .bellen: return "Noah belt op dat moment"
        case .inGesprek: return "Noah noemt het in het volgende gesprek"
        case .unknown: return "Onbekend"
        }
    }

    var shortLabel: String {
        switch self {
        case .bellen: return "Noah belt"
        case .inGesprek: return "In gesprek"
        case .unknown: return "Onbekend"
        }
    }
}

extension ReminderSchedule.Kind {
    var label: String {
        switch self {
        case .eenmalig: return "Eenmalig"
        case .dagelijks: return "Dagelijks"
        case .wekelijks: return "Wekelijks"
        }
    }
}

extension AlertType {
    var label: String {
        switch self {
        case .lageStemming: return "Lage stemming"
        case .stemmingsdaling: return "Stemming gedaald"
        case .zorgelijkSignaal: return "Zorgelijk signaal"
        case .geenContact: return "Geen contact"
        case .hulpvraag: return "Hulpvraag"
        case .oplichting: return "Mogelijke oplichting"
        case .verwardheid: return "Verwardheid"
        case .noodgeval: return "Noodgeval"
        case .unknown: return "Melding"
        }
    }

    var systemImage: String {
        switch self {
        case .lageStemming, .stemmingsdaling: return "cloud.rain.fill"
        case .zorgelijkSignaal: return "exclamationmark.bubble.fill"
        case .geenContact: return "phone.down.fill"
        case .hulpvraag: return "hand.raised.fill"
        case .oplichting: return "shield.lefthalf.filled"
        case .verwardheid: return "questionmark.circle.fill"
        case .noodgeval: return "staroflife.fill"
        case .unknown: return "bell.fill"
        }
    }
}

extension AlertSeverity {
    var label: String {
        switch self {
        case .info: return "Ter info"
        case .waarschuwing: return "Let op"
        case .urgent: return "Urgent"
        case .nood: return "Nood"
        case .unknown: return "Melding"
        }
    }

    /// Higher = more serious; used for sorting.
    var rank: Int {
        switch self {
        case .nood: return 4
        case .urgent: return 3
        case .waarschuwing: return 2
        case .info: return 1
        case .unknown: return 0
        }
    }
}

extension AlertStatus {
    var label: String {
        switch self {
        case .open: return "Nieuw"
        case .gezien: return "Gezien"
        case .afgehandeld: return "Afgehandeld"
        case .unknown: return "Onbekend"
        }
    }
}

extension Role {
    var label: String {
        switch self {
        case .beheerder: return "Beheerder"
        case .lezer: return "Lezer"
        case .unknown: return "Onbekend"
        }
    }

    var explanation: String {
        switch self {
        case .beheerder: return "Kan alles zien en instellen, ook het abonnement."
        case .lezer: return "Kan meelezen: gesprekken, stemming, levensverhaal en meldingen."
        case .unknown: return ""
        }
    }
}

extension AddressForm {
    var label: String {
        switch self {
        case .u, .unknown: return "Met \u{201C}u\u{201D}"
        case .jij: return "Met \u{201C}jij\u{201D}"
        }
    }
}

extension Gender {
    var label: String {
        switch self {
        case .man: return "Man"
        case .vrouw: return "Vrouw"
        case .anders: return "Anders"
        case .unknown: return "Zeg ik liever niet"
        }
    }
}

extension LivingSituation {
    var label: String {
        switch self {
        case .alleen: return "Woont alleen"
        case .metPartner: return "Met partner"
        case .metFamilie: return "Met familie"
        case .zorginstelling: return "In een zorginstelling"
        case .unknown: return "Onbekend"
        }
    }
}

extension NoahVoice {
    var label: String {
        switch self {
        case .vrouw: return "Vrouwenstem"
        case .man: return "Mannenstem"
        case .unknown: return "Standaard"
        }
    }
}

extension SubscriptionStatus {
    var label: String {
        switch self {
        case .actief: return "Actief"
        case .intro: return "Actief (introductieprijs)"
        case .beta: return "Gratis (bètatest)"
        case .verlopen: return "Verlopen"
        case .geen: return "Geen abonnement"
        case .unknown: return "Onbekend"
        }
    }
}
