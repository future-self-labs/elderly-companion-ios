import Foundation

/// Which token a request carries.
enum AuthKind {
    case none
    case caregiver
    case device
}

/// Makes sure only one `POST /auth/refresh` runs at a time. Refresh tokens rotate, so two parallel
/// refreshes would invalidate each other: every caller that needs a fresh token awaits the same task.
actor TokenRefresher {
    typealias RefreshCall = @Sendable (_ refreshToken: String) async throws -> AuthResponse

    private let storage: TokenStorage
    private let refreshCall: RefreshCall
    private var inFlight: Task<CaregiverTokens, Error>?
    private(set) var refreshCount = 0

    init(storage: TokenStorage, refreshCall: @escaping RefreshCall) {
        self.storage = storage
        self.refreshCall = refreshCall
    }

    /// A non-expiring access token, refreshing first when needed.
    func validAccessToken(now: Date = Date()) async throws -> String {
        if let inFlight { return try await inFlight.value.accessToken }
        guard let tokens = storage.caregiverTokens else { throw APIError.sessionExpired }
        if tokens.isExpiring(now: now) {
            return try await refresh(rejecting: nil).accessToken
        }
        return tokens.accessToken
    }

    /// Refreshes the token pair. If `rejecting` is given and the stored token is already a different
    /// (newer) one, that one is returned without another refresh.
    func refresh(rejecting rejectedToken: String?) async throws -> CaregiverTokens {
        if let inFlight { return try await inFlight.value }
        guard let current = storage.caregiverTokens else { throw APIError.sessionExpired }
        if let rejectedToken, current.accessToken != rejectedToken, !current.isExpiring() {
            return current
        }

        refreshCount += 1
        let call = refreshCall
        let task = Task { () throws -> CaregiverTokens in
            let response = try await call(current.refreshToken)
            return CaregiverTokens(
                accessToken: response.accessToken,
                accessTokenExpiresAt: response.accessTokenExpiresAt,
                refreshToken: response.refreshToken
            )
        }
        inFlight = task
        do {
            let tokens = try await task.value
            storage.caregiverTokens = tokens
            inFlight = nil
            return tokens
        } catch {
            inFlight = nil
            let apiError = APIError.from(error)
            switch apiError {
            case .server(let status, _, _) where status == 400 || status == 401 || status == 403:
                storage.caregiverTokens = nil
                throw APIError.sessionExpired
            default:
                throw apiError
            }
        }
    }
}

/// HTTP client for API v2: JSON coding, auth headers, Dutch errors, single-flight token refresh.
final class APIClient {
    let baseURL: URL
    let storage: TokenStorage
    private let session: URLSession
    private(set) lazy var refresher = TokenRefresher(storage: storage) { [weak self] refreshToken in
        guard let self else { throw APIError.cancelled }
        return try await self.send(
            "POST", "/auth/refresh",
            body: ["refreshToken": refreshToken],
            auth: .none
        )
    }

    /// Called on the main actor when the caregiver must sign in again.
    var onSessionExpired: (@MainActor () -> Void)?
    /// Called on the main actor when the device token was revoked.
    var onDeviceUnpaired: (@MainActor () -> Void)?

    init(baseURL: URL, storage: TokenStorage, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.storage = storage
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 25
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: Public API

    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        auth: AuthKind
    ) async throws -> T {
        let data = try await perform(method, path, query: query, body: body, auth: auth)
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try NoahJSON.decoder.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func sendVoid(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        auth: AuthKind
    ) async throws {
        _ = try await perform(method, path, query: query, body: body, auth: auth)
    }

    /// Raw response body (exports).
    func sendData(_ method: String, _ path: String, auth: AuthKind) async throws -> Data {
        try await perform(method, path, query: [], body: nil, auth: auth)
    }

    // MARK: Internals

    private func perform(
        _ method: String,
        _ path: String,
        query: [URLQueryItem],
        body: (any Encodable)?,
        auth: AuthKind
    ) async throws -> Data {
        let bodyData = try body.map { try NoahJSON.encoder.encode(AnyEncodable($0)) }

        var token: String?
        switch auth {
        case .none:
            token = nil
        case .caregiver:
            token = try await caregiverToken { try await self.refresher.validAccessToken() }
        case .device:
            guard let deviceToken = storage.deviceToken else { throw APIError.deviceUnpaired }
            token = deviceToken
        }

        var (data, response) = try await transport(method, path, query: query, body: bodyData, token: token)

        if response.statusCode == 401 {
            switch auth {
            case .caregiver:
                let rejected = token
                let fresh = try await caregiverToken { try await self.refresher.refresh(rejecting: rejected).accessToken }
                (data, response) = try await transport(method, path, query: query, body: bodyData, token: fresh)
                if response.statusCode == 401 {
                    storage.caregiverTokens = nil
                    await notifySessionExpired()
                    throw APIError.sessionExpired
                }
            case .device:
                storage.deviceToken = nil
                await notifyDeviceUnpaired()
                throw APIError.deviceUnpaired
            case .none:
                break
            }
        }

        guard (200..<300).contains(response.statusCode) else {
            throw Self.error(from: data, status: response.statusCode)
        }
        return data
    }

    /// Runs a token lookup and turns `sessionExpired` into a sign-out notification.
    private func caregiverToken(_ body: () async throws -> String) async throws -> String {
        do {
            return try await body()
        } catch APIError.sessionExpired {
            await notifySessionExpired()
            throw APIError.sessionExpired
        }
    }

    private func transport(
        _ method: String,
        _ path: String,
        query: [URLQueryItem],
        body: Data?,
        token: String?
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.unexpected("Ongeldige URL") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("nl-NL", forHTTPHeaderField: "Accept-Language")
        request.setValue("HelloNoah-iOS/\(AppConfig.appVersion)", forHTTPHeaderField: "X-HelloNoah-Client")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.unexpected("Geen HTTP-antwoord") }
            return (data, http)
        } catch {
            throw APIError.from(error)
        }
    }

    static func error(from data: Data, status: Int) -> APIError {
        if let body = try? NoahJSON.decoder.decode(APIErrorBody.self, from: data) {
            return .server(status: status, code: body.error.code, message: body.error.message)
        }
        return .server(status: status, code: "http_\(status)", message: nil)
    }

    @MainActor private func notifySessionExpired() { onSessionExpired?() }
    @MainActor private func notifyDeviceUnpaired() { onDeviceUnpaired?() }
}

/// Type-erased Encodable so bodies of any type can be passed around.
struct AnyEncodable: Encodable {
    private let encodeBody: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeBody = value.encode }
    func encode(to encoder: Encoder) throws { try encodeBody(encoder) }
}
