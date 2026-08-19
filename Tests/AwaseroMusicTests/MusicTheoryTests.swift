import XCTest
@testable import AwaseroMusic

final class MusicTheoryTests: XCTestCase {
    func testMidiFrequencyRoundTrip() {
        for midi in [40.0, 60.0, 69.0, 72.0, 96.0] {
            let frequency = MusicTheory.frequency(midiNote: midi)
            let back = MusicTheory.midiNote(frequency: frequency)
            XCTAssertEqual(back, midi, accuracy: 0.0001)
        }
        XCTAssertEqual(MusicTheory.midiNote(frequency: 440), 69, accuracy: 0.0001)
        XCTAssertEqual(MusicTheory.frequency(midiNote: 69), 440, accuracy: 0.0001)
    }

    private func syntheticFrames(notes: [Int], repeats: Int, offsetCents: Double, confidence: Double = 0.95, rms: Double = 0.3) -> [PitchFrame] {
        notes.flatMap { note in
            Array(repeating: PitchFrame(
                time: 0,
                frequency: MusicTheory.frequency(midiNote: Double(note) + offsetCents / 100),
                confidence: confidence,
                rms: rms
            ), count: repeats)
        }
    }

    func testInferKeysPicksCMajorForDiatonicMelody() {
        // C E G C, ending back on the tonic — should read as C major regardless of a global offset.
        let frames = syntheticFrames(notes: [60, 64, 67, 60], repeats: 8, offsetCents: 0)
        let keys = MusicTheory.inferKeys(frames: frames)
        XCTAssertFalse(keys.isEmpty)
        XCTAssertEqual(keys.first?.tonic, 0)
        XCTAssertEqual(keys.first?.isMinor, false)
    }

    func testInferKeysFindsTheBestFittingOffsetPerCandidate() {
        // Every frame is uniformly 30 cents sharp; the winning candidate's own offset search
        // should converge on +30 cents (the exact correction), not just any offset that happens
        // to round to the same pitch classes.
        let frames = syntheticFrames(notes: [60, 64, 67, 60], repeats: 8, offsetCents: 30)
        let keys = MusicTheory.inferKeys(frames: frames)
        guard let best = keys.first else { return XCTFail("expected at least one key candidate") }
        XCTAssertEqual(best.tonic, 0)
        XCTAssertEqual(best.isMinor, false)
        XCTAssertEqual(best.globalPitchOffsetCents, 30, accuracy: 0.01)
    }

    func testSuggestChordsBasicTriad() {
        let notes = [
            NoteEvent(startBeat: 0, durationBeats: 1, midiNote: 60),
            NoteEvent(startBeat: 1, durationBeats: 1, midiNote: 64),
            NoteEvent(startBeat: 2, durationBeats: 2, midiNote: 67)
        ]
        let key = KeyCandidate(tonic: 0, isMinor: false, score: 1, globalPitchOffsetCents: 0)
        let chords = MusicTheory.suggestChords(notes: notes, key: key)
        XCTAssertEqual(chords.first?.symbol, "C")
        XCTAssertEqual(chords.first?.pitchClasses.sorted(), [0, 4, 7])
    }

    func testSuggestChordsEmptyNotesReturnsEmpty() {
        XCTAssertTrue(MusicTheory.suggestChords(notes: [], key: nil).isEmpty)
    }

    func testFifthsForRepresentativeKeys() {
        XCTAssertEqual(MusicTheory.fifths(tonic: 0, isMinor: false), 0) // C major
        XCTAssertEqual(MusicTheory.fifths(tonic: 7, isMinor: false), 1) // G major
        XCTAssertEqual(MusicTheory.fifths(tonic: 5, isMinor: false), -1) // F major
        XCTAssertEqual(MusicTheory.fifths(tonic: 9, isMinor: true), 0) // A minor (relative of C major)
    }

    func testSpelledPitchSharpAndFlatPreference() {
        let gMajorFsharp = MusicTheory.spelledPitch(midiNote: 66, fifths: 1) // F# in G major
        XCTAssertEqual(gMajorFsharp.step, "F")
        XCTAssertEqual(gMajorFsharp.alter, 1)

        let fMajorBflat = MusicTheory.spelledPitch(midiNote: 70, fifths: -1) // Bb in F major
        XCTAssertEqual(fMajorBflat.step, "B")
        XCTAssertEqual(fMajorBflat.alter, -1)

        let middleC = MusicTheory.spelledPitch(midiNote: 60, fifths: 0)
        XCTAssertEqual(middleC.step, "C")
        XCTAssertEqual(middleC.alter, 0)
        XCTAssertEqual(middleC.octave, 4)
    }
}
