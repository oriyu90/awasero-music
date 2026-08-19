import Foundation

struct NoteEvent: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var startBeat: Double
    var durationBeats: Double
    var midiNote: Int
    var velocity: Int = 90
    var confidence: Double = 1

    var noteName: String {
        let note = max(0, min(127, midiNote))
        return "\(MusicTheory.pitchClassNames[note % 12])\(note / 12 - 1)"
    }
}

struct TempoEvent: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var beat: Double
    var bpm: Double
}

struct TimeSignature: Codable, Hashable, Sendable {
    var numerator = 4
    var denominator = 4
}

enum TimeSignaturePreset: String, CaseIterable, Identifiable, Hashable, Sendable {
    case three4, four4, six8

    var id: String { rawValue }

    var label: String {
        switch self {
        case .three4: "3/4"
        case .four4: "4/4"
        case .six8: "6/8"
        }
    }

    var numerator: Int {
        switch self {
        case .three4: 3
        case .four4: 4
        case .six8: 6
        }
    }

    var denominator: Int {
        switch self {
        case .three4: 4
        case .four4: 4
        case .six8: 8
        }
    }

    var timeSignature: TimeSignature { TimeSignature(numerator: numerator, denominator: denominator) }

    static func matching(_ timeSignature: TimeSignature) -> TimeSignaturePreset {
        allCases.first { $0.numerator == timeSignature.numerator && $0.denominator == timeSignature.denominator } ?? .four4
    }
}

struct KeyCandidate: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(tonic)-\(isMinor)" }
    var tonic: Int
    var isMinor: Bool
    var score: Double
    var globalPitchOffsetCents: Double

    var name: String {
        MusicTheory.pitchClassNames[(tonic % 12 + 12) % 12] + (isMinor ? " minor" : " major")
    }

    var fifths: Int { MusicTheory.fifths(tonic: tonic, isMinor: isMinor) }
}

struct PitchFrame: Codable, Hashable, Sendable {
    var time: Double
    var frequency: Double
    var confidence: Double
    var rms: Double
}

struct ChordSuggestion: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var startBeat: Double
    var durationBeats: Double
    var symbol: String
    var rootPitchClass: Int
    var pitchClasses: [Int]
    var confidence: Double
}

struct AnalysisResult: Codable, Sendable {
    var pitchFrames: [PitchFrame] = []
    var detectedNotes: [NoteEvent] = []
    var keyCandidates: [KeyCandidate] = []
    var estimatedBPM: Double = 120
    var chords: [ChordSuggestion] = []
}

struct ScoreDocument: Codable, Sendable {
    var tempoEvents: [TempoEvent] = [TempoEvent(beat: 0, bpm: 120)]
    var timeSignature = TimeSignature()
    var selectedKey: KeyCandidate?
    var notes: [NoteEvent] = []
    var chords: [ChordSuggestion] = []

    var bpm: Double {
        get { tempoEvents.first?.bpm ?? 120 }
        set {
            if tempoEvents.isEmpty { tempoEvents = [TempoEvent(beat: 0, bpm: newValue)] }
            else { tempoEvents[0].bpm = newValue }
        }
    }

    /// Converts a beat position to elapsed seconds, honoring every tempo change in `tempoEvents`.
    func seconds(atBeat beat: Double) -> Double {
        let events = tempoEvents.isEmpty ? [TempoEvent(beat: 0, bpm: bpm)] : tempoEvents.sorted { $0.beat < $1.beat }
        var elapsed = 0.0
        var previousBeat = 0.0
        var previousBPM = events[0].bpm
        for event in events {
            if event.beat >= beat {
                elapsed += max(0, beat - previousBeat) * 60 / max(1, previousBPM)
                return elapsed
            }
            elapsed += max(0, event.beat - previousBeat) * 60 / max(1, previousBPM)
            previousBeat = event.beat
            previousBPM = event.bpm
        }
        elapsed += max(0, beat - previousBeat) * 60 / max(1, previousBPM)
        return elapsed
    }
}

struct AwaseroProject: Identifiable, Codable, Sendable {
    static let formatVersion = 1

    var id = UUID()
    var name: String
    var createdAt = Date()
    var updatedAt = Date()
    var formatVersion = Self.formatVersion
    var audioFileName: String?
    var score = ScoreDocument()
    var analysis: AnalysisResult?
}

enum AnalysisStage: String, Sendable {
    case idle = "待機中"
    case loading = "音声を読み込んでいます"
    case pitch = "音程を解析しています"
    case notes = "音符へ変換しています"
    case key = "調を推定しています"
    case chords = "コードを推定しています"
    case complete = "解析完了"
}
