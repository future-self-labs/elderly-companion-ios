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

extension ConversationMode {
    var label: String {
        switch self {
        case .gesprek, .unknown: return "Gewoon gesprek"
        case .levensverhaal: return "Verhaal-gesprek"
        }
    }
}

extension RecordingSetting {
    var label: String {
        switch self {
        case .uit: return "Uit"
        case .levensverhaal: return "Alleen bij levensverhalen"
        case .alleGesprekken: return "Alle gesprekken"
        case .unknown: return "Onbekend"
        }
    }

    func explanation(name: String) -> String {
        switch self {
        case .uit: return "Er wordt geen geluid opgenomen. Je leest wel de samenvatting en de uitgeschreven tekst van elk gesprek."
        case .levensverhaal: return "Alleen verhaal-gesprekken, zodat je later de eigen stem van \(name) bij het levensverhaal kunt terughoren."
        case .alleGesprekken: return "Elk gesprek met Noah, als \(name) daar toestemming voor geeft."
        case .unknown: return ""
        }
    }
}

/// v2.4: what the family sees, in the older person's words ("u"). The server builds these
/// sentences (`familySees`); this is the same text for when it doesn't (older backend).
enum FamilySees {
    static func sentences(sharing: SharingLevel, recording: RecordingSetting) -> [String] {
        var lines: [String]
        switch sharing {
        case .alles, .unknown:
            lines = [
                "Een korte samenvatting van elk gesprek.",
                "De uitgeschreven tekst van elk gesprek, woord voor woord.",
                "Een inschatting van hoe u zich voelde.",
            ]
        case .samenvattingen:
            lines = [
                "Een korte samenvatting van elk gesprek.",
                "Een inschatting van hoe u zich voelde.",
                "Niet de uitgeschreven tekst van uw gesprekken.",
            ]
        case .alleenMeldingen:
            lines = ["Alleen dát u met Noah heeft gepraat, en hoe lang. Niet waarover."]
        }
        lines.append("Een melding als Noah zich zorgen maakt of als u om hulp vraagt.")
        switch recording {
        case .levensverhaal: lines.append("Opnames van uw verhalen, als u daar in dat gesprek ja op zegt.")
        case .alleGesprekken: lines.append("Opnames van uw gesprekken, als u daar in dat gesprek ja op zegt.")
        case .uit, .unknown: break
        }
        return lines
    }
}

extension SharingLevel {
    /// The older person's words (they decide).
    var elderLabel: String {
        switch self {
        case .alles, .unknown: return "Alles"
        case .samenvattingen: return "Alleen samenvattingen"
        case .alleenMeldingen: return "Alleen meldingen"
        }
    }

    var elderExplanation: String {
        switch self {
        case .alles, .unknown: return "Uw familie leest de samenvatting en de uitgeschreven tekst van uw gesprekken, en ziet hoe u zich voelde."
        case .samenvattingen: return "Uw familie leest alleen een korte samenvatting en ziet hoe u zich voelde. Niet wat u woord voor woord zei."
        case .alleenMeldingen: return "Uw familie ziet alleen dát u met Noah praatte. Bij zorgen of nood krijgen ze wel een melding."
        }
    }

    /// For the caregiver ("je"), about the older person.
    func caregiverExplanation(name: String) -> String {
        switch self {
        case .alles, .unknown: return "Je leest de samenvatting en de uitgeschreven tekst van de gesprekken van \(name)."
        case .samenvattingen: return "\(name) heeft gekozen dat de familie alleen de samenvattingen leest, niet de uitgeschreven tekst."
        case .alleenMeldingen: return "\(name) heeft gekozen dat de familie alleen ziet dát er gepraat is, plus meldingen bij zorgen of nood."
        }
    }
}

extension AlertDelivery {
    /// What really went out for an alert (v2.4), for the caregiver.
    var caregiverText: String {
        if reachedNobody {
            return "Hier is niemand een bericht over gestuurd. Je ziet deze melding alleen in de app."
        }
        var parts: [String] = []
        if pushedDevices > 0 { parts.append(pushedDevices == 1 ? "een melding op 1 telefoon" : "een melding op \(pushedDevices) telefoons") }
        if sms > 0 { parts.append(sms == 1 ? "1 sms" : "\(sms) sms'jes") }
        if calls > 0 { parts.append(calls == 1 ? "1 telefoontje" : "\(calls) telefoontjes") }
        return "Verstuurd: " + DutchList.join(parts) + "."
    }
}

/// Copy that must say exactly the same everywhere (contract v2.1, founder corrections).
enum ProductCopy {
    /// Point 6: honest privacy. Never claim "geen geluidsopnames" or "alle gegevens in de EU".
    static let privacy = String(localized: "Gesprekken en gegevens worden versleuteld opgeslagen in de EU. Voor het gesprek zelf gebruikt Noah gespecialiseerde spraak- en AI-diensten; die bewaren geen gegevens langer dan nodig. Opnames alleen als jij dat aanzet én je naaste toestemming geeft.")

    /// Audit 2026-11-14 M9 / product §2e: the family reads more than summaries; say so plainly.
    static let familyReads = String(localized: "Mantelzorgers lezen van elk gesprek de samenvatting én de uitgeschreven tekst, en zien een inschatting van de stemming. Je naaste kan dat zelf beperken in de app op de eigen telefoon.")

    /// Point 5: reminders are a memory aid. Shown on every caregiver reminder screen.
    static let reminderDisclaimer = String(localized: "Noah's herinneringen zijn een extra geheugensteuntje, naast wat er al is (zoals een medicijndoos, de apotheek, thuiszorg of je eigen berichtjes). Noah houdt geen medicijngebruik bij en is geen medisch hulpmiddel. Vertrouw er niet als enige op: een gemist gesprek of een storing kan altijd.")

    /// Shorter version, shown when a caregiver creates a reminder for the first time.
    static let reminderDisclaimerShort = String(localized: "Goed om te weten: Noah is een extra geheugensteuntje, naast wat er al is. Geen medisch hulpmiddel, dus vertrouw er niet als enige op.")

    /// For the older person ("u").
    static let elderReminderNote = String(localized: "Noah helpt u herinneren, naast wat u al gebruikt, zoals uw medicijndoos of de kalender.")

    /// v2.3: the older person's own privacy line ("u"; they decide about recording themselves).
    static let elderPrivacy = String(localized: "Uw gesprekken en gegevens worden versleuteld opgeslagen in de EU. Voor het gesprek zelf gebruikt Noah gespecialiseerde spraak- en AI-diensten; die bewaren geen gegevens langer dan nodig. Opnames alleen als u dat zelf aanzet en ja zegt.")

    /// v2.3: fair use for the older person who pays themselves, kindly and in "u". Never "onbeperkt".
    static func elderFairUse(allowanceMinutes: Int) -> String {
        String(localized: "U kunt met Noah praten zo vaak als u wilt. Er geldt wel een redelijk-gebruikbeleid van \(DutchFormat.hours(minutes: allowanceMinutes)) per maand, zodat Noah voor iedereen betaalbaar blijft. Heeft u in een maand heel veel gepraat, dan blijft Noah gewoon voor u bereikbaar, met wat kortere gesprekken (tot \(Plan.cappedConversationMinutes) minuten). De maand erna is alles weer zoals gewoonlijk.")
    }

    /// Point 1: fair use, plainly and kindly. Never "onbeperkt".
    static func fairUse(name: String, allowanceMinutes: Int) -> String {
        String(localized: "Praten met Noah kan zo vaak als \(name) wil, met een redelijk-gebruikbeleid van \(DutchFormat.hours(minutes: allowanceMinutes)) per maand. Is dat op, dan blijft Noah gewoon bereikbaar, met kortere gesprekken (tot \(Plan.cappedConversationMinutes) minuten). De maand erna is alles weer zoals gewoonlijk.")
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
        // A memory aid, never medical care (contract v2.1 point 5).
        case .medicatie: return "Medicijnen (geheugensteun)"
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
        case .verbruik: return "Redelijk gebruik"
        case .apparaatGekoppeld: return "Telefoon gekoppeld"
        case .privacyGewijzigd: return "Privacy aangepast"
        case .wilStoppen: return "Wil stoppen"
        case .verwijderverzoek: return "Verzoek om te verwijderen"
        case .nummerLosgekoppeld: return "Nummer losgekoppeld"
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
        case .verbruik: return "clock.fill"
        case .apparaatGekoppeld: return "iphone.radiowaves.left.and.right"
        case .privacyGewijzigd: return "eye.slash.fill"
        case .wilStoppen: return "hand.raised.slash.fill"
        case .verwijderverzoek: return "trash.fill"
        case .nummerLosgekoppeld: return "phone.circle"
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
