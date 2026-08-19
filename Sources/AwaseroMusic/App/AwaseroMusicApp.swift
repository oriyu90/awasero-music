import SwiftUI

@main
struct AwaseroMusicApp: App {
    @StateObject private var state = AppState()

    init() {
        if CommandLine.arguments.contains("--self-check") {
            let passed = CoreSelfCheck.run()
            Foundation.exit(passed ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup("合わせろMusic") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 650)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新規プロジェクト") { state.newProject() }
                    .keyboardShortcut("n")
                Button("プロジェクトを開く…") { state.openProjectFromDisk() }
                    .keyboardShortcut("o")
                Button("プロジェクトを保存") { state.quickSave() }
                    .keyboardShortcut("s")
                Button("名前を付けて保存…") { state.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("取り消す") { state.undo() }
                    .keyboardShortcut("z")
                    .disabled(!state.canUndo)
                Button("やり直す") { state.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!state.canRedo)
            }
            CommandMenu("再生") {
                Button(state.scorePlayer.isPlaying ? "停止" : "メロディを再生") {
                    state.scorePlayer.isPlaying ? state.scorePlayer.stop() : state.scorePlayer.play(score: state.store.project.score)
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }
}
