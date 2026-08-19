import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(AppState.Section.allCases, selection: $state.selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("合わせろMusic")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Divider()
                    Button("プロジェクトを保存", systemImage: "square.and.arrow.down") { state.quickSave() }
                        .buttonStyle(.borderless)
                        .accessibilityHint("現在のプロジェクトを保存します")
                }
                .padding()
            }
        } detail: {
            Group {
                switch state.selection ?? .projects {
                case .projects: ProjectListView()
                case .record: RecordingView()
                case .edit: ScoreEditorView()
                case .chords: ChordView()
                case .export: ExportView()
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    TextField("曲名", text: $state.store.project.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Button(state.scorePlayer.isPlaying ? "停止" : "試聴", systemImage: state.scorePlayer.isPlaying ? "stop.fill" : "play.fill") {
                        state.scorePlayer.isPlaying ? state.scorePlayer.stop() : state.scorePlayer.play(score: state.store.project.score)
                    }
                    .disabled(state.store.project.score.notes.isEmpty)
                }
            }
        }
        .alert("合わせろMusic", isPresented: Binding(
            get: { state.message != nil },
            set: { if !$0 { state.message = nil } }
        )) {
            Button("OK") { state.message = nil }
        } message: {
            Text(state.message ?? "")
        }
        .alert("編集内容を破棄しますか？", isPresented: Binding(
            get: { state.confirmDiscardMessage != nil },
            set: { if !$0 { state.cancelPendingAction() } }
        )) {
            Button("キャンセル", role: .cancel) { state.cancelPendingAction() }
            Button("破棄して続行", role: .destructive) { state.confirmPendingAction() }
        } message: {
            Text(state.confirmDiscardMessage ?? "")
        }
        .alert("自動保存されたプロジェクトがあります", isPresented: Binding(
            get: { state.recoveryAvailableURL != nil },
            set: { if !$0 { state.discardRecovery() } }
        )) {
            Button("破棄", role: .destructive) { state.discardRecovery() }
            Button("復元") { state.restoreFromRecovery() }
        } message: {
            Text("前回終了時に保存されていなかったプロジェクトが見つかりました。復元しますか？")
        }
    }
}
