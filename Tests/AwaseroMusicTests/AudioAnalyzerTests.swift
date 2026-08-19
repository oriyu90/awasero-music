import AVFoundation
import XCTest
@testable import AwaseroMusic

final class AudioAnalyzerTests: XCTestCase {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).caf")
    }

    private func writeSyntheticAudio(segments: [(frequency: Double, duration: Double)], sampleRate: Double = 44100, amplitude: Double = 0.5, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        for segment in segments {
            let frameCount = AVAudioFrameCount(segment.duration * sampleRate)
            guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }
            buffer.frameLength = frameCount
            let channel = buffer.floatChannelData![0]
            for index in 0..<Int(frameCount) {
                let time = Double(index) / sampleRate
                channel[index] = Float(sin(2 * Double.pi * segment.frequency * time) * amplitude)
            }
            try file.write(from: buffer)
        }
    }

    func testEstimatePitchAccuracyWithinOnePercent() {
        let sampleRate = 44100.0
        let frequency = 220.0
        let frameSize = 2048
        var frame = [Float](repeating: 0, count: frameSize)
        for index in 0..<frameSize {
            frame[index] = Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.6)
        }
        guard let result = AudioAnalyzer.estimatePitch(frame, sampleRate: sampleRate) else {
            return XCTFail("expected a pitch estimate")
        }
        XCTAssertEqual(result.frequency, frequency, accuracy: frequency * 0.01)
    }

    func testSegmentNotesProducesDistinctNotesForDistinctPitches() {
        var frames: [PitchFrame] = []
        for index in 0..<20 {
            frames.append(PitchFrame(time: Double(index) * 0.01, frequency: MusicTheory.frequency(midiNote: 60), confidence: 0.9, rms: 0.3))
        }
        for index in 0..<20 {
            frames.append(PitchFrame(time: 0.2 + Double(index) * 0.01, frequency: MusicTheory.frequency(midiNote: 64), confidence: 0.9, rms: 0.3))
        }
        let notes = AudioAnalyzer.segmentNotes(frames: frames, bpm: 120, offsetCents: 0)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.map(\.midiNote), [60, 64])
    }

    func testEstimateTempoFromRegularOnsets() {
        var frames: [PitchFrame] = []
        // Onsets every 0.5s (=> 120 BPM), each a short voiced burst preceded by silence.
        for beatIndex in 0..<8 {
            let start = Double(beatIndex) * 0.5
            frames.append(PitchFrame(time: start - 0.01, frequency: 0, confidence: 0.1, rms: 0.01))
            frames.append(PitchFrame(time: start, frequency: 440, confidence: 0.9, rms: 0.3))
            frames.append(PitchFrame(time: start + 0.05, frequency: 440, confidence: 0.9, rms: 0.3))
        }
        let bpm = AudioAnalyzer.estimateTempo(frames: frames, fallback: 90)
        XCTAssertEqual(bpm, 120, accuracy: 5)
    }

    func testAnalyzeRoundTripOnSyntheticAudio() throws {
        let url = temporaryURL("analyze")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSyntheticAudio(segments: [(261.63, 1.0), (329.63, 1.0)], to: url)

        let result = try AudioAnalyzer.analyze(url: url, expectedBPM: 100)
        XCTAssertFalse(result.detectedNotes.isEmpty)
        XCTAssertFalse(result.keyCandidates.isEmpty)
        XCTAssertGreaterThan(result.pitchFrames.count, 0)
    }

    func testAnalyzeThrowsOnSilence() throws {
        let url = temporaryURL("silence")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSyntheticAudio(segments: [(440, 1.0)], amplitude: 0, to: url)

        XCTAssertThrowsError(try AudioAnalyzer.analyze(url: url)) { error in
            guard case AudioAnalysisError.noVoicedAudio = error else {
                return XCTFail("expected noVoicedAudio, got \(error)")
            }
        }
    }

    func testAnalyzeThrowsOnTooShortAudio() throws {
        let url = temporaryURL("tooshort")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSyntheticAudio(segments: [(440, 0.01)], to: url)

        XCTAssertThrowsError(try AudioAnalyzer.analyze(url: url)) { error in
            guard case AudioAnalysisError.unreadableAudio = error else {
                return XCTFail("expected unreadableAudio, got \(error)")
            }
        }
    }
}
