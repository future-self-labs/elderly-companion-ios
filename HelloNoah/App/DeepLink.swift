import Foundation

/// Links the app understands. No link ever acts on its own: anything that opens the microphone,
/// pairs this phone or joins a family first waits for a visible tap (security audit H4, M10, M11).
///
/// - `hellonoah://praat` — open the conversation screen; the conversation starts after a tap.
///   Only the app's own widget (`?bron=widget&t=<per-install token>`, see `WidgetLaunch`) starts
///   it right away (`verified`).
/// - `hellonoah://verhaal` — the same for a story conversation ("Vertel een verhaal", v2.1).
/// - `hellonoah://koppel/482913` — open pairing with the code filled in (the person taps "Koppelen").
/// - `hellonoah://uitnodiging/K7P-2QX` and `https://(www.)hellonoah.ai/uitnodiging/K7P-2QX` — fill in
///   an invitation (the caregiver taps "Accepteren").
/// - `hellonoah://melding/<alertId>?elderly=<elderlyId>` — open an alert (also used by pushes).
enum DeepLink: Equatable {
    case talk(verified: Bool)
    case story
    case pair(code: String)
    case invitation(code: String)
    case alert(id: String, elderlyId: String?)

    /// Invitation codes look like `K7P-2QX` (dash optional, letters and digits).
    static func normalizedInvitationCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.range(of: "^[A-Z0-9]{3}-?[A-Z0-9]{3}$", options: .regularExpression) != nil else { return nil }
        return code.count == 6 ? "\(code.prefix(3))-\(code.suffix(3))" : code
    }

    /// - Parameter widgetToken: the per-install widget token (`WidgetLaunch.storedToken()`).
    init?(url: URL, widgetToken: String? = nil) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var parts: [String]
        switch url.scheme?.lowercased() {
        case "hellonoah":
            parts = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        case "https", "http":
            guard let host = url.host?.lowercased(), host == "hellonoah.ai" || host == "www.hellonoah.ai" else { return nil }
            parts = url.pathComponents.filter { $0 != "/" }
        default:
            return nil
        }
        parts = parts.map { $0.removingPercentEncoding ?? $0 }
        guard let first = parts.first?.lowercased() else { return nil }

        switch first {
        case "praat", "talk":
            self = .talk(verified: WidgetLaunch.isVerifiedWidgetLink(url, expectedToken: widgetToken))
        case "verhaal", "story":
            self = .story
        case "koppel", "pair":
            guard parts.count > 1 else { return nil }
            let digits = parts[1].filter(\.isNumber)
            guard digits.count == 6 else { return nil }
            self = .pair(code: digits)
        case "uitnodiging", "invite":
            guard parts.count > 1, let code = Self.normalizedInvitationCode(parts[1]) else { return nil }
            self = .invitation(code: code)
        case "melding", "alert":
            guard parts.count > 1 else { return nil }
            let elderly = components?.queryItems?.first { $0.name == "elderly" }?.value
            self = .alert(id: parts[1], elderlyId: elderly)
        default:
            return nil
        }
    }
}
