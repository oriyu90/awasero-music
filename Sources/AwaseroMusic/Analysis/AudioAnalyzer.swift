@preconcurrency import AVFoundation
import Foundation

enum AudioAnalysisError: LocalizedError {
    case unreadableAudio
    case noVoicedAudio

    var errorDescription: String? {
        switch self {
        case .unreadableAudio: "音声ファイルを読み込めませんでした。"
        case .noVoicedAudio: "安定した鼻歌の音程を検出できませんでした。入力音量を確認して録り直してください。"
        }
    }
}

enum AudioAnalyzer {
    static func analyze(url: URL, expectedBPM: Double = 120) throws -> AnalysisResult {
        let (samples, sampleRate) = try loadMonoSamples(url: url)
        let frameSize = 2048
        let hopSize = 512
        guard samples.count >= frameSize else { throw AudioAnalysisError.unreadableAudio }

        var frames: [PitchFrame] = []
        var offset = 0
        while offset + frameSize <= samples.count {
            if frames.count % 200 == 0 { try Task.checkCancellation() }
            let frame = Array(samples[offset..<(offset + frameSize)])
            let rms = sqrt(frame.reduce(0.0) { $0 + Double($1 * $1) } / Double(frameSize))
            let result = rms > 0.008 ? estimatePitch(frame, sampleRate: sampleRate) : nil
            frames.append(PitchFrame(
                time: Double(offset) / sampleRate,
                frequency: result?.frequency ?? 0,
                confidence: result?.confidence ?? 0,
                rms: rms
            ))
            offset += hopSize
        }

        let voiced = frames.filter { $0.frequency > 0 && $0.confidence >= 0.45 }
        guard !voiced.isEmpty else { throw AudioAnalysisError.noVoicedAudio }
        let keys = MusicTheory.inferKeys(frames: frames)
        let bpm = estimateTempo(frames: frames, fallback: expectedBPM)
        let notes = segmentNotes(frames: frames, bpm: bpm, offsetCents: keys.first?.globalPitchOffsetCents ?? 0)
        guard !notes.isEmpty else { throw AudioAnalysisError.noVoicedAudio }
        let chords = MusicTheory.suggestChords(notes: notes, key: keys.first)
        return AnalysisResult(
            pitchFrames: frames,
            detectedNotes: notes,
            keyCandidates: Array(keys.prefix(5)),
            estimatedBPM: bpm,
            chords: chords
        )
    }

    static func loadMonoSamples(url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let inputCapacity = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: inputCapacity) else {
            throw AudioAnalysisError.unreadableAudio
        }
        try file.read(into: inputBuffer)
        guard let channelData = inputBuffer.floatChannelData else { throw AudioAnalysisError.unreadableAudio }
        let frameCount = Int(inputBuffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = Array(repeating: Float(0), count: frameCount)
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for index in 0..<frameCount { mono[index] += samples[index] / Float(channelCount) }
        }
        return (mono, format.sampleRate)
    }

    static func estimatePitch(_ frame: [Float], sampleRate: Double) -> (frequency: Double, confidence: Double)? {
        let mean = frame.reduce(0, +) / Float(frame.count)
        let centered = frame.map { Double($0 - mean) }
        let minLag = max(2, Int(sampleRate / 1000))
        let maxLag = min(frame.count / 2, Int(sampleRate / 65))
        guard maxLag > minLag else { return nil }

        func normalizedCorrelation(at lag: Int) -> Double {
            var numerator = 0.0
            var energyA = 0.0
            var energyB = 0.0
            let count = centered.count - lag
            for index in 0..<count {
                let a = centered[index]
                let b = centered[index + lag]
                numerator += a * b
                energyA += a * a
                energyB += b * b
            }
            return numerator / max(sqrt(energyA * energyB), 0.000_001)
        }

        // Coarse pass: sample lags at a stride to cheaply find the peak's neighborhood, then
        // exhaustively re-scan just that neighborhood. Cuts evaluated lags roughly 4x versus a
        // full linear scan while keeping the same peak (autocorrelation peaks around the true
        // pitch period are broad, not needle-thin, so a stride of 4 samples doesn't skip them).
        let coarseStride = 4
        var coarseBestLag = minLag
        var coarseBestCorrelation = -Double.infinity
        var lag = minLag
        while lag <= maxLag {
            let value = normalizedCorrelation(at: lag)
            if value > coarseBestCorrelation { coarseBestCorrelation = value; coarseBestLag = lag }
            lag += coarseStride
        }

        let fineStart = max(minLag, coarseBestLag - coarseStride)
        let fineEnd = min(maxLag, coarseBestLag + coarseStride)
        var bestLag = coarseBestLag
        var bestCorrelation = coarseBestCorrelation
        if fineEnd > fineStart {
            for candidate in fineStart...fineEnd where candidate != coarseBestLag {
                let value = normalizedCorrelation(at: candidate)
                if value > bestCorrelation { bestCorrelation = value; bestLag = candidate }
            }
        }
        guard bestLag > 0, bestCorrelation >= 0.35 else { return nil }

        var refinedLag = Double(bestLag)
        if bestLag > minLag && bestLag < maxLag {
            func rawCorrelation(at lag: Int) -> Double {
                var sum = 0.0
                for index in 0..<(centered.count - lag) { sum += centered[index] * centered[index + lag] }
                return sum
            }
            let left = rawCorrelation(at: bestLag - 1)
            let center = rawCorrelation(at: bestLag)
            let right = rawCorrelation(at: bestLag + 1)
            let denominator = left - 2 * center + right
            if abs(denominator) > 0.000_001 { refinedLag += 0.5 * (left - right) / denominator }
        }
        return (sampleRate / refinedLag, min(1, bestCorrelation))
    }

    static func estimateTempo(frames: [PitchFrame], fallback: Double) -> Double {
        let onsets = frames.indices.dropFirst().compactMap { index -> Double? in
            let current = frames[index]
            let previous = frames[index - 1]
            let startsVoiced = current.confidence >= 0.45 && previous.confidence < 0.3
            let energyJump = current.rms > previous.rms * 1.8 && current.rms > 0.015
            return startsVoiced || energyJump ? current.time : nil
        }
        let allIntervals: [Double] = zip(onsets, onsets.dropFirst()).map { pair in
            abs(pair.1 - pair.0)
        }
        let intervals = allIntervals.filter { interval in
            interval >= 0.2 && interval <= 2
        }
        guard intervals.count >= 2 else { return fallback }
        let median = intervals.sorted()[intervals.count / 2]
        var bpm = 60 / median
        while bpm < 70 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        return (bpm * 10).rounded() / 10
    }

    static func segmentNotes(frames: [PitchFrame], bpm: Double, offsetCents: Double) -> [NoteEvent] {
        let voiced = frames.map { frame -> Int? in
            guard frame.confidence >= 0.45, frame.frequency > 0 else { return nil }
            return Int(MusicTheory.midiNote(frequency: frame.frequency, offsetCents: offsetCents).rounded())
        }
        guard frames.count > 1 else { return [] }
        let hopSeconds = frames[1].time - frames[0].time
        let beatSeconds = 60 / max(30, bpm)
        let quantum = 0.25
        var output: [NoteEvent] = []
        var startIndex: Int?
        var currentNote: Int?

        func appendNote(start: Int, end: Int, midi: Int) {
            guard end > start else { return }
            let rawStart = frames[start].time / beatSeconds
            let rawDuration = Double(end - start) * hopSeconds / beatSeconds
            let startBeat = (rawStart / quantum).rounded() * quantum
            let duration = max(quantum, (rawDuration / quantum).rounded() * quantum)
            let confidences = frames[start..<end].map(\.confidence)
            output.append(NoteEvent(
                startBeat: startBeat,
                durationBeats: duration,
                midiNote: max(0, min(127, midi)),
                confidence: confidences.reduce(0, +) / Double(max(1, confidences.count))
            ))
        }

        for index in voiced.indices {
            let note = voiced[index]
            if note == currentNote { continue }
            if let startIndex, let currentNote { appendNote(start: startIndex, end: index, midi: currentNote) }
            startIndex = note == nil ? nil : index
            currentNote = note
        }
        if let startIndex, let currentNote { appendNote(start: startIndex, end: voiced.count, midi: currentNote) }

        return output.reduce(into: []) { result, note in
            if var previous = result.last,
               previous.midiNote == note.midiNote,
               note.startBeat - (previous.startBeat + previous.durationBeats) <= quantum {
                previous.durationBeats = max(previous.durationBeats, note.startBeat + note.durationBeats - previous.startBeat)
                result[result.count - 1] = previous
            } else {
                result.append(note)
            }
        }
    }
}
