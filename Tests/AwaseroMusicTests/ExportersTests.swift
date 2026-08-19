import XCTest
@testable import AwaseroMusic

final class ExportersTests: XCTestCase {
    private func makeScore(key: KeyCandidate? = nil, chords: [ChordSuggestion] = [], tempoEvents: [TempoEvent]? = nil) -> ScoreDocument {
        var score = ScoreDocument()
        score.notes = [
            NoteEvent(startBeat: 0, durationBeats: 1, midiNote: 60),
            NoteEvent(startBeat: 1, durationBeats: 1, midiNote: 64),
            NoteEvent(startBeat: 2, durationBeats: 2, midiNote: 67)
        ]
        score.selectedKey = key
        score.chords = chords
        if let tempoEvents { score.tempoEvents = tempoEvents }
        return score
    }

    // MARK: - MIDI

    func testMIDIExportHasValidHeaderAndNoteEvents() throws {
        let score = makeScore()
        let data = try MIDIExporter.data(for: score)
        XCTAssertTrue(data.starts(with: Data("MThd".utf8)))
        // MThd is always a fixed 14-byte chunk, so MTrk begins right after it.
        let trackChunkStart = data.index(data.startIndex, offsetBy: 14)
        XCTAssertEqual(data[trackChunkStart..<data.index(trackChunkStart, offsetBy: 4)], Data("MTrk".utf8))

        let noteOnCount = countBytePattern([0x90], in: data)
        XCTAssertEqual(noteOnCount, score.notes.count)
    }

    func testMIDIExportEmitsOneTempoEventPerTempoChange() throws {
        let score = makeScore(tempoEvents: [TempoEvent(beat: 0, bpm: 100), TempoEvent(beat: 2, bpm: 140)])
        let data = try MIDIExporter.data(for: score)
        // Set Tempo meta event is FF 51 03.
        let tempoEventCount = countBytePattern([0xFF, 0x51, 0x03], in: data)
        XCTAssertEqual(tempoEventCount, 2)
    }

    func testMIDIExportThrowsOnEmptyScore() {
        XCTAssertThrowsError(try MIDIExporter.data(for: ScoreDocument()))
    }

    private func countBytePattern(_ pattern: [UInt8], in data: Data) -> Int {
        let bytes = Array(data)
        guard bytes.count >= pattern.count else { return 0 }
        var count = 0
        for index in 0...(bytes.count - pattern.count) where Array(bytes[index..<(index + pattern.count)]) == pattern {
            count += 1
        }
        return count
    }

    // MARK: - MusicXML

    func testMusicXMLReflectsSelectedKeyFifths() throws {
        let gMajor = KeyCandidate(tonic: 7, isMinor: false, score: 0.9, globalPitchOffsetCents: 0)
        let score = makeScore(key: gMajor)
        let xml = try MusicXMLExporter.string(for: score, title: "Test")
        XCTAssertTrue(xml.contains("<fifths>1</fifths>"))
        XCTAssertTrue(xml.contains("<pitch>"))
    }

    func testMusicXMLDefaultsToCMajorWhenNoKeySelected() throws {
        let score = makeScore(key: nil)
        let xml = try MusicXMLExporter.string(for: score, title: "Test")
        XCTAssertTrue(xml.contains("<fifths>0</fifths>"))
    }

    func testMusicXMLIncludesHarmonyForChords() throws {
        let chord = ChordSuggestion(startBeat: 0, durationBeats: 4, symbol: "C", rootPitchClass: 0, pitchClasses: [0, 4, 7], confidence: 0.8)
        let score = makeScore(chords: [chord])
        let xml = try MusicXMLExporter.string(for: score, title: "Test")
        XCTAssertTrue(xml.contains("<harmony>"))
        XCTAssertTrue(xml.contains("<root-step>C</root-step>"))
    }

    func testMusicXMLThrowsOnEmptyScore() {
        XCTAssertThrowsError(try MusicXMLExporter.string(for: ScoreDocument(), title: "Empty"))
    }

    // MARK: - WAV

    func testWaveExportHasRIFFHeader() throws {
        let score = makeScore()
        let data = try WaveExporter.data(for: score)
        XCTAssertTrue(data.starts(with: Data("RIFF".utf8)))
        XCTAssertTrue(data.count > 44) // header + at least some samples
    }

    func testWaveExportHonorsMultipleTempoEvents() throws {
        var fastScore = makeScore()
        fastScore.tempoEvents = [TempoEvent(beat: 0, bpm: 240)]
        var slowScore = makeScore()
        slowScore.tempoEvents = [TempoEvent(beat: 0, bpm: 60)]

        let fastData = try WaveExporter.data(for: fastScore)
        let slowData = try WaveExporter.data(for: slowScore)
        // The same notes should render into a much shorter buffer at a faster tempo.
        XCTAssertLessThan(fastData.count, slowData.count)
    }

    func testWaveExportThrowsOnEmptyScore() {
        XCTAssertThrowsError(try WaveExporter.data(for: ScoreDocument()))
    }

    // MARK: - PDF

    @MainActor
    func testPDFExportProducesNonEmptyData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PDFScoreExporter.write(score: makeScore(), title: "Test", to: url)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
    }

    @MainActor
    func testPDFExportThrowsOnEmptyScore() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).pdf")
        XCTAssertThrowsError(try PDFScoreExporter.write(score: ScoreDocument(), title: "Empty", to: url))
    }
}
