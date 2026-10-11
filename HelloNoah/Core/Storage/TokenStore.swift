import Foundation
import Security

/// Minimal Keychain wrapper (generic passwords), adapted from the previous Noah app.
struct Keychain {
    let service: String

    func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct CaregiverTokens: Codable, Equatable {
    var accessToken: String
    var accessTokenExpiresAt: Date
    var refreshToken: String

    /// Refresh a minute early so a request never goes out with an expiring token.
    func isExpiring(now: Date = Date()) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(now) < 60
    }
}

/// Where tokens live. The Keychain in the app, memory in tests.
protocol TokenStorage: AnyObject {
    var caregiverTokens: CaregiverTokens? { get set }
    var deviceToken: String? { get set }
}

final class InMemoryTokenStorage: TokenStorage {
    var caregiverTokens: CaregiverTokens?
    var deviceToken: String?
    init(caregiverTokens: CaregiverTokens? = nil, deviceToken: String? = nil) {
        self.caregiverTokens = caregiverTokens
        self.deviceToken = deviceToken
    }
}

/// Keychain-backed storage. Mock mode uses its own namespace so mock and live sessions never mix.
final class KeychainTokenStorage: TokenStorage {
    private let keychain: Keychain
    private let lock = NSLock()

    init(namespace: String) {
        keychain = Keychain(service: "ai.hellonoah.app.\(namespace)")
    }

    var caregiverTokens: CaregiverTokens? {
        get {
            lock.lock(); defer { lock.unlock() }
            guard let json = keychain.get("caregiverTokens"), let data = json.data(using: .utf8) else { return nil }
            return try? NoahJSON.decoder.decode(CaregiverTokens.self, from: data)
        }
        set {
            lock.lock(); defer { lock.unlock() }
            let json = newValue.flatMap { try? NoahJSON.encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
            keychain.set(json, for: "caregiverTokens")
        }
    }

    var deviceToken: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return keychain.get("deviceToken")
        }
        set {
            lock.lock(); defer { lock.unlock() }
            keychain.set(newValue, for: "deviceToken")
        }
    }
}
