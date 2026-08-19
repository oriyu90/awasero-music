import SwiftUI

struct ChordView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("コード進行").font(.largeTitle.bold())
                    Text("メロディと調から、各小節に合うコードを推定します。伴奏音源は生成しません。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("コードを再推定", systemImage: "arrow.clockwise") { state.regenerateChords() }
                    .disabled(state.store.project.score.notes.isEmpty)
            }
            if let key = state.store.project.score.selectedKey {
                Label("推定キー: \(key.name)（信頼度 \(Int(key.score * 100))%）", systemImage: "key.horizontal")
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if state.store.project.score.chords.isEmpty {
                ContentUnavailableView("コードがありません", systemImage: "guitars", description: Text("先に鼻歌を解析してください。"))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(state.store.project.score.chords.indices), id: \.self) { index in
                            ChordCell(index: index, chord: state.store.project.score.chords[index])
                        }
                    }.padding(.vertical)
                }
                Text("コード一覧: " + state.store.project.score.chords.map(\.symbol).joined(separator: "  |  "))
                    .font(.title3.monospaced()).textSelection(.enabled)
            }
            Spacer()
        }
        .padding(28)
    }
}

private struct ChordCell: View {
    @EnvironmentObject private var state: AppState
    let index: Int
    let chord: ChordSuggestion
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Text("小節 \(index + 1)").font(.caption).foregroundStyle(.secondary)
            TextField("コード", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .onSubmit { state.updateChordSymbol(at: index, to: draft) }
                .accessibilityLabel("小節\(index + 1)のコード")
                .accessibilityValue(chord.symbol)
            Text("信頼度 \(Int(chord.confidence * 100))%").font(.caption)
        }
        .frame(width: 120, height: 100)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { draft = chord.symbol }
        .onChange(of: chord.symbol) { _, newValue in draft = newValue }
    }
}
