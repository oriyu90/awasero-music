import XCTest
@testable import AwaseroMusic

@MainActor
final class UndoRedoTests: XCTestCase {
    func testUndoRestoresPreviousScoreAndRedoReappliesIt() {
        let store = ProjectStore()
        store.project.score.notes = [NoteEvent(startBeat: 0, durationBeats: 1, midiNote: 60)]

        store.pushUndoSnapshot()
        store.project.score.notes.append(NoteEvent(startBeat: 1, durationBeats: 1, midiNote: 64))
        XCTAssertEqual(store.project.score.notes.count, 2)

        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.project.score.notes.count, 1)
        XCTAssertFalse(store.canUndo)

        XCTAssertTrue(store.canRedo)
        store.redo()
        XCTAssertEqual(store.project.score.notes.count, 2)
        XCTAssertFalse(store.canRedo)
    }

    func testNewMutationAfterUndoClearsRedoStack() {
        let store = ProjectStore()
        store.pushUndoSnapshot()
        store.project.score.notes.append(NoteEvent(startBeat: 0, durationBeats: 1, midiNote: 60))
        store.undo()
        XCTAssertTrue(store.canRedo)

        store.pushUndoSnapshot()
        store.project.score.notes.append(NoteEvent(startBeat: 0, durationBeats: 1, midiNote: 67))
        XCTAssertFalse(store.canRedo, "starting a new edit after an undo should discard the redo history")
    }

    func testUndoWithEmptyHistoryIsANoOp() {
        let store = ProjectStore()
        store.project.score.notes = [NoteEvent(startBeat: 0, durationBeats: 1, midiNote: 60)]
        store.undo()
        XCTAssertEqual(store.project.score.notes.count, 1)
    }
}
