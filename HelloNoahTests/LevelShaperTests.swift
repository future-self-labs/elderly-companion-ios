import XCTest
@testable import HelloNoah

final class LevelShaperTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testRealAgentLevelsPassThrough() {
        var shaper = LevelShaper()
        let shown = shaper.levels(agent: 0.6, user: 0.0, turn: .speaking, now: start)
        XCTAssertEqual(shown.agent, 0.6, accuracy: 0.0001)
        XCTAssertFalse(shaper.isSynthetic)
    }

    func testSyntheticWaveWhileSpeakingWithoutLevels() {
        var shaper = LevelShaper()
        var values: [Double] = []
        for step in 0..<40 {
            let now = start.addingTimeInterval(1 + Double(step) * 0.05)
            values.append(shaper.levels(agent: 0, user: 0, turn: .speaking, now: now).agent)
        }
        XCTAssertTrue(shaper.isSynthetic)
        XCTAssertGreaterThan(values.max()! - values.min()!, 0.2, "the synthetic wave must visibly move")
        XCTAssertTrue(values.allSatisfy { (0...1).contains($0) })
    }

    func testNoSyntheticWaveRightAfterRealLevels() {
        var shaper = LevelShaper()
        _ = shaper.levels(agent: 0.5, user: 0, turn: .speaking, now: start)
        let shown = shaper.levels(agent: 0.0, user: 0, turn: .speaking, now: start.addingTimeInterval(0.2))
        XCTAssertEqual(shown.agent, 0, "a short pause between words stays real")
        XCTAssertFalse(shaper.isSynthetic)
    }

    func testListeningBreathesWhenMicIsSilent() {
        var shaper = LevelShaper()
        let shown = shaper.levels(agent: 0, user: 0, turn: .listening, now: start.addingTimeInterval(2))
        XCTAssertGreaterThan(shown.user, 0.02)
        XCTAssertLessThan(shown.user, 0.15, "listening stays calm")
    }
}
