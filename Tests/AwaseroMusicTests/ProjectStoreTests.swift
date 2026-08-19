import XCTest
@testable import AwaseroMusic

@MainActor
final class ProjectStoreTests: XCTestCase {
    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = ProjectStore()
        store.project.name = "テスト曲"
        store.project.score.notes = [NoteEvent(startBeat: 0, durationBeats: 1, midiNote: 62)]
        store.project.score.bpm = 133

        let packageURL = temporaryDirectory("project")
        defer { try? FileManager.default.removeItem(at: packageURL) }
        try store.save(to: packageURL)

        let loader = ProjectStore()
        try loader.load(from: packageURL)
        XCTAssertEqual(loader.project.name, "テスト曲")
        XCTAssertEqual(loader.project.score.notes.first?.midiNote, 62)
        XCTAssertEqual(loader.project.score.bpm, 133, accuracy: 0.001)
    }

    /// Regression test for the "save to a new location after loading, without a fresh recording"
    /// bug: the original audio must be carried over rather than silently dropped.
    func testEnsureAudioIsPresentCopiesAudioWhenSavingToNewLocationWithoutFreshRecording() throws {
        let originalPackage = temporaryDirectory("original")
        let relocatedPackage = temporaryDirectory("relocated")
        defer {
            try? FileManager.default.removeItem(at: originalPackage)
            try? FileManager.default.removeItem(at: relocatedPackage)
        }

        // Simulate an initial save with a freshly-recorded audio file.
        let fakeRecording = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).caf")
        try Data("fake-audio".utf8).write(to: fakeRecording)
        defer { try? FileManager.default.removeItem(at: fakeRecording) }

        let store = ProjectStore()
        _ = try store.copyAudioIntoProject(source: fakeRecording, packageURL: originalPackage)
        try store.save(to: originalPackage)
        XCTAssertNotNil(store.project.audioFileName)

        // Now reload (as if the app were relaunched) and save to a different folder with no
        // in-session recording — this must still bring the audio along.
        let reloaded = ProjectStore()
        try reloaded.load(from: originalPackage)
        try reloaded.ensureAudioIsPresent(atNewLocation: relocatedPackage, freshRecordingURL: nil)
        try reloaded.save(to: relocatedPackage)

        let audioName = try XCTUnwrap(reloaded.project.audioFileName)
        let copiedAudioPath = relocatedPackage.appendingPathComponent(audioName).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedAudioPath), "audio file should have been copied to the new location")
    }
}
