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
        // Do NOT convert to snake_case — our backend expects camelCase
    }

    // MARK: - API URL Configuration
    static let deployedURL: String? = "https://elderly-companion-api-production.up.railway.app/api/v1"

    private static var resolvedBaseURL: String {
        // 1. Use deployed URL if set
        if let url = deployedURL {
            return url
        }
        // 2. Use Info.plist override
        if let url = Bundle.main.infoDictionary?["API_BASE_URL"] as? String, !url.isEmpty {
            return url
        }
        // 3. Fallback to local development
        #if targetEnvironment(simulator)
        return "http://localhost:3000/api/v1"
        #else
        return "http://192.168.178.178:3000/api/v1"
        #endif
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

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = try buildRequest(path: path, method: "PUT")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func delete(_ path: String) async throws {
        var request = try buildRequest(path: path, method: "DELETE")
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
        let token: String? // JWT auth token
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

    func getLiveKitPipelineToken(userId: String) async throws -> TokenResponse {
        try await post("/livekit/get-token-pipeline", body: TokenRequest(userId: userId))
    }

    struct CallResponse: Decodable {
        // The server returns { participant: { ... } } - we just need to know it succeeded
        let participant: AnyCodable?
    }

    // Wrapper to accept any JSON value we don't need to inspect
    struct AnyCodable: Decodable {
        init(from decoder: Decoder) throws {
            // Accept any value - we don't need the participant details
            _ = try? decoder.singleValueContainer()
        }
    }

    func initiateCall(phoneNumber: String, userId: String, message: String? = nil) async throws {
        let _: CallResponse = try await post("/livekit/call", body: CallRequest(phoneNumber: phoneNumber, userId: userId, message: message))
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

    // MARK: - Transcripts

    struct TranscriptMessage: Codable {
        let role: String
        let content: String
        let timestamp: String
    }

    struct SaveTranscriptRequest: Encodable {
        let userId: String
        let duration: Int
        let messages: [TranscriptMessage]
        let tags: [String]
        let summary: String?
    }

    struct TranscriptRecord: Decodable, Identifiable {
        let id: String
        let userId: String
        let duration: Int
        let messages: [TranscriptMessage]
        let tags: [String]
        let summary: String?
        let createdAt: String
    }

    struct TranscriptsResponse: Decodable {
        let transcripts: [TranscriptRecord]
    }

    func saveTranscript(_ request: SaveTranscriptRequest) async throws -> TranscriptRecord {
        try await post("/transcripts", body: request)
    }

    func getTranscripts(userId: String) async throws -> [TranscriptRecord] {
        let response: TranscriptsResponse = try await get("/transcripts/\(userId)")
        return response.transcripts
    }

    // MARK: - Scheduled Calls

    struct ScheduledCallRequest: Encodable {
        let userId: String
        let phoneNumber: String
        let type: String
        let title: String
        let message: String?
        let time: String
        let days: [Int]
        let enabled: Bool
    }

    struct ScheduledCallRecord: Decodable, Identifiable {
        let id: String
        let userId: String
        let phoneNumber: String
        let type: String
        let title: String
        let message: String?
        let time: String
        let days: [Int]
        let enabled: Bool
        let createdAt: String
    }

    struct ScheduledCallsResponse: Decodable {
        let scheduledCalls: [ScheduledCallRecord]
    }

    struct ScheduledCallUpdateRequest: Encodable {
        let enabled: Bool?
        let time: String?
        let days: [Int]?
    }

    func createScheduledCall(_ request: ScheduledCallRequest) async throws -> ScheduledCallRecord {
        try await post("/scheduled-calls", body: request)
    }

    func getScheduledCalls(userId: String) async throws -> [ScheduledCallRecord] {
        let response: ScheduledCallsResponse = try await get("/scheduled-calls/\(userId)")
        return response.scheduledCalls
    }

    func updateScheduledCall(id: String, update: ScheduledCallUpdateRequest) async throws {
        let _: ScheduledCallRecord = try await put("/scheduled-calls/\(id)", body: update)
    }

    func deleteScheduledCall(id: String) async throws {
        try await delete("/scheduled-calls/\(id)")
    }

    // MARK: - Health Data

    struct HealthSnapshotRequest: Encodable {
        let userId: String
        let stepCount: Int
        let heartRate: Int
        let bloodOxygen: Int
        let bloodPressureSystolic: Int
        let bloodPressureDiastolic: Int
        let sleepHours: String
    }

    struct HealthSnapshotResponse: Decodable {
        let id: String?
    }

    func sendHealthSnapshot(_ request: HealthSnapshotRequest) async throws {
        let _: HealthSnapshotResponse = try await post("/health-data", body: request)
    }

    // MARK: - Family Contacts

    struct FamilyContactRequest: Encodable {
        let userId: String
        let name: String
        let phoneNumber: String
        let relationship: String
        let whatsappUpdatesEnabled: Bool
    }

    struct FamilyContactRecord: Decodable, Identifiable {
        let id: String
        let userId: String
        let name: String
        let phoneNumber: String
        let relationship: String
        let whatsappUpdatesEnabled: Bool
        let createdAt: String
    }

    struct FamilyContactsResponse: Decodable {
        let familyContacts: [FamilyContactRecord]
    }

    func createFamilyContact(_ request: FamilyContactRequest) async throws -> FamilyContactRecord {
        try await post("/family", body: request)
    }

    func getFamilyContacts(userId: String) async throws -> [FamilyContactRecord] {
        let response: FamilyContactsResponse = try await get("/family/\(userId)")
        return response.familyContacts
    }

    func deleteFamilyContact(id: String) async throws {
        try await delete("/family/\(id)")
    }

    // MARK: - People (Memory Vault)

    struct PersonRequest: Encodable {
        let elderlyUserId: String
        let addedByUserId: String?
        let name: String
        let nickname: String?
        let relationship: String
        let phoneNumber: String?
        let email: String?
        let birthDate: String?
        let notes: String?
    }

    struct PersonRecord: Decodable, Identifiable {
        let id: String
        let elderlyUserId: String
        let addedByUserId: String?
        let name: String
        let nickname: String?
        let relationship: String
        let phoneNumber: String?
        let email: String?
        let birthDate: String?
        let notes: String?
        let photoUrl: String?
        let createdAt: String
    }

    struct PeopleResponse: Decodable {
        let people: [PersonRecord]
    }

    func createPerson(_ request: PersonRequest) async throws -> PersonRecord {
        try await post("/people", body: request)
    }

    func getPeople(elderlyUserId: String) async throws -> [PersonRecord] {
        let response: PeopleResponse = try await get("/people/\(elderlyUserId)")
        return response.people
    }

    func deletePerson(id: String) async throws {
        try await delete("/people/\(id)")
    }

    // MARK: - Events

    struct EventRequest: Encodable {
        let elderlyUserId: String
        let personId: String?
        let type: String
        let title: String
        let date: String
        let recurring: Bool
        let remindDaysBefore: Int
    }

    struct EventRecord: Decodable, Identifiable {
        let id: String
        let elderlyUserId: String
        let personId: String?
        let type: String
        let title: String
        let date: String
        let recurring: Bool
        let remindDaysBefore: Int
        let createdAt: String
        let daysUntil: Int?
    }

    struct EventsResponse: Decodable {
        let events: [EventRecord]
    }

    func createEvent(_ request: EventRequest) async throws -> EventRecord {
        try await post("/events", body: request)
    }

    func getEvents(elderlyUserId: String) async throws -> [EventRecord] {
        let response: EventsResponse = try await get("/events/\(elderlyUserId)")
        return response.events
    }

    func getUpcomingEvents(elderlyUserId: String, days: Int = 7) async throws -> [EventRecord] {
        let response: EventsResponse = try await get("/events/\(elderlyUserId)/upcoming", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        return response.events
    }

    func deleteEvent(id: String) async throws {
        try await delete("/events/\(id)")
    }

    // MARK: - Legacy Stories

    struct LegacyStoryRecord: Decodable, Identifiable {
        let id: String
        let elderlyUserId: String
        let transcriptId: String?
        let title: String
        let summary: String?
        let audioUrl: String?
        let audioDuration: Int?
        let tags: [String]
        let peopleMentioned: [String]
        let isStarred: Bool
        let createdAt: String
    }

    struct LegacyStoriesResponse: Decodable {
        let stories: [LegacyStoryRecord]
    }

    func getLegacyStories(elderlyUserId: String) async throws -> [LegacyStoryRecord] {
        let response: LegacyStoriesResponse = try await get("/legacy-stories/\(elderlyUserId)")
        return response.stories
    }

    // MARK: - Wellbeing

    struct WellbeingSummaryResponse: Decodable {
        let summary: WellbeingSummary?
    }

    struct WellbeingSummary: Decodable {
        let period: String
        let averageMoodScore: Double?
        let totalConversations: Int
        let totalMinutes: Int
        let activeDays: Int
        let concerns: [String]
        let topTopics: [String]
    }

    func getWellbeingSummary(elderlyUserId: String) async throws -> WellbeingSummary? {
        let response: WellbeingSummaryResponse = try await get("/wellbeing/\(elderlyUserId)/summary")
        return response.summary
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

        if let token = KeychainService.authToken {
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
