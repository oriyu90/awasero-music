import Foundation

enum CoreSelfCheck {
    static func run() -> Bool {
        var failures: [String] = []
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
            do {
                if try !condition() { failures.append(name) }
            } catch {
                failures.append("\(name): \(error.localizedDescription)")
            }
        }

        check(abs(MusicTheory.midiNote(frequency: 440) - 69) < 0.0001, "440Hz → A4")
        check(abs(MusicTheory.frequency(midiNote: 69) - 440) < 0.0001, "A4 → 440Hz")

        let frames = [60, 64, 67, 72].flatMap { note in
            Array(repeating: PitchFrame(
                time: 0,
                frequency: MusicTheory.frequency(midiNote: Double(note)),
                confidence: 0.95,
                rms: 0.3
            ), count: note == 60 ? 10 : 4)
        }
        let keys = MusicTheory.inferKeys(frames: frames)
        check(keys.prefix(5).contains { $0.tonic == 0 && !$0.isMinor }, "C major調推定")

        var score = ScoreDocument()
        score.notes = [
            NoteEvent(startBeat: 0, durationBeats: 1, midiNote: 60),
            NoteEvent(startBeat: 1, durationBeats: 1, midiNote: 64),
            NoteEvent(startBeat: 2, durationBeats: 2, midiNote: 67)
        ]
        let key = KeyCandidate(tonic: 0, isMinor: false, score: 1, globalPitchOffsetCents: 0)
        let chords = MusicTheory.suggestChords(notes: score.notes, key: key)
        check(chords.first?.symbol == "C", "C majorコード推定")
        check((try? MIDIExporter.data(for: score).starts(with: Data("MThd".utf8))) == true, "MIDI出力")
        check((try? MusicXMLExporter.string(for: score, title: "Check").contains("<score-partwise")) == true, "MusicXML出力")
        check((try? WaveExporter.data(for: score).starts(with: Data("RIFF".utf8))) == true, "WAV出力")

        if failures.isEmpty {
            print("Self-check passed: 7 checks")
            return true
        }
        print("Self-check failed: \(failures.joined(separator: ", "))")
        return false
    }
}
