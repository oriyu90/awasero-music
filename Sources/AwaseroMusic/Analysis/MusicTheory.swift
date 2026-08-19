import Foundation

enum MusicTheory {
    static let majorScale = [0, 2, 4, 5, 7, 9, 11]
    static let minorScale = [0, 2, 3, 5, 7, 8, 10]
    static let pitchClassNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    static func midiNote(frequency: Double, offsetCents: Double = 0) -> Double {
        guard frequency > 0 else { return 0 }
        return 69 + 12 * log2(frequency / 440) - offsetCents / 100
    }

    static func frequency(midiNote: Double) -> Double {
        440 * pow(2, (midiNote - 69) / 12)
    }

    /// Offsets searched per key candidate (cents), evaluated against a scale-fit + stable-tone + terminal-note score.
    private static let offsetSearchRangeCents: [Double] = stride(from: -50.0, through: 50.0, by: 10.0).map { $0 }

    private struct OffsetProfile {
        var histogram: [Double]
        var stability: [Double]
        var terminalPitchClass: Int
        /// Weighted-average distance (in semitones, 0...0.5) between each frame and the nearest
        /// semitone once this offset is applied. Two offsets can bucket every frame into the same
        /// pitch classes yet fit with very different precision; without this term the search below
        /// cannot tell them apart and just keeps the first tied offset it sees.
        var meanAbsResidual: Double
    }

    private static func offsetProfile(offsetCents: Double, valid: [PitchFrame], rawNotes: [Double]) -> OffsetProfile {
        var histogram = Array(repeating: 0.0, count: 12)
        var stability = Array(repeating: 0.0, count: 12)
        var roundedClasses: [Int] = []
        roundedClasses.reserveCapacity(valid.count)
        var weightedResidual = 0.0
        var weightTotal = 0.0
        for (frame, raw) in zip(valid, rawNotes) {
            let shifted = raw - offsetCents / 100
            let rounded = shifted.rounded()
            let pitchClass = (Int(rounded) % 12 + 12) % 12
            let weight = max(0.05, frame.rms) * frame.confidence
            histogram[pitchClass] += weight
            roundedClasses.append(pitchClass)
            weightedResidual += abs(shifted - rounded) * weight
            weightTotal += weight
        }
        // Stable tones (long runs of the same rounded pitch class) count more than fleeting ones.
        var runLength = 1
        for index in 1..<roundedClasses.count {
            if roundedClasses[index] == roundedClasses[index - 1] {
                runLength += 1
            } else {
                stability[roundedClasses[index - 1]] += Double(runLength * runLength)
                runLength = 1
            }
        }
        if let last = roundedClasses.last { stability[last] += Double(runLength * runLength) }
        return OffsetProfile(
            histogram: histogram,
            stability: stability,
            terminalPitchClass: roundedClasses.last ?? 0,
            meanAbsResidual: weightTotal > 0 ? weightedResidual / weightTotal : 0
        )
    }

    static func inferKeys(frames: [PitchFrame]) -> [KeyCandidate] {
        let valid = frames.filter { $0.confidence >= 0.45 && $0.frequency > 0 }
        guard !valid.isEmpty else { return [] }
        let rawNotes = valid.map { midiNote(frequency: $0.frequency) }

        // Precompute one profile per candidate offset; every (tonic, mode) pair searches across
        // these to find its own best-fitting global pitch offset, rather than sharing one value.
        let profiles = offsetSearchRangeCents.map { offset in
            (offset: offset, profile: offsetProfile(offsetCents: offset, valid: valid, rawNotes: rawNotes))
        }

        var candidates: [KeyCandidate] = []
        for tonic in 0..<12 {
            for isMinor in [false, true] {
                let scale = isMinor ? minorScale : majorScale
                let allowed = Set(scale.map { ($0 + tonic) % 12 })
                let fifthPitchClass = (tonic + 7) % 12
                var bestScore = -Double.infinity
                var bestOffset = 0.0
                for entry in profiles {
                    let histogram = entry.profile.histogram
                    let total = max(histogram.reduce(0, +), 0.0001)
                    var score = 0.0
                    for pitchClass in 0..<12 {
                        let weight = allowed.contains(pitchClass) ? 1.0 : -0.7
                        score += histogram[pitchClass] * weight
                    }
                    score += histogram[tonic] * 0.35
                    score /= total

                    let stabilityTotal = max(entry.profile.stability.reduce(0, +), 0.0001)
                    score += (entry.profile.stability[tonic] / stabilityTotal) * 0.15

                    if entry.profile.terminalPitchClass == tonic {
                        score += 0.12
                    } else if entry.profile.terminalPitchClass == fifthPitchClass {
                        score += 0.05
                    }

                    // Prefer the offset that lands closest to exact semitones among otherwise-tied offsets.
                    score -= entry.profile.meanAbsResidual * 0.4

                    if score > bestScore {
                        bestScore = score
                        bestOffset = entry.offset
                    }
                }
                candidates.append(KeyCandidate(
                    tonic: tonic,
                    isMinor: isMinor,
                    score: max(0, min(1, (bestScore + 0.7) / 1.97)),
                    globalPitchOffsetCents: bestOffset
                ))
            }
        }
        return candidates.sorted { $0.score > $1.score }
    }

    /// Circle-of-fifths signature (-7...7) for a key, used for MusicXML/PDF key signatures and note spelling.
    static func fifths(tonic: Int, isMinor: Bool) -> Int {
        let majorFifthsByPitchClass = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5]
        let relativeMajorTonic = isMinor ? (tonic + 3) % 12 : tonic
        return majorFifthsByPitchClass[(relativeMajorTonic % 12 + 12) % 12]
    }

    /// A simplified (non-diatonic-aware) enharmonic spelling: sharp-preferring for fifths >= 0, flat-preferring otherwise.
    static func spelledPitch(midiNote: Int, fifths: Int) -> (step: String, alter: Int, octave: Int) {
        let sharpTable: [(String, Int)] = [("C", 0), ("C", 1), ("D", 0), ("D", 1), ("E", 0), ("F", 0), ("F", 1), ("G", 0), ("G", 1), ("A", 0), ("A", 1), ("B", 0)]
        let flatTable: [(String, Int)] = [("C", 0), ("D", -1), ("D", 0), ("E", -1), ("E", 0), ("F", 0), ("G", -1), ("G", 0), ("A", -1), ("A", 0), ("B", -1), ("B", 0)]
        let note = max(0, min(127, midiNote))
        let pitchClass = note % 12
        let table = fifths >= 0 ? sharpTable : flatTable
        let (step, alter) = table[pitchClass]
        return (step, alter, note / 12 - 1)
    }

    static func suggestChords(notes: [NoteEvent], key: KeyCandidate?, beatsPerBar: Double = 4) -> [ChordSuggestion] {
        guard !notes.isEmpty else { return [] }
        let finalBeat = notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
        let barCount = max(1, Int(ceil(finalBeat / beatsPerBar)))
        let tonic = key?.tonic ?? 0
        let scale = key?.isMinor == true ? minorScale : majorScale
        let qualities = key?.isMinor == true
            ? ["m", "dim", "", "m", "m", "", ""]
            : ["", "m", "m", "", "", "m", "dim"]

        return (0..<barCount).map { bar in
            let start = Double(bar) * beatsPerBar
            let end = start + beatsPerBar
            let barNotes = notes.filter { $0.startBeat < end && $0.startBeat + $0.durationBeats > start }
            var bestDegree = 0
            var bestScore = -Double.infinity
            for degree in 0..<7 {
                let root = (tonic + scale[degree]) % 12
                let third = (tonic + scale[(degree + 2) % 7]) % 12
                let fifth = (tonic + scale[(degree + 4) % 7]) % 12
                let chordSet = Set([root, third, fifth])
                let score = barNotes.reduce(0.0) { partial, note in
                    let overlap = max(0, min(note.startBeat + note.durationBeats, end) - max(note.startBeat, start))
                    return partial + overlap * (chordSet.contains((note.midiNote % 12 + 12) % 12) ? 1 : -0.3)
                }
                if score > bestScore { bestScore = score; bestDegree = degree }
            }
            let root = (tonic + scale[bestDegree]) % 12
            let third = (tonic + scale[(bestDegree + 2) % 7]) % 12
            let fifth = (tonic + scale[(bestDegree + 4) % 7]) % 12
            return ChordSuggestion(
                startBeat: start,
                durationBeats: beatsPerBar,
                symbol: pitchClassNames[root] + qualities[bestDegree],
                rootPitchClass: root,
                pitchClasses: [root, third, fifth],
                confidence: max(0, min(1, 0.5 + bestScore / max(beatsPerBar * 2, 1)))
            )
        }
    }
}
