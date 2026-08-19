import Foundation

enum ExportError: LocalizedError {
    case emptyScore

    var errorDescription: String? { "書き出す音符がありません。" }
}

enum MIDIExporter {
    static let ticksPerQuarter = 480

    static func data(for score: ScoreDocument) throws -> Data {
        guard !score.notes.isEmpty else { throw ExportError.emptyScore }
        struct Event {
            var tick: Int
            var priority: Int
            var bytes: [UInt8]
        }
        var events: [Event] = []
        let tempoEvents = score.tempoEvents.isEmpty ? [TempoEvent(beat: 0, bpm: score.bpm)] : score.tempoEvents.sorted { $0.beat < $1.beat }
        for tempoEvent in tempoEvents {
            let tick = max(0, Int((tempoEvent.beat * Double(ticksPerQuarter)).rounded()))
            let micros = Int(60_000_000 / max(1, tempoEvent.bpm))
            events.append(Event(tick: tick, priority: 0, bytes: [0xFF, 0x51, 0x03, UInt8((micros >> 16) & 0xFF), UInt8((micros >> 8) & 0xFF), UInt8(micros & 0xFF)]))
        }
        let denominatorPower = UInt8(log2(Double(max(1, score.timeSignature.denominator))).rounded())
        events.append(Event(tick: 0, priority: 0, bytes: [0xFF, 0x58, 0x04, UInt8(score.timeSignature.numerator), denominatorPower, 24, 8]))

        for chord in score.chords {
            let tick = max(0, Int((chord.startBeat * Double(ticksPerQuarter)).rounded()))
            let symbolBytes = Array(chord.symbol.utf8)
            events.append(Event(tick: tick, priority: 0, bytes: [0xFF, 0x06, UInt8(min(127, symbolBytes.count))] + symbolBytes.prefix(127)))
        }

        for note in score.notes {
            let start = max(0, Int((note.startBeat * Double(ticksPerQuarter)).rounded()))
            let end = max(start + 1, Int(((note.startBeat + note.durationBeats) * Double(ticksPerQuarter)).rounded()))
            let pitch = UInt8(max(0, min(127, note.midiNote)))
            let velocity = UInt8(max(1, min(127, note.velocity)))
            events.append(Event(tick: start, priority: 1, bytes: [0x90, pitch, velocity]))
            events.append(Event(tick: end, priority: 0, bytes: [0x80, pitch, 0]))
        }
        events.sort { $0.tick == $1.tick ? $0.priority < $1.priority : $0.tick < $1.tick }

        var track = Data()
        var previousTick = 0
        for event in events {
            track.append(contentsOf: variableLength(event.tick - previousTick))
            track.append(contentsOf: event.bytes)
            previousTick = event.tick
        }
        track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])

        var result = Data("MThd".utf8)
        result.appendBE(UInt32(6))
        result.appendBE(UInt16(0))
        result.appendBE(UInt16(1))
        result.appendBE(UInt16(ticksPerQuarter))
        result.append(Data("MTrk".utf8))
        result.appendBE(UInt32(track.count))
        result.append(track)
        return result
    }

    static func write(score: ScoreDocument, to url: URL) throws {
        try data(for: score).write(to: url, options: .atomic)
    }

    private static func variableLength(_ value: Int) -> [UInt8] {
        var value = max(0, value)
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8((value & 0x7F) | 0x80), at: 0)
            value >>= 7
        }
        return bytes
    }
}

private extension Data {
    mutating func appendBE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF)); append(UInt8(value & 0xFF))
    }

    mutating func appendBE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF)); append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF)); append(UInt8(value & 0xFF))
    }
}
