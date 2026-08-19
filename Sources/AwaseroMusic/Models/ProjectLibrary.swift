import Foundation

struct ProjectSummary: Identifiable, Hashable {
    var url: URL
    var name: String
    var updatedAt: Date
    var noteCount: Int
    var durationBeats: Double
    var id: URL { url }
}

/// Manages the app-owned project directory used by the project list screen (F-01),
/// plus a separate auto-recovery directory used for crash recovery.
enum ProjectLibrary {
    static func directory() -> URL {
        managedDirectory(named: "Projects")
    }

    static func autoRecoveryDirectory() -> URL {
        managedDirectory(named: "AutoRecovery")
    }

    private static func managedDirectory(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("AwaseroMusic", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func listProjects() -> [ProjectSummary] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return entries.compactMap { url -> ProjectSummary? in
            guard url.pathExtension == "hummingproject" else { return nil }
            guard let data = try? Data(contentsOf: url.appendingPathComponent("project.json")) else { return nil }
            guard let project = try? decoder.decode(AwaseroProject.self, from: data) else { return nil }
            let duration = project.score.notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
            return ProjectSummary(url: url, name: project.name, updatedAt: project.updatedAt, noteCount: project.score.notes.count, durationBeats: duration)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func suggestedURL(for name: String, in directory: URL? = nil) -> URL {
        let target = directory ?? self.directory()
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新しい曲" : name
        var candidate = target.appendingPathComponent("\(safeName).hummingproject")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = target.appendingPathComponent("\(safeName) \(suffix).hummingproject")
            suffix += 1
        }
        return candidate
    }

    @discardableResult
    static func duplicate(_ url: URL) throws -> URL {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url.appendingPathComponent("project.json"))
        var project = try decoder.decode(AwaseroProject.self, from: data)

        let destination = suggestedURL(for: "\(project.name) のコピー")
        try FileManager.default.copyItem(at: url, to: destination)

        project.id = UUID()
        project.name = destination.deletingPathExtension().lastPathComponent
        project.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(project).write(to: destination.appendingPathComponent("project.json"), options: .atomic)
        return destination
    }

    /// Moves the project package to the Trash rather than deleting it outright, so it stays recoverable.
    static func delete(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func clearAutoRecovery() {
        let directory = autoRecoveryDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries { try? FileManager.default.removeItem(at: entry) }
    }

    /// The most recently modified auto-recovery package, if any.
    static func latestRecovery() -> URL? {
        let directory = autoRecoveryDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return entries
            .filter { $0.pathExtension == "hummingproject" }
            .max { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhsDate < rhsDate
            }
    }
}
