import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published var project: AwaseroProject
    @Published var projectURL: URL?
    @Published var lastError: String?

    private var undoStack: [ScoreDocument] = []
    private var redoStack: [ScoreDocument] = []
    private let undoLimit = 50

    init(project: AwaseroProject = AwaseroProject(name: "新しい曲")) {
        self.project = project
    }

    func newProject() {
        project = AwaseroProject(name: "新しい曲")
        projectURL = nil
        lastError = nil
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - Undo/Redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Call before any user-driven mutation of `project.score` that should be undoable.
    func pushUndoSnapshot() {
        undoStack.append(project.score)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project.score)
        project.score = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project.score)
        project.score = next
    }

    /// Clears history when the score baseline changes for reasons other than user edits (e.g. a fresh analysis run).
    func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - Persistence

    func save(to packageURL: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        project.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(project).write(to: packageURL.appendingPathComponent("project.json"), options: .atomic)
        projectURL = packageURL
    }

    func load(from packageURL: URL) throws {
        let data = try Data(contentsOf: packageURL.appendingPathComponent("project.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        project = try decoder.decode(AwaseroProject.self, from: data)
        projectURL = packageURL
        undoStack.removeAll()
        redoStack.removeAll()
    }

    func copyAudioIntoProject(source: URL, packageURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let destination = packageURL.appendingPathComponent("original-audio.\(source.pathExtension.isEmpty ? "caf" : source.pathExtension)")
        if source.standardizedFileURL != destination.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
        project.audioFileName = destination.lastPathComponent
        return destination
    }

    /// Ensures the package at `packageURL` has the project's audio file. If there is no fresh
    /// in-session recording, falls back to copying the audio from the previously loaded/saved
    /// package so that saving to a new location never silently drops the original recording.
    func ensureAudioIsPresent(atNewLocation packageURL: URL, freshRecordingURL: URL?) throws {
        if let fresh = freshRecordingURL {
            _ = try copyAudioIntoProject(source: fresh, packageURL: packageURL)
            return
        }
        guard let name = project.audioFileName else { return }
        let destination = packageURL.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { return }
        guard let previousPackage = projectURL else { return }
        let source = previousPackage.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    /// Writes a snapshot of the current project to `packageURL` without mutating `project` or
    /// `projectURL` — used for crash-recovery autosaves that must not be mistaken for a real save.
    func writeAutoRecoverySnapshot(to packageURL: URL, freshRecordingURL: URL?) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        var snapshot = project
        if let fresh = freshRecordingURL {
            let destination = packageURL.appendingPathComponent("original-audio.\(fresh.pathExtension.isEmpty ? "caf" : fresh.pathExtension)")
            if fresh.standardizedFileURL != destination.standardizedFileURL {
                if manager.fileExists(atPath: destination.path) { try? manager.removeItem(at: destination) }
                try manager.copyItem(at: fresh, to: destination)
            }
            snapshot.audioFileName = destination.lastPathComponent
        } else if let name = project.audioFileName, let previousPackage = projectURL {
            let source = previousPackage.appendingPathComponent(name)
            let destination = packageURL.appendingPathComponent(name)
            if manager.fileExists(atPath: source.path), !manager.fileExists(atPath: destination.path) {
                try? manager.copyItem(at: source, to: destination)
            }
        }
        snapshot.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: packageURL.appendingPathComponent("project.json"), options: .atomic)
    }
}
