import XCTest
@testable import HelloNoah

/// Intercepts all requests of a URLSession and answers them from a handler.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Int, String)

    private static let lock = NSLock()
    private static var _handler: Handler?
    private static var _requests: [URLRequest] = []

    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); _handler = newValue; _requests = []; lock.unlock() }
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._requests.append(request)
        let handler = Self._handler
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.badServerResponse) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class TokenRefreshTests: XCTestCase {
    private let base = URL(string: "https://api.test/api/v2")!
    private let meBody = #"{ "caregiver": { "id": "c1", "name": "Anna" }, "elderly": [] }"#

    private func makeClient(tokens: CaregiverTokens?, deviceToken: String? = nil) -> (APIClient, InMemoryTokenStorage) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let storage = InMemoryTokenStorage(caregiverTokens: tokens, deviceToken: deviceToken)
        return (APIClient(baseURL: base, storage: storage, session: URLSession(configuration: configuration)), storage)
    }

    private func refreshBody(access: String, refresh: String) -> String {
        """
        { "accessToken": "\(access)", "accessTokenExpiresAt": "\(NoahJSON.formatDate(Date().addingTimeInterval(3600)))", "refreshToken": "\(refresh)",
          "caregiver": { "id": "c1", "name": "Anna" }, "isNewAccount": false }
        """
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// Five requests hit 401 at the same time: exactly one refresh, all five succeed with the new token.
    func testConcurrent401sTriggerSingleFlightRefresh() async throws {
        let (client, storage) = makeClient(tokens: CaregiverTokens(accessToken: "old", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r1"))
        let refreshCalls = Counter()
        StubURLProtocol.handler = { [meBody] request in
            if request.url!.path.hasSuffix("/auth/refresh") {
                refreshCalls.increment()
                Thread.sleep(forTimeInterval: 0.3)
                return (200, self.refreshBody(access: "new", refresh: "r2"))
            }
            switch request.value(forHTTPHeaderField: "Authorization") {
            case "Bearer new": return (200, meBody)
            default: return (401, #"{ "error": { "code": "token_expired", "message": "Verlopen" } }"#)
            }
        }
        let api = LiveNoahAPI(client: client)

        let results = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
            for _ in 0..<5 { group.addTask { try await api.me().caregiver.id } }
            var ids: [String] = []
            for try await id in group { ids.append(id) }
            return ids
        }

        XCTAssertEqual(results, Array(repeating: "c1", count: 5))
        XCTAssertEqual(refreshCalls.value, 1, "refresh tokens rotate, so only one refresh may run")
        XCTAssertEqual(storage.caregiverTokens?.accessToken, "new")
        XCTAssertEqual(storage.caregiverTokens?.refreshToken, "r2")
    }

    func testExpiringTokenIsRefreshedBeforeTheRequest() async throws {
        let (client, storage) = makeClient(tokens: CaregiverTokens(accessToken: "old", accessTokenExpiresAt: Date().addingTimeInterval(20), refreshToken: "r1"))
        StubURLProtocol.handler = { [meBody] request in
            if request.url!.path.hasSuffix("/auth/refresh") { return (200, self.refreshBody(access: "fresh", refresh: "r2")) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
            return (200, meBody)
        }
        _ = try await LiveNoahAPI(client: client).me()
        XCTAssertEqual(storage.caregiverTokens?.accessToken, "fresh")
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url!.path.hasSuffix("/auth/refresh") }.count, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 2, "no request should go out with the expiring token")
    }

    func testInvalidRefreshTokenSignsOut() async throws {
        let (client, storage) = makeClient(tokens: CaregiverTokens(accessToken: "old", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "bad"))
        let expired = expectation(description: "session expired callback")
        await MainActor.run { client.onSessionExpired = { expired.fulfill() } }
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/refresh") {
                return (401, #"{ "error": { "code": "invalid_refresh_token", "message": "Log opnieuw in." } }"#)
            }
            return (401, #"{ "error": { "code": "token_expired", "message": "Verlopen" } }"#)
        }
        do {
            _ = try await LiveNoahAPI(client: client).me()
            XCTFail("expected sessionExpired")
        } catch {
            XCTAssertEqual(error as? APIError, .sessionExpired)
        }
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertNil(storage.caregiverTokens)
    }

    func testRefreshNetworkErrorKeepsTokens() async throws {
        let tokens = CaregiverTokens(accessToken: "old", accessTokenExpiresAt: Date().addingTimeInterval(10), refreshToken: "r1")
        let (client, storage) = makeClient(tokens: tokens)
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await LiveNoahAPI(client: client).me()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
        XCTAssertEqual(storage.caregiverTokens, tokens, "being offline must not sign the caregiver out")
    }

    func testRevokedDeviceTokenUnpairs() async throws {
        let (client, storage) = makeClient(tokens: nil, deviceToken: "hnd_1")
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hnd_1")
            return (401, #"{ "error": { "code": "device_revoked", "message": "Ontkoppeld" } }"#)
        }
        do {
            _ = try await LiveNoahAPI(client: client).deviceMe()
            XCTFail("expected deviceUnpaired")
        } catch {
            XCTAssertEqual(error as? APIError, .deviceUnpaired)
        }
        XCTAssertNil(storage.deviceToken)
    }

    func testServerErrorMessageIsSurfaced() async throws {
        let (client, _) = makeClient(tokens: nil, deviceToken: "hnd_1")
        StubURLProtocol.handler = { _ in (409, ContractFixtures.error) }
        do {
            _ = try await LiveNoahAPI(client: client).startDeviceConversation()
            XCTFail("expected 409")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "inactive")
            XCTAssertEqual(error.status, 409)
            XCTAssertEqual(error.elderMessage, "Noah is nog niet actief. Vraag uw mantelzorger om hulp.")
        }
    }

    func testRequestsUseContractPathsAndQueries() async throws {
        let (client, _) = makeClient(tokens: CaregiverTokens(accessToken: "a", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        StubURLProtocol.handler = { _ in (200, #"{ "items": [], "nextCursor": null }"#) }
        _ = try await LiveNoahAPI(client: client).alerts(elderlyId: "e1", status: .open, cursor: "c2", limit: 20)
        let url = try XCTUnwrap(StubURLProtocol.requests.first?.url)
        XCTAssertEqual(url.path, "/api/v2/elderly/e1/alerts")
        let query = Set(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { "\($0.name)=\($0.value ?? "")" } ?? [])
        XCTAssertEqual(query, ["limit=20", "cursor=c2", "status=open"])
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer a")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
