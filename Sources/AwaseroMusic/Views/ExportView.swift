import SwiftUI

struct ExportView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("書き出し").font(.largeTitle.bold())
            Text("DAW、楽譜ソフト、歌声合成ソフトで使える形式に変換します。")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))], spacing: 16) {
                exportCard(.midi, icon: "pianokeys", description: "テンポ・拍子・音符・ベロシティを含む標準MIDI")
                exportCard(.musicXML, icon: "music.note.list", description: "対応する楽譜制作ソフトで編集できる楽譜データ")
                exportCard(.pdf, icon: "doc.richtext", description: "共有・印刷用の五線譜PDF")
                exportCard(.wave, icon: "waveform", description: "内蔵音色でメロディを再生した音声")
            }
            GroupBox("書き出し内容") {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow { Text("曲名").foregroundStyle(.secondary); Text(state.store.project.name) }
                    GridRow { Text("音符数").foregroundStyle(.secondary); Text("\(state.store.project.score.notes.count)") }
                    GridRow { Text("テンポ").foregroundStyle(.secondary); Text("\(Int(state.store.project.score.bpm)) BPM") }
                    GridRow { Text("拍子").foregroundStyle(.secondary); Text("\(state.store.project.score.timeSignature.numerator)/\(state.store.project.score.timeSignature.denominator)") }
                    GridRow { Text("コード").foregroundStyle(.secondary); Text(state.store.project.score.chords.map(\.symbol).joined(separator: " / ")) }
                }.padding(8)
            }
            Spacer()
        }
        .padding(28)
    }

    private func exportCard(_ kind: AppState.ExportKind, icon: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(.tint)
            Text(kind.rawValue).font(.title3.bold())
            Text(description).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Button("書き出す", systemImage: "square.and.arrow.up") { state.export(kind) }
                .buttonStyle(.borderedProminent).disabled(state.store.project.score.notes.isEmpty)
                .accessibilityHint(description)
        }
        .padding(18).background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }
}
