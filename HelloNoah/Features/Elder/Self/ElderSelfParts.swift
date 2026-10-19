import SwiftUI

// Building blocks for the older person's own sign-up and settings (v2.3 self route).
// Formal "u", big type, one clear action per screen.

/// "Stap 2 van 5" above a big title.
struct ElderStepHeader: View {
    let step: Int
    let total: Int
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.xs) {
            Text("Stap \(step) van \(total)")
                .font(NoahFont.Elder.label)
                .foregroundColor(NoahColor.accent)
                .accessibilityIdentifier("elder.step")
            Text(title)
                .font(NoahFont.Elder.hero).noahElderTitleScaling()
                .foregroundColor(NoahColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Big title of an older person's sub-screen.
struct ElderScreenTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(NoahFont.Elder.hero).noahElderTitleScaling()
            .foregroundColor(NoahColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Body copy in the older person's size.
struct ElderText: View {
    let text: String
    var color: Color = NoahColor.textSoft

    init(_ text: String, color: Color = NoahColor.textSoft) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(verbatim: text)
            .font(NoahFont.Elder.body)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Scrolling older person's sub-screen with the standard margins and chrome.
struct ElderScrollScreen<Content: View>: View {
    var showsBack = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                if showsBack { ElderBackButton() }
                content()
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.m)
            .noahReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .noahElderScreenScaling()
        .elderSubscreen()
    }
}

/// Error or success line in the older person's size.
struct ElderMessage: View {
    let text: String
    var isError = true

    var body: some View {
        NoahNotice(kind: isError ? .error : .success, text: text, large: true)
    }
}

/// Name and number of someone Noah may warn (onboarding and settings).
struct ElderContactFields: View {
    @Binding var name: String
    @Binding var phone: String
    var phoneError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            NoahTextField(label: "Naam", text: $name, prompt: "Ellen", contentType: .name,
                          autocapitalization: .words, large: true)
                .accessibilityIdentifier("contact.name")
            NoahTextField(label: "Telefoonnummer", text: $phone, prompt: "06 12345678", error: phoneError,
                          keyboard: .phonePad, contentType: .telephoneNumber, autocapitalization: .never, large: true)
                .accessibilityIdentifier("contact.phone")
        }
    }
}

/// The three speaking speeds the older person chooses from (instead of a fiddly slider).
enum ElderSpeed: CaseIterable {
    case rustiger, normaal, vlotter

    var value: Double {
        switch self {
        case .rustiger: return 0.9
        case .normaal: return 1.0
        case .vlotter: return 1.1
        }
    }

    var label: String {
        switch self {
        case .rustiger: return "Rustiger"
        case .normaal: return "Normaal"
        case .vlotter: return "Wat vlotter"
        }
    }

    var explanation: String {
        switch self {
        case .rustiger: return "Noah praat wat langzamer. Fijn als u minder goed hoort."
        case .normaal: return "Zoals de meeste mensen praten."
        case .vlotter: return "Noah praat iets sneller."
        }
    }

    /// The choice closest to a stored speed (a caregiver may have set 0.85).
    static func nearest(to speed: Double) -> ElderSpeed {
        allCases.min { abs($0.value - speed) < abs($1.value - speed) } ?? .normaal
    }
}

extension AddressForm {
    /// For the older person: how Noah will sound.
    var elderExample: String {
        switch self {
        case .jij: return "\u{201C}Hoe gaat het met jou?\u{201D}"
        case .u, .unknown: return "\u{201C}Hoe gaat het met u?\u{201D}"
        }
    }
}

extension Role {
    /// The older person's words for the two roles (v2.3 invitations).
    var elderLabel: String {
        switch self {
        case .lezer, .unknown: return "Meekijken"
        case .beheerder: return "Helpen beheren"
        }
    }

    var elderExplanation: String {
        switch self {
        case .lezer, .unknown:
            return "Ziet hoe het met u gaat: korte samenvattingen van uw gesprekken, hoe u zich voelt en uw levensverhaal. Kan niets veranderen."
        case .beheerder:
            return "Kan meekijken én dingen voor u regelen, zoals herinneringen, noodcontacten en het abonnement. Diegene regelt dan voortaan de instellingen; praten met Noah blijft precies hetzelfde."
        }
    }
}
