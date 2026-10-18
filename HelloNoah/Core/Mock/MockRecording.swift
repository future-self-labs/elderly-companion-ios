import Foundation

// Mock mode exists only in Debug builds: Release (TestFlight, App Store) cannot reach it.
#if DEBUG

/// A generated demo "recording" for mock mode, so the players can be tried without a backend:
/// a calm 40-second melody written once as a small WAV file in the temporary directory.
enum MockRecording {
    static let durationSeconds: Double = 40
    private static let sampleRate = 11_025

    /// A file URL that AVPlayer can play. Generated on first use.
    static func fileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hellonoah-demo-opname.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData().write(to: url, options: .atomic)
        }
        return url
    }

    static func wavData() -> Data {
        let count = Int(durationSeconds) * sampleRate
        // A slow pentatonic phrase (A minor), one note per 0.8 s, over a soft drone.
        let notes: [Double] = [440, 523.25, 587.33, 659.25, 587.33, 523.25, 440, 392, 440, 523.25]
        let noteLength = 0.8
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let noteIndex = Int(t / noteLength) % notes.count
            let local = t.truncatingRemainder(dividingBy: noteLength)
            let envelope = min(1, local / 0.05) * exp(-local * 2.6)
            let melody = sin(2 * .pi * notes[noteIndex] * t) * envelope * 0.32
            let drone = sin(2 * .pi * 110 * t) * 0.08 + sin(2 * .pi * 165 * t) * 0.04
            let fade = min(1, t / 1.5, (durationSeconds - t) / 1.5)
            samples[i] = Int16(max(-1, min(1, (melody + drone) * fade)) * Double(Int16.max))
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        samples.withUnsafeBufferPointer { buffer in
            for sample in buffer { append(sample) }
        }
        return data
    }
}

#endif
