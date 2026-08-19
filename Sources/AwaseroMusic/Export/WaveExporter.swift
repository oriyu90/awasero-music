import Foundation

enum WaveExporter {
    static let sampleRate = 44_100

    static func data(for score: ScoreDocument) throws -> Data {
        guard !score.notes.isEmpty else { throw ExportError.emptyScore }
        let endBeat = score.notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
        let tailSeconds = 0.25
        let frameCount = Int((score.seconds(atBeat: endBeat) + tailSeconds) * Double(sampleRate))
        var samples = Array(repeating: Float(0), count: max(1, frameCount))
        for note in score.notes {
            let start = max(0, Int(score.seconds(atBeat: note.startBeat) * Double(sampleRate)))
            let noteEndSeconds = score.seconds(atBeat: note.startBeat + note.durationBeats)
            let length = max(1, Int((noteEndSeconds - score.seconds(atBeat: note.startBeat)) * Double(sampleRate)))
            let end = min(samples.count, start + length)
            guard start < end else { continue }
            let frequency = MusicTheory.frequency(midiNote: Double(note.midiNote))
            for index in start..<end {
                let local = index - start
                let time = Double(local) / Double(sampleRate)
                let attack = min(1, Double(local) / (Double(sampleRate) * 0.015))
                let release = min(1, Double(end - index) / (Double(sampleRate) * 0.04))
                let envelope = min(attack, release)
                let fundamental = sin(2 * .pi * frequency * time)
                let harmonic = 0.2 * sin(4 * .pi * frequency * time)
                samples[index] += Float((fundamental + harmonic) * envelope * Double(note.velocity) / 127 * 0.22)
            }
        }
        return makeWave(samples: samples)
    }

    static func write(score: ScoreDocument, to url: URL) throws {
        try data(for: score).write(to: url, options: .atomic)
    }

    private static func makeWave(samples: [Float]) -> Data {
        let pcm = samples.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        let dataSize = UInt32(pcm.count * 2)
        var data = Data("RIFF".utf8)
        data.appendLE(36 + dataSize)
        data.append(Data("WAVEfmt ".utf8))
        data.appendLE(UInt32(16)); data.appendLE(UInt16(1)); data.appendLE(UInt16(1))
        data.appendLE(UInt32(sampleRate)); data.appendLE(UInt32(sampleRate * 2))
        data.appendLE(UInt16(2)); data.appendLE(UInt16(16))
        data.append(Data("data".utf8)); data.appendLE(dataSize)
        for sample in pcm { data.appendLE(UInt16(bitPattern: sample)) }
        return data
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF)); append(UInt8((value >> 8) & 0xFF))
    }
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF)); append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF)); append(UInt8((value >> 24) & 0xFF))
    }
}
