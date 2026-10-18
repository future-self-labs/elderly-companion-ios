import UIKit
import XCTest
@testable import HelloNoah

/// The edges of a voice session: hanging up while Noah is still being "called" must never leave
/// a live session (open microphone) behind, and the maximum duration ends calmly (audit H1, M4).
@MainActor
final class ConversationControllerTests: XCTestCase {
    /// Connects only when the test says so, and (like a slow SDK) ignores a stop while connecting.
    final class SlowEngine: VoiceEngine {
        var onEvent: ((VoiceEvent) -> Void)?
        var stopCount = 0
        var contexts: [String] = []
        private var release: CheckedContinuation<Void, Never>?
        private(set) var isConnecting = false

        func start(_ session: ConversationSession) async throws {
            isConnecting = true
            await withCheckedContinuation { release = $0 }
            isConnecting = false
            onEvent?(.connected)
        }

        func connect() {
            release?.resume()
            release = nil
        }

        func stop() async { stopCount += 1 }
        func sendContext(_ text: String) async { contexts.append(text) }
    }

    private func makeAPI() -> MockNoahAPI {
        let defaults = UserDefaults(suiteName: "ConversationControllerTests")!
        defaults.removePersistentDomain(forName: "ConversationControllerTests")
        defaults.set(0.0, forKey: "mockLatency")
        return MockNoahAPI(defaults: defaults)
    }

    func testHangUpWhileConnectingStopsTheLateSession() async throws {
        let engine = SlowEngine()
        let controller = ConversationController(api: makeAPI(), reachability: Reachability(), requestMicrophone: { .granted }) { engine }
        let start = Task { await controller.start() }

        while !engine.isConnecting { await Task.yield() }
        XCTAssertEqual(controller.phase, .connecting)

        await controller.hangUp()
        XCTAssertEqual(controller.phase, .ended(.hungUp))
        XCTAssertEqual(engine.stopCount, 1)

        // The SDK finishes connecting after all.
        engine.connect()
        await start.value

        XCTAssertEqual(controller.phase, .ended(.hungUp), "must not come back to life")
        XCTAssertGreaterThanOrEqual(engine.stopCount, 2, "the late session must be ended")
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "the screen may sleep again")
        XCTAssertEqual(controller.elapsed, 0)
    }

    func testMockEngineNeverConnectsAfterAStop() async throws {
        let engine = MockVoiceEngine()
        engine.connectDelay = 0.2
        var events: [String] = []
        engine.onEvent = { event in
            if case .connected = event { events.append("connected") }
        }
        let session = ConversationSession(agentId: "a", conversationToken: "t", dynamicVariables: nil, overrides: nil,
                                          maxDurationSeconds: 60, mode: .gesprek, recording: false)
        let start = Task { try await engine.start(session) }
        await engine.stop()
        do {
            try await start.value
            XCTFail("start must report the cancellation")
        } catch {
            XCTAssertTrue(error is VoiceStartCancelled)
        }
        XCTAssertEqual(events, [])
    }

    func testMaximumDurationWaitsForNoahsGoodbye() {
        let max: TimeInterval = 600
        XCTAssertFalse(ConversationController.shouldEndForMaxDuration(elapsed: 599, maxDuration: max, turn: .listening))
        XCTAssertTrue(ConversationController.shouldEndForMaxDuration(elapsed: 600, maxDuration: max, turn: .listening))
        // Noah is still saying goodbye: give him a moment…
        XCTAssertFalse(ConversationController.shouldEndForMaxDuration(elapsed: 610, maxDuration: max, turn: .speaking))
        // …but not forever.
        XCTAssertTrue(ConversationController.shouldEndForMaxDuration(elapsed: 600 + ConversationController.goodbyeGrace, maxDuration: max, turn: .speaking))
        XCTAssertTrue(ConversationController.wrapUpContext.contains("afscheid"))
    }

    func testStatusUsesTheConfiguredName() {
        let controller = ConversationController(api: makeAPI(), reachability: Reachability(), noahName: "Fleur", requestMicrophone: { .granted }) { MockVoiceEngine() }
        XCTAssertEqual(controller.statusText, "Fleur wordt gebeld…")
    }
}
