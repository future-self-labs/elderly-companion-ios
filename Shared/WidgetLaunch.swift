import Foundation
import Security

/// Lets the app tell the app's own "Praat met Noah" widget apart from any other
/// `hellonoah://praat` link (security audit M11).
///
/// A link from a web page, a message or another app opens the conversation screen and waits for a
/// visible tap before the microphone starts. The widget may start at once: its URL carries a
/// random per-install token that only the app and the widget can read (a Keychain item in the
/// shared access group `<team>.ai.hellonoah.shared`, this device only). If the token can't be
/// read, the widget falls back to the plain link and the app simply asks for the tap.
enum WidgetLaunch {
    static let talkHost = "praat"
    static let tokenQueryItem = "t"
    static let sourceQueryItem = "bron"
    static let widgetSource = "widget"

    private static let service = "ai.hellonoah.widget"
    private static let account = "launchToken"

    /// `<team id>.ai.hellonoah.shared`, from Info.plist (`HNSharedKeychainGroup`).
    static var accessGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "HNSharedKeychainGroup") as? String,
              !group.isEmpty, !group.hasPrefix("$(") else { return nil }
        return group
    }

    /// The link the widget opens.
    static func talkURL(token: String?) -> URL {
        var components = URLComponents()
        components.scheme = "hellonoah"
        components.host = talkHost
        var items = [URLQueryItem(name: sourceQueryItem, value: widgetSource)]
        if let token, !token.isEmpty { items.append(URLQueryItem(name: tokenQueryItem, value: token)) }
        components.queryItems = items
        return components.url ?? URL(string: "hellonoah://praat")!
    }

    /// The stored token, if any (app and widget).
    static func storedToken() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    /// Creates the token once (app). Returns true when a new token was stored, so the widget's
    /// timeline should be reloaded.
    @discardableResult
    static func ensureToken() -> Bool {
        guard storedToken() == nil, let accessGroup else { return false }
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return false }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8),
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Whether `url` is the widget's link with the right token.
    static func isVerifiedWidgetLink(_ url: URL, expectedToken: String?) -> Bool {
        guard let expectedToken, !expectedToken.isEmpty,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = items.first(where: { $0.name == tokenQueryItem })?.value else { return false }
        // Constant-time comparison.
        let a = Array(token.utf8), b = Array(expectedToken.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
