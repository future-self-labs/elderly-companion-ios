import Foundation

/// Links the app understands.
///
/// - `hellonoah://praat` — start a conversation right away (widget, Siri shortcut).
/// - `hellonoah://verhaal` — start a story conversation ("Vertel een verhaal", v2.1).
/// - `hellonoah://koppel/482913` — open pairing with the code filled in.
/// - `hellonoah://uitnodiging/K7P-2QX` and `https://hellonoah.ai/uitnodiging/K7P-2QX` — accept an invitation.
/// - `hellonoah://melding/<alertId>?elderly=<elderlyId>` — open an alert (also used by pushes).
enum DeepLink: Equatable {
    case talk
    case story
    case pair(code: String)
    case invitation(code: String)
    case alert(id: String, elderlyId: String?)

    static let talkURL = URL(string: "hellonoah://praat")!

    init?(url: URL) {
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
            self = .talk
        case "verhaal", "story":
            self = .story
        case "koppel", "pair":
            guard parts.count > 1 else { return nil }
            let digits = parts[1].filter(\.isNumber)
            guard digits.count == 6 else { return nil }
            self = .pair(code: digits)
        case "uitnodiging", "invite":
            guard parts.count > 1, !parts[1].isEmpty else { return nil }
            self = .invitation(code: parts[1].uppercased())
        case "melding", "alert":
            guard parts.count > 1 else { return nil }
            let elderly = components?.queryItems?.first { $0.name == "elderly" }?.value
            self = .alert(id: parts[1], elderlyId: elderly)
        default:
            return nil
        }
    }
}
