import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case projects = "プロジェクト"
        case record = "録音"
        case edit = "楽譜編集"
        case chords = "コード"
        case export = "書き出し"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .projects: "square.grid.2x2"
            case .record: "mic.fill"
            case .edit: "music.note.list"
            case .chords: "guitars.fill"
            case .export: "square.and.arrow.up"
            }
        }
    }

    @Published var selection: Section? = .projects
    @Published var analysisStage: AnalysisStage = .idle
    @Published var isAnalyzing = false
    @Published var selectedNoteID: UUID?
    @Published var selectedNoteIDs: Set<UUID> = []
    @Published var message: String?
    @Published var countInBars = 1
    @Published var hasManualEdits = false
    @Published var confirmDiscardMessage: String?
    @Published var recoveryAvailableURL: URL?
    @Published var projectSummaries: [ProjectSummary] = []

    var store = ProjectStore()
    var recorder = AudioRecorder()
    var metronome = Metronome()
    var scorePlayer = ScorePlayer()
    private var subscriptions = Set<AnyCancellable>()
    private var analysisTask: Task<Void, Never>?
    private var analysisComputeTask: Task<AnalysisResult, Error>?
    private var pendingAction: (() -> Void)?
    private var autoRecoveryURL: URL?
    private var autosaveTimer: Timer?

    init() {
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        recorder.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        metronome.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        scorePlayer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)

        refreshProjectList()
        checkForRecovery()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performAutosave() }
        }
    }

    var recordingURL: URL? {
        if let temporary = recorder.recordingURL { return temporary }
        guard let package = store.projectURL, let name = store.project.audioFileName else { return nil }
        return package.appendingPathComponent(name)
    }

    var canUndo: Bool { store.canUndo }
    var canRedo: Bool { store.canRedo }
    func undo() { store.undo() }
    func redo() { store.redo() }

    // MARK: - Recording

    func startRecording() {
        scorePlayer.stop()
        metronome.start()
        Task {
            if countInBars > 0 {
                let seconds = Double(countInBars * metronome.beatsPerBar) * 60 / metronome.bpm
                try? await Task.sleep(for: .seconds(seconds))
            }
            guard metronome.isRunning else { return }
            await recorder.startRecording()
        }
    }

    func stopRecording() {
        recorder.stopRecording()
        metronome.stop()
    }

    // MARK: - Analysis

    func analyzeRecording() {
        guard let url = recordingURL else {
            message = "先に鼻歌を録音してください。"
            return
        }
        isAnalyzing = true
        analysisStage = .loading
        message = nil
        let bpm = metronome.bpm
        analysisTask = Task { [weak self] in
            guard let self else { return }
            self.analysisStage = .pitch
            let compute = Task.detached(priority: .userInitiated) {
                try AudioAnalyzer.analyze(url: url, expectedBPM: bpm)
            }
            self.analysisComputeTask = compute
            do {
                let result = try await compute.value
                self.analysisStage = .key
                self.store.project.analysis = result
                self.store.project.score.notes = result.detectedNotes
                self.store.project.score.bpm = result.estimatedBPM
                self.store.project.score.selectedKey = result.keyCandidates.first
                self.store.project.score.chords = result.chords
                self.metronome.bpm = result.estimatedBPM
                self.analysisStage = .complete
                self.isAnalyzing = false
                self.hasManualEdits = false
                self.store.clearUndoHistory()
                self.selectedNoteIDs = []
                self.selectedNoteID = nil
                self.selection = .edit
            } catch is CancellationError {
                self.isAnalyzing = false
                self.analysisStage = .idle
                self.message = "解析をキャンセルしました。録音データは保持されています。"
            } catch {
                self.isAnalyzing = false
                self.analysisStage = .idle
                self.message = error.localizedDescription
            }
            self.analysisComputeTask = nil
            self.analysisTask = nil
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisComputeTask?.cancel()
    }

    func reanalyze() {
        requestConfirmation(message: "手動編集を破棄して再解析しますか？録音データ自体は保持されます。") { [weak self] in
            self?.analyzeRecording()
        }
    }

    // MARK: - Discard confirmation

    func requestConfirmation(message: String, action: @escaping () -> Void) {
        if hasManualEdits {
            confirmDiscardMessage = message
            pendingAction = action
        } else {
            action()
        }
    }

    func confirmPendingAction() {
        pendingAction?()
        pendingAction = nil
        confirmDiscardMessage = nil
    }

    func cancelPendingAction() {
        pendingAction = nil
        confirmDiscardMessage = nil
    }

    // MARK: - Key / chords

    func selectKey(_ key: KeyCandidate) {
        requestConfirmation(message: "調を切り替えると、手動で編集した音符やコードは解析結果で上書きされます。続けますか？") { [weak self] in
            self?.applyKeySelection(key)
        }
    }

    private func applyKeySelection(_ key: KeyCandidate) {
        store.pushUndoSnapshot()
        store.project.score.selectedKey = key
        if let analysis = store.project.analysis {
            store.project.score.notes = AudioAnalyzer.segmentNotes(
                frames: analysis.pitchFrames,
                bpm: store.project.score.bpm,
                offsetCents: key.globalPitchOffsetCents
            )
        }
        store.project.score.chords = MusicTheory.suggestChords(
            notes: store.project.score.notes,
            key: key,
            beatsPerBar: Double(store.project.score.timeSignature.numerator)
        )
        hasManualEdits = false
    }

    func regenerateChords() {
        store.pushUndoSnapshot()
        store.project.score.chords = MusicTheory.suggestChords(
            notes: store.project.score.notes,
            key: store.project.score.selectedKey,
            beatsPerBar: Double(store.project.score.timeSignature.numerator)
        )
        hasManualEdits = true
    }

    func updateChordSymbol(at index: Int, to rawValue: String) {
        guard store.project.score.chords.indices.contains(index) else { return }
        let sanitized = Self.sanitizeChordSymbol(rawValue)
        guard !sanitized.isEmpty else { return }
        store.pushUndoSnapshot()
        store.project.score.chords[index].symbol = sanitized
        hasManualEdits = true
    }

    private static func sanitizeChordSymbol(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "#♯♭/()+- "))
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return String(filtered.prefix(12))
    }

    // MARK: - Note editing

    func addNote() {
        store.pushUndoSnapshot()
        let end = store.project.score.notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
        let note = NoteEvent(startBeat: end, durationBeats: 1, midiNote: 60)
        store.project.score.notes.append(note)
        selectedNoteID = note.id
        selectedNoteIDs = [note.id]
        hasManualEdits = true
    }

    func deleteSelectedNotes() {
        guard !selectedNoteIDs.isEmpty else { return }
        store.pushUndoSnapshot()
        store.project.score.notes.removeAll { selectedNoteIDs.contains($0.id) }
        selectedNoteIDs = []
        selectedNoteID = nil
        hasManualEdits = true
    }

    /// Click-to-select in the piano roll / staff view. `extend` toggles membership (shift/cmd-click).
    func selectNote(_ id: UUID, extend: Bool) {
        if extend {
            if selectedNoteIDs.contains(id) { selectedNoteIDs.remove(id) } else { selectedNoteIDs.insert(id) }
        } else {
            selectedNoteIDs = [id]
        }
        selectedNoteID = id
    }

    /// Call before editing a field on the currently selected note(s), so the prior state becomes undoable.
    func beginNoteFieldEdit() {
        store.pushUndoSnapshot()
    }

    func noteFieldDidChange() {
        hasManualEdits = true
    }

    func applyVelocity(_ value: Int) {
        guard !selectedNoteIDs.isEmpty else { return }
        store.pushUndoSnapshot()
        for index in store.project.score.notes.indices where selectedNoteIDs.contains(store.project.score.notes[index].id) {
            store.project.score.notes[index].velocity = max(1, min(127, value))
        }
        hasManualEdits = true
    }

    func applyVelocityRamp(from startValue: Int, to endValue: Int) {
        let targets = store.project.score.notes.enumerated()
            .filter { selectedNoteIDs.contains($0.element.id) }
            .sorted { $0.element.startBeat < $1.element.startBeat }
        guard targets.count > 1 else {
            applyVelocity(startValue)
            return
        }
        store.pushUndoSnapshot()
        let step = Double(endValue - startValue) / Double(targets.count - 1)
        for (rank, entry) in targets.enumerated() {
            let value = Int((Double(startValue) + step * Double(rank)).rounded())
            store.project.score.notes[entry.offset].velocity = max(1, min(127, value))
        }
        hasManualEdits = true
    }

    // MARK: - Tempo map

    func addTempoEvent(beat: Double, bpm: Double) {
        store.pushUndoSnapshot()
        let clampedBeat = max(0, beat)
        let clampedBPM = max(20, min(300, bpm))
        store.project.score.tempoEvents.removeAll { abs($0.beat - clampedBeat) < 0.001 }
        store.project.score.tempoEvents.append(TempoEvent(beat: clampedBeat, bpm: clampedBPM))
        store.project.score.tempoEvents.sort { $0.beat < $1.beat }
        if store.project.score.tempoEvents.first?.beat != 0 {
            store.project.score.tempoEvents.insert(TempoEvent(beat: 0, bpm: store.project.score.tempoEvents.first?.bpm ?? 120), at: 0)
        }
        hasManualEdits = true
    }

    func removeTempoEvent(_ id: UUID) {
        guard store.project.score.tempoEvents.count > 1 else { return }
        store.pushUndoSnapshot()
        store.project.score.tempoEvents.removeAll { $0.id == id }
        if var first = store.project.score.tempoEvents.first, first.beat != 0 {
            first.beat = 0
            store.project.score.tempoEvents[0] = first
        }
        hasManualEdits = true
    }

    // MARK: - Project lifecycle

    func newProject() {
        stopRecording()
        scorePlayer.stop()
        cancelAnalysis()
        store.newProject()
        selectedNoteIDs = []
        selectedNoteID = nil
        hasManualEdits = false
        autoRecoveryURL = nil
        selection = .record
    }

    /// Saves in place if the project already lives somewhere; otherwise behaves like `saveAs()`.
    func quickSave() {
        if let url = store.projectURL {
            do {
                try store.ensureAudioIsPresent(atNewLocation: url, freshRecordingURL: recorder.recordingURL)
                try store.save(to: url)
                ProjectLibrary.clearAutoRecovery()
                autoRecoveryURL = nil
                refreshProjectList()
                message = "プロジェクトを保存しました。"
            } catch { message = error.localizedDescription }
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.title = "プロジェクトを保存"
        panel.directoryURL = ProjectLibrary.directory()
        panel.nameFieldStringValue = "\(store.project.name).hummingproject"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.ensureAudioIsPresent(atNewLocation: url, freshRecordingURL: recorder.recordingURL)
                try store.save(to: url)
                ProjectLibrary.clearAutoRecovery()
                autoRecoveryURL = nil
                refreshProjectList()
                message = "プロジェクトを保存しました。"
            } catch { message = error.localizedDescription }
        }
    }

    func openProjectFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "プロジェクトを開く"
        panel.directoryURL = ProjectLibrary.directory()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            openProjectFromLibrary(url)
        }
    }

    func openProjectFromLibrary(_ url: URL) {
        do {
            try store.load(from: url)
            metronome.bpm = store.project.score.bpm
            selectedNoteIDs = []
            selectedNoteID = nil
            hasManualEdits = false
            autoRecoveryURL = nil
            selection = store.project.score.notes.isEmpty ? .record : .edit
        } catch { message = error.localizedDescription }
    }

    func duplicateProject(_ summary: ProjectSummary) {
        do {
            _ = try ProjectLibrary.duplicate(summary.url)
            refreshProjectList()
        } catch { message = error.localizedDescription }
    }

    func deleteProject(_ summary: ProjectSummary) {
        do {
            try ProjectLibrary.delete(summary.url)
            if store.projectURL == summary.url { store.newProject() }
            refreshProjectList()
        } catch { message = error.localizedDescription }
    }

    func refreshProjectList() {
        projectSummaries = ProjectLibrary.listProjects()
    }

    // MARK: - Autosave / crash recovery

    private func performAutosave() {
        guard hasManualEdits || recorder.recordingURL != nil || store.projectURL != nil else { return }
        do {
            if let url = store.projectURL {
                try store.save(to: url)
            } else if !store.project.score.notes.isEmpty || recorder.recordingURL != nil {
                let url = autoRecoveryURL ?? ProjectLibrary.suggestedURL(for: store.project.name, in: ProjectLibrary.autoRecoveryDirectory())
                autoRecoveryURL = url
                try store.writeAutoRecoverySnapshot(to: url, freshRecordingURL: recorder.recordingURL)
            }
        } catch {
            // Best effort: autosave failures are not surfaced to avoid noisy interruptions.
        }
    }

    func checkForRecovery() {
        recoveryAvailableURL = ProjectLibrary.latestRecovery()
    }

    func restoreFromRecovery() {
        guard let url = recoveryAvailableURL else { return }
        do {
            try store.load(from: url)
            let destination = ProjectLibrary.suggestedURL(for: store.project.name)
            try store.ensureAudioIsPresent(atNewLocation: destination, freshRecordingURL: nil)
            try store.save(to: destination)
            ProjectLibrary.clearAutoRecovery()
            metronome.bpm = store.project.score.bpm
            hasManualEdits = false
            refreshProjectList()
            selection = store.project.score.notes.isEmpty ? .record : .edit
            message = "自動保存されたプロジェクトを復元しました。"
        } catch { message = error.localizedDescription }
        recoveryAvailableURL = nil
    }

    func discardRecovery() {
        ProjectLibrary.clearAutoRecovery()
        recoveryAvailableURL = nil
    }

    // MARK: - Export

    enum ExportKind: String, CaseIterable, Identifiable {
        case midi = "MIDI"
        case musicXML = "MusicXML"
        case pdf = "PDF楽譜"
        case wave = "WAV音声"
        var id: String { rawValue }
        var pathExtension: String {
            switch self { case .midi: "mid"; case .musicXML: "musicxml"; case .pdf: "pdf"; case .wave: "wav" }
        }
    }

    func export(_ kind: ExportKind) {
        let panel = NSSavePanel()
        panel.title = "\(kind.rawValue)を書き出し"
        panel.nameFieldStringValue = "\(store.project.name).\(kind.pathExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                switch kind {
                case .midi: try MIDIExporter.write(score: store.project.score, to: url)
                case .musicXML: try MusicXMLExporter.write(score: store.project.score, title: store.project.name, to: url)
                case .pdf: try PDFScoreExporter.write(score: store.project.score, title: store.project.name, to: url)
                case .wave: try WaveExporter.write(score: store.project.score, to: url)
                }
                message = "\(kind.rawValue)を書き出しました。"
            } catch { message = error.localizedDescription }
        }
    }
}
