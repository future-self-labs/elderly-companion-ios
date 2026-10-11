import Foundation

/// Build- and launch-time configuration.
struct AppConfig {
    static let defaultBaseURL = URL(string: "https://elderly-companion-api-production.up.railway.app/api/v2")!
    /// Launch argument `-useMockAPI YES`.
    static let mockArgumentKey = "useMockAPI"
    /// Persisted by the hidden debug toggle.
    static let mockToggleKey = "debugMockMode"

    let baseURL: URL
    let useMock: Bool
    let termsURL: URL
    let privacyURL: URL
    let supportURL: URL

    /// Reads Info.plist (from the xcconfig) and launch arguments / user defaults.
    ///
    /// - `-useMockAPI YES` runs the whole app against the in-app mock (also settable through the
    ///   hidden debug toggle, persisted in UserDefaults).
    /// - `-apiBaseURL https://…` overrides the API base URL.
    static func current(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> AppConfig {
        func url(_ key: String, fallback: String) -> URL {
            let raw = (bundle.object(forInfoDictionaryKey: key) as? String) ?? fallback
            return URL(string: raw) ?? URL(string: fallback)!
        }
        var base = url("HNAPIBaseURL", fallback: defaultBaseURL.absoluteString)
        if let override = defaults.string(forKey: "apiBaseURL"), let overrideURL = URL(string: override), overrideURL.scheme != nil {
            base = overrideURL
        }
        return AppConfig(
            baseURL: base,
            useMock: defaults.bool(forKey: mockArgumentKey) || defaults.bool(forKey: mockToggleKey),
            termsURL: url("HNTermsURL", fallback: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"),
            privacyURL: url("HNPrivacyURL", fallback: "https://hellonoah.ai/privacy"),
            supportURL: url("HNSupportURL", fallback: "https://hellonoah.ai/hulp")
        )
    }

    /// True when mock mode comes from the launch argument (the toggle can't switch it off then).
    static var isMockForcedByLaunchArgument: Bool {
        (UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[mockArgumentKey] as? String).map { ["YES", "1", "true"].contains($0) } ?? false
    }

    /// APNs environment for `POST /me/push-tokens`: debug builds talk to the sandbox.
    static var pushEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
