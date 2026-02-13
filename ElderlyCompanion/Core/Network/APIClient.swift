import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let message):
            return message ?? "Server error (\(code))"
        case .decodingError(let error):
            return "Data error: \(error.localizedDescription)"
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: String = APIClient.resolvedBaseURL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    private static var resolvedBaseURL: String {
        // Use the configured API URL, fallback to localhost for development
        if let url = Bundle.main.infoDictionary?["API_BASE_URL"] as? String, !url.isEmpty {
            return url
        }
        return "http://localhost:3000/api/v1"
    }

    // MARK: - Generic request methods

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", queryItems: queryItems)
        return try await perform(request)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = try buildRequest(path: path, method: "POST")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func post(_ path: String, body: some Encodable) async throws {
        var request = try buildRequest(path: path, method: "POST")
        request.httpBody = try encoder.encode(body)
        let _: EmptyResponse = try await perform(request)
    }

    // MARK: - OTP

    struct OTPCreateRequest: Encodable {
        let phoneNumber: String
    }

    struct OTPCreateResponse: Decodable {
        let message: String
    }

    struct OTPValidateRequest: Encodable {
        let phoneNumber: String
        let code: String
    }

    struct OTPValidateResponse: Decodable {
        let message: String
        let userId: String
    }

    func sendOTP(phoneNumber: String) async throws -> OTPCreateResponse {
        try await post("/otp/create", body: OTPCreateRequest(phoneNumber: phoneNumber))
    }

    func validateOTP(phoneNumber: String, code: String) async throws -> OTPValidateResponse {
        try await post("/otp/validate", body: OTPValidateRequest(phoneNumber: phoneNumber, code: code))
    }

    // MARK: - LiveKit

    struct TokenRequest: Encodable {
        let userId: String
    }

    struct TokenResponse: Decodable {
        let token: String
        let userId: String
    }

    struct CallRequest: Encodable {
        let phoneNumber: String
        let userId: String
        let message: String?
    }

    func getLiveKitToken(userId: String) async throws -> TokenResponse {
        try await post("/livekit/get-token", body: TokenRequest(userId: userId))
    }

    func initiateCall(phoneNumber: String, userId: String, message: String? = nil) async throws -> TokenResponse {
        try await post("/livekit/call", body: CallRequest(phoneNumber: phoneNumber, userId: userId, message: message))
    }

    // MARK: - Users

    struct CreateUserRequest: Encodable {
        let name: String
        let nickname: String?
        let birthYear: Int?
        let city: String?
        let phoneNumber: String
        let proactiveCallsEnabled: Bool
    }

    func createUser(_ request: CreateUserRequest) async throws -> User {
        try await post("/users", body: request)
    }

    func getUser(id: String) async throws -> User {
        try await get("/users/\(id)")
    }

    // MARK: - Memory

    func getUserMemory(userId: String) async throws -> String? {
        let response: MemoryResponse = try await get("/memory/\(userId)")
        return response.context
    }

    struct MemoryResponse: Decodable {
        let context: String?
    }

    // MARK: - Private helpers

    private func buildRequest(path: String, method: String, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = UserDefaults.standard.string(forKey: "authToken") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = try? decoder.decode(ErrorResponse.self, from: data).error
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private struct EmptyResponse: Decodable {}
}
