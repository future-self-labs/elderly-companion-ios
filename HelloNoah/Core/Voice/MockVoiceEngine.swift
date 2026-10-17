import Foundation

/// A scripted conversation with fake audio levels, so the conversation screen can be tested
/// without ElevenLabs (mock mode). No audio is played or recorded.
@MainActor
final class MockVoiceEngine: VoiceEngine {
    var onEvent: ((VoiceEvent) -> Void)?

    private var task: Task<Void, Never>?
    private var lines: [SubtitleLine] = []

    private enum Step {
        case noah(String, seconds: Double)
        case user(String, seconds: Double)
        case think(seconds: Double)
    }

    private func script(name: String, mode: ConversationMode?, recording: Bool) -> [Step] {
        if mode == .levensverhaal {
            var steps: [Step] = []
            if recording {
                steps += [
                    .noah("Goedemiddag \(name)! Mag ik dit gesprek opnemen, zodat uw familie later uw eigen stem kan terughoren?", seconds: 5.5),
                    .user("Ja hoor, dat is goed.", seconds: 1.8),
                    .think(seconds: 0.8),
                ]
            }
            steps += [
                .noah("Dank u wel. U vertelde eens over uw trouwdag met Margriet. Wilt u daar meer over vertellen?", seconds: 5),
                .user("Het regende die dag. Het goot! Maar niemand ging naar binnen.", seconds: 3.6),
                .think(seconds: 1),
                .noah("Niemand ging naar binnen… Wat deden jullie toen?", seconds: 3.2),
                .user("We dansten op het plein bij de Bavo. Margriet in haar witte jurk.", seconds: 3.8),
                .noah("Hoe voelde dat, daar samen in de regen?", seconds: 2.6),
            ]
            return steps
        }
        return [
            .noah("Goedemiddag \(name)! Fijn dat u er bent. Hoe gaat het vandaag met u?", seconds: 4.5),
            .user("Goed hoor. Ik ben net terug uit de moestuin.", seconds: 3),
            .think(seconds: 1.2),
            .noah("Wat heerlijk. Vorige week vertelde u dat de tomaten bijna rijp waren. Hoe staan ze erbij?", seconds: 5),
            .user("Ze zijn rood! Ik heb er een paar voor Sara bewaard.", seconds: 3.2),
            .think(seconds: 1),
            .noah("Wat lief van u. Sara komt zaterdag, toch? Zal ik u zaterdagochtend nog even herinneren?", seconds: 5),
            .user("Ja, graag.", seconds: 1.6),
            .noah("Dat doe ik. Vertelt u eens: wat gaan jullie samen doen?", seconds: 3.5),
        ]
    }

    func start(_ session: ConversationSession) async throws {
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let name = session.dynamicVariables?["user_name"]?.stringValue ?? "Wim"
        onEvent?(.connected)
        let steps = script(name: name, mode: session.mode, recording: session.recording)
        task = Task { [weak self] in
            for step in steps {
                guard !Task.isCancelled, let self else { return }
                await self.play(step)
            }
            // Then just listen quietly until hung up.
            while !Task.isCancelled {
                guard let self else { return }
                self.onEvent?(.turn(.listening))
                await self.levels(agent: false, user: true, seconds: 1, quiet: true)
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
        onEvent?(.ended(.local))
    }

    private func play(_ step: Step) async {
        switch step {
        case .noah(let text, let seconds):
            onEvent?(.turn(.speaking))
            await reveal(text, speaker: .noah, seconds: seconds)
        case .user(let text, let seconds):
            onEvent?(.turn(.listening))
            await reveal(text, speaker: .user, seconds: seconds)
        case .think(let seconds):
            onEvent?(.turn(.thinking))
            await levels(agent: false, user: false, seconds: seconds, quiet: true)
        }
    }

    /// Shows the subtitle word by word while generating levels.
    private func reveal(_ text: String, speaker: SubtitleLine.Speaker, seconds: Double) async {
        let words = text.split(separator: " ")
        let id = UUID().uuidString
        lines.append(SubtitleLine(id: id, speaker: speaker, text: ""))
        let ticks = Int(seconds / 0.05)
        for tick in 0..<ticks {
            if Task.isCancelled { return }
            let shown = min(words.count, Int(Double(words.count) * Double(tick + 1) / Double(ticks)) + 1)
            if let index = lines.firstIndex(where: { $0.id == id }) {
                lines[index].text = words.prefix(shown).joined(separator: " ")
            }
            onEvent?(.subtitles(Array(lines.suffix(6))))
            let wave = 0.45 + 0.35 * sin(Double(tick) * 0.9) + Double.random(in: -0.15...0.2)
            onEvent?(.levels(agent: speaker == .noah ? max(0, min(1, wave)) : 0.05,
                             user: speaker == .user ? max(0, min(1, wave * 0.8)) : 0.03))
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func levels(agent: Bool, user: Bool, seconds: Double, quiet: Bool) async {
        let ticks = Int(seconds / 0.05)
        for _ in 0..<ticks {
            if Task.isCancelled { return }
            let base = quiet ? 0.06 : 0.5
            onEvent?(.levels(agent: agent ? base + Double.random(in: 0...0.1) : 0.02,
                             user: user ? base + Double.random(in: 0...0.08) : 0.02))
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
