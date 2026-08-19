import Foundation

enum MusicXMLExporter {
    static func string(for score: ScoreDocument, title: String) throws -> String {
        guard !score.notes.isEmpty else { throw ExportError.emptyScore }
        let divisions = 4
        let beatsPerMeasure = Double(score.timeSignature.numerator)
        let fifths = score.selectedKey?.fifths ?? 0
        let measures = Dictionary(grouping: score.notes) { Int($0.startBeat / beatsPerMeasure) }
        let noteMaxMeasure = measures.keys.max() ?? 0
        let chordMaxMeasure = score.chords.map { Int($0.startBeat / beatsPerMeasure) }.max() ?? 0
        let maxMeasure = max(noteMaxMeasure, chordMaxMeasure)
        let escapedTitle = escape(title)

        let tempoEvents = score.tempoEvents.isEmpty ? [TempoEvent(beat: 0, bpm: score.bpm)] : score.tempoEvents.sorted { $0.beat < $1.beat }
        let tempoByMeasure = Dictionary(grouping: tempoEvents) { Int($0.beat / beatsPerMeasure) }
        let chordByMeasure = Dictionary(grouping: score.chords) { Int($0.startBeat / beatsPerMeasure) }.compactMapValues(\.first)

        var body = ""
        for measureIndex in 0...maxMeasure {
            body += "    <measure number=\"\(measureIndex + 1)\">\n"
            if measureIndex == 0 {
                body += """
                      <attributes>
                        <divisions>\(divisions)</divisions>
                        <key><fifths>\(fifths)</fifths></key>
                        <time><beats>\(score.timeSignature.numerator)</beats><beat-type>\(score.timeSignature.denominator)</beat-type></time>
                        <clef><sign>G</sign><line>2</line></clef>
                      </attributes>

                """
            }
            for tempoEvent in tempoByMeasure[measureIndex] ?? [] {
                body += "      <direction placement=\"above\"><sound tempo=\"\(Int(tempoEvent.bpm.rounded()))\"/></direction>\n"
            }
            if let chord = chordByMeasure[measureIndex] {
                body += harmonyElement(for: chord, fifths: fifths)
            }
            for note in (measures[measureIndex] ?? []).sorted(by: { $0.startBeat < $1.startBeat }) {
                let spelling = MusicTheory.spelledPitch(midiNote: note.midiNote, fifths: fifths)
                let alter = spelling.alter == 0 ? "" : "<alter>\(spelling.alter)</alter>"
                let duration = max(1, Int((note.durationBeats * Double(divisions)).rounded()))
                body += """
                      <note>
                        <pitch><step>\(spelling.step)</step>\(alter)<octave>\(spelling.octave)</octave></pitch>
                        <duration>\(duration)</duration><voice>1</voice>
                      </note>

                """
            }
            body += "    </measure>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0">
          <work><work-title>\(escapedTitle)</work-title></work>
          <part-list><score-part id="P1"><part-name>Melody</part-name></score-part></part-list>
          <part id="P1">
        \(body)  </part>
        </score-partwise>
        """
    }

    static func write(score: ScoreDocument, title: String, to url: URL) throws {
        try string(for: score, title: title).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func harmonyElement(for chord: ChordSuggestion, fifths: Int) -> String {
        let spelling = MusicTheory.spelledPitch(midiNote: chord.rootPitchClass, fifths: fifths)
        let alter = spelling.alter == 0 ? "" : "<root-alter>\(spelling.alter)</root-alter>"
        let symbol = chord.symbol
        let kind: String
        if symbol.hasSuffix("dim") { kind = "diminished" }
        else if symbol.hasSuffix("m") { kind = "minor" }
        else { kind = "major" }
        return """
              <harmony>
                <root><root-step>\(spelling.step)</root-step>\(alter)</root>
                <kind text="\(escape(symbol))">\(kind)</kind>
              </harmony>

        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
