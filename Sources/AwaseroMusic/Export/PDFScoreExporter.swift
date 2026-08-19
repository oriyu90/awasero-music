import AppKit
import Foundation

enum PDFScoreExporter {
    @MainActor
    static func write(score: ScoreDocument, title: String, to url: URL) throws {
        guard !score.notes.isEmpty else { throw ExportError.emptyScore }
        let page = NSRect(x: 0, y: 0, width: 842, height: 595)
        let view = PrintableScoreView(frame: page, score: score, title: title)
        let data = view.dataWithPDF(inside: page)
        try data.write(to: url, options: .atomic)
    }
}

private final class PrintableScoreView: NSView {
    let score: ScoreDocument
    let title: String

    init(frame: NSRect, score: ScoreDocument, title: String) {
        self.score = score
        self.title = title
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 24), .foregroundColor: NSColor.black]
        title.draw(at: NSPoint(x: 48, y: bounds.height - 54), withAttributes: titleAttributes)
        let keyName = score.selectedKey?.name ?? "調未推定"
        let info = "♩ = \(Int(score.bpm.rounded()))    \(score.timeSignature.numerator)/\(score.timeSignature.denominator)    \(keyName)"
        info.draw(at: NSPoint(x: 50, y: bounds.height - 82), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])

        let fifths = score.selectedKey?.fifths ?? 0
        let accidentalAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.black]
        let totalBeats = max(4, score.notes.map { $0.startBeat + $0.durationBeats }.max() ?? 4)
        let systems = max(1, Int(ceil(totalBeats / 16)))
        for system in 0..<systems {
            let top = bounds.height - 125 - CGFloat(system) * 105
            guard top > 60 else { break }
            NSColor.black.setStroke()
            for line in 0..<5 {
                let y = top - CGFloat(line) * 10
                let path = NSBezierPath(); path.move(to: NSPoint(x: 50, y: y)); path.line(to: NSPoint(x: 792, y: y)); path.stroke()
            }
            let systemStart = Double(system) * 16
            for note in score.notes where note.startBeat >= systemStart && note.startBeat < systemStart + 16 {
                let x = 60 + CGFloat((note.startBeat - systemStart) / 16) * 720
                let y = top - 40 + CGFloat(note.midiNote - 60) * 2.5
                let spelling = MusicTheory.spelledPitch(midiNote: note.midiNote, fifths: fifths)
                if spelling.alter != 0 {
                    let accidental = spelling.alter > 0 ? "♯" : "♭"
                    accidental.draw(at: NSPoint(x: x - 12, y: y - 3), withAttributes: accidentalAttributes)
                }
                let oval = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 12, height: 8))
                NSColor.black.setFill(); oval.fill()
                let stem = NSBezierPath(); stem.move(to: NSPoint(x: x + 11, y: y + 4)); stem.line(to: NSPoint(x: x + 11, y: y + 35)); stem.stroke()
            }
        }
    }
}
