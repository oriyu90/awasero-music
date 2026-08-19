import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject private var state: AppState
    @State private var pendingDeletion: ProjectSummary?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("プロジェクト").font(.largeTitle.bold())
                    Text("保存済みのプロジェクトを開く、複製する、削除する").foregroundStyle(.secondary)
                }
                Spacer()
                Button("他の場所から開く…", systemImage: "folder") { state.openProjectFromDisk() }
                Button("新規プロジェクト", systemImage: "plus") { state.newProject() }
                    .buttonStyle(.borderedProminent)
            }

            if state.projectSummaries.isEmpty {
                ContentUnavailableView(
                    "保存済みプロジェクトはありません",
                    systemImage: "music.note.list",
                    description: Text("「新規プロジェクト」から鼻歌の録音を始めてください。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(state.projectSummaries) { summary in
                    HStack(spacing: 16) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.title)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.name).font(.headline)
                            Text("更新日時: \(dateFormatter.string(from: summary.updatedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("音符数: \(summary.noteCount) / 長さ: \(Int(summary.durationBeats))拍")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("開く") { state.openProjectFromLibrary(summary.url) }
                            .buttonStyle(.borderedProminent)
                        Button("複製", systemImage: "plus.square.on.square") { state.duplicateProject(summary) }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("\(summary.name) を複製")
                        Button("削除", systemImage: "trash", role: .destructive) { pendingDeletion = summary }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("\(summary.name) を削除")
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { state.openProjectFromLibrary(summary.url) }
                }
                .listStyle(.inset)
            }
        }
        .padding(28)
        .onAppear { state.refreshProjectList() }
        .alert("プロジェクトを削除しますか？", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("キャンセル", role: .cancel) { pendingDeletion = nil }
            Button("ゴミ箱に入れる", role: .destructive) {
                if let pendingDeletion { state.deleteProject(pendingDeletion) }
                pendingDeletion = nil
            }
        } message: {
            Text("「\(pendingDeletion?.name ?? "")」をゴミ箱に移動します。ゴミ箱から元に戻すことができます。")
        }
    }
}
