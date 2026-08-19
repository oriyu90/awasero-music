import SwiftUI

struct ScoreEditorView: View {
    @EnvironmentObject private var state: AppState
    @State private var presentation = 0
    @State private var showTempoEditor = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("表示", selection: $presentation) {
                    Text("ピアノロール").tag(0)
                    Text("五線譜").tag(1)
                }
                .pickerStyle(.segmented).frame(width: 240)
                Divider().frame(height: 20)
                HStack {
                    Text("BPM")
                    TextField("BPM", value: $state.store.project.score.bpm, format: .number)
                        .frame(width: 58).textFieldStyle(.roundedBorder)
                    Picker("拍子", selection: timeSignaturePresetBinding) {
                        ForEach(TimeSignaturePreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }.frame(width: 110)
                }
                if let analysis = state.store.project.analysis, !analysis.keyCandidates.isEmpty {
                    Picker("調", selection: Binding(
                        get: { state.store.project.score.selectedKey?.id ?? analysis.keyCandidates[0].id },
                        set: { id in if let key = analysis.keyCandidates.first(where: { $0.id == id }) { state.selectKey(key) } }
                    )) {
                        ForEach(analysis.keyCandidates) { key in
                            Text("\(key.name)  \(Int(key.score * 100))%").tag(key.id)
                        }
                    }.frame(width: 210)
                }
                Spacer()
                Button("テンポ編集", systemImage: "metronome") { showTempoEditor = true }
                    .popover(isPresented: $showTempoEditor) { TempoEditorView() }
                Button("再解析", systemImage: "arrow.clockwise") { state.reanalyze() }
                    .disabled(state.recordingURL == nil || state.isAnalyzing)
                Button("音符を追加", systemImage: "plus") { state.addNote() }
                Button("削除", systemImage: "trash") { state.deleteSelectedNotes() }
                    .disabled(state.selectedNoteIDs.isEmpty)
            }
            .padding()
            Divider()

            if state.store.project.score.notes.isEmpty {
                ContentUnavailableView("音符がありません", systemImage: "music.note", description: Text("鼻歌を録音して解析するか、音符を追加してください。"))
            } else {
                HSplitView {
                    Group {
                        if presentation == 0 {
                            PianoRollView()
                        } else {
                            StaffScoreView()
                        }
                    }
                    .frame(minWidth: 580)
                    NoteInspector()
                        .frame(minWidth: 230, idealWidth: 270, maxWidth: 320)
                }
            }
        }
        .navigationTitle("楽譜編集")
    }

    private var timeSignaturePresetBinding: Binding<TimeSignaturePreset> {
        Binding(
            get: { TimeSignaturePreset.matching(state.store.project.score.timeSignature) },
            set: { preset in state.store.project.score.timeSignature = preset.timeSignature }
        )
    }
}

private struct TempoEditorView: View {
    @EnvironmentObject private var state: AppState
    @State private var newBeat: Double = 0
    @State private var newBPM: Double = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("テンポ編集").font(.headline)
            Text("拍位置ごとにテンポを設定します。同じ拍を再入力すると上書きされます。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(state.store.project.score.tempoEvents.sorted { $0.beat < $1.beat }) { event in
                HStack {
                    Text("拍 \(event.beat, format: .number)").frame(width: 70, alignment: .leading)
                    Text("\(Int(event.bpm)) BPM")
                    Spacer()
                    Button("削除", systemImage: "minus.circle") { state.removeTempoEvent(event.id) }
                        .labelStyle(.iconOnly)
                        .disabled(state.store.project.score.tempoEvents.count <= 1)
                        .accessibilityLabel("拍\(event.beat, format: .number)のテンポを削除")
                }
            }
            Divider()
            HStack {
                TextField("拍", value: $newBeat, format: .number).frame(width: 60)
                TextField("BPM", value: $newBPM, format: .number).frame(width: 60)
                Button("追加/更新") { state.addTempoEvent(beat: newBeat, bpm: newBPM) }
            }
        }
        .padding()
        .frame(width: 280)
    }
}

private struct PianoRollView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let notes = state.store.project.score.notes
        GeometryReader { proxy in
            let minNote = max(0, (notes.map(\.midiNote).min() ?? 60) - 3)
            let maxNote = min(127, (notes.map(\.midiNote).max() ?? 72) + 3)
            let totalBeats = max(8, notes.map { $0.startBeat + $0.durationBeats }.max() ?? 8)
            let rowHeight = max(14, proxy.size.height / CGFloat(maxNote - minNote + 1))
            let beatWidth = max(42, proxy.size.width / totalBeats)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        for note in minNote...maxNote {
                            let y = CGFloat(maxNote - note) * rowHeight
                            let isBlack = [1, 3, 6, 8, 10].contains(note % 12)
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)), with: .color(isBlack ? .gray.opacity(0.08) : .clear))
                            context.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)), with: .color(.gray.opacity(0.18)), lineWidth: 0.5)
                        }
                        for beat in 0...Int(ceil(totalBeats)) {
                            let x = CGFloat(beat) * beatWidth
                            context.stroke(Path { path in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(.gray.opacity(beat % 4 == 0 ? 0.5 : 0.2)), lineWidth: beat % 4 == 0 ? 1.5 : 0.5)
                        }
                    }
                    .accessibilityHidden(true)
                    ForEach(notes) { note in
                        let x = CGFloat(note.startBeat) * beatWidth
                        let y = CGFloat(maxNote - note.midiNote) * rowHeight + 1
                        let isSelected = state.selectedNoteIDs.contains(note.id)
                        Button {
                            state.selectNote(note.id, extend: NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command))
                        } label: {
                            Text(note.noteName).font(.caption2.bold()).lineLimit(1).padding(.horizontal, 4)
                                .frame(width: max(22, CGFloat(note.durationBeats) * beatWidth - 2), height: rowHeight - 2, alignment: .leading)
                                .background(isSelected ? Color.orange : Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain).position(x: x + max(22, CGFloat(note.durationBeats) * beatWidth - 2) / 2, y: y + (rowHeight - 2) / 2)
                        .accessibilityLabel("\(note.noteName)、拍\(note.startBeat, format: .number)から\(note.durationBeats, format: .number)拍分")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .frame(width: CGFloat(totalBeats) * beatWidth, height: CGFloat(maxNote - minNote + 1) * rowHeight)
            }
        }
        .padding(12)
    }
}

private struct StaffScoreView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let score = state.store.project.score
        GeometryReader { proxy in
            let totalBeats = max(4, score.notes.map { $0.startBeat + $0.durationBeats }.max() ?? 4)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let top: CGFloat = 120
                    for line in 0..<5 {
                        let y = top + CGFloat(line) * 14
                        context.stroke(Path { path in path.move(to: CGPoint(x: 45, y: y)); path.addLine(to: CGPoint(x: size.width - 30, y: y)) }, with: .color(.primary), lineWidth: 1)
                    }
                    for beat in stride(from: 0.0, through: totalBeats, by: Double(score.timeSignature.numerator)) {
                        let x = 55 + CGFloat(beat / totalBeats) * (size.width - 100)
                        context.stroke(Path { path in path.move(to: CGPoint(x: x, y: top)); path.addLine(to: CGPoint(x: x, y: top + 56)) }, with: .color(.secondary), lineWidth: 1)
                    }
                    context.draw(Text("𝄞").font(.system(size: 54)), at: CGPoint(x: 68, y: top + 28))
                }
                .accessibilityHidden(true)
                ForEach(score.notes) { note in
                    let x = 90 + CGFloat(note.startBeat / totalBeats) * (proxy.size.width - 135)
                    let y = 176 - CGFloat(note.midiNote - 60) * 3.5
                    let isSelected = state.selectedNoteIDs.contains(note.id)
                    Button {
                        state.selectNote(note.id, extend: NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command))
                    } label: {
                        Ellipse().fill(isSelected ? Color.orange : Color.primary).frame(width: 16, height: 11)
                    }
                    .buttonStyle(.plain).position(x: x, y: y)
                    .accessibilityLabel("\(note.noteName)、拍\(note.startBeat, format: .number)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .padding(12)
    }
}

private struct NoteInspector: View {
    @EnvironmentObject private var state: AppState
    @State private var rampStart: Double = 90
    @State private var rampEnd: Double = 90

    var selectedIndex: Int? {
        guard state.selectedNoteIDs.count == 1, let id = state.selectedNoteID else { return nil }
        return state.store.project.score.notes.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("音符の編集").font(.title2.bold())
            if state.selectedNoteIDs.count > 1 {
                multiSelectionPanel
            } else if let index = selectedIndex {
                singleNotePanel(index: index)
            } else {
                ContentUnavailableView("音符を選択", systemImage: "cursorarrow.click", description: Text("編集する音符をクリックしてください。複数選択はShift/Cmdクリックです。"))
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func singleNotePanel(index: Int) -> some View {
        let binding = $state.store.project.score.notes[index]
        LabeledContent("音名") { Text(binding.wrappedValue.noteName).font(.headline) }
        Stepper("音程  \(binding.wrappedValue.midiNote)", value: binding.midiNote, in: 0...127)
            .onChange(of: binding.wrappedValue.midiNote) { _, _ in state.noteFieldDidChange() }
        LabeledContent("開始位置") {
            TextField("拍", value: binding.startBeat, format: .number).frame(width: 90)
                .onSubmit { state.noteFieldDidChange() }
        }
        LabeledContent("長さ") {
            TextField("拍", value: binding.durationBeats, format: .number).frame(width: 90)
                .onSubmit { state.noteFieldDidChange() }
        }
        Stepper("ベロシティ  \(binding.wrappedValue.velocity)", value: binding.velocity, in: 1...127)
            .onChange(of: binding.wrappedValue.velocity) { _, _ in state.noteFieldDidChange() }
        VStack(alignment: .leading) {
            Text("解析信頼度")
            ProgressView(value: binding.wrappedValue.confidence)
                .accessibilityValue("\(Int(binding.wrappedValue.confidence * 100))パーセント")
            Text("\(Int(binding.wrappedValue.confidence * 100))%").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: state.selectedNoteID) { _, _ in state.beginNoteFieldEdit() }
    }

    @ViewBuilder
    private var multiSelectionPanel: some View {
        Text("\(state.selectedNoteIDs.count)音を選択中").font(.headline)
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text("ベロシティを一括設定").font(.subheadline.bold())
            HStack {
                Slider(value: $rampStart, in: 1...127, step: 1)
                Text("\(Int(rampStart))").frame(width: 32)
            }
            Button("選択範囲に適用") { state.applyVelocity(Int(rampStart)) }
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text("クレッシェンド／デクレッシェンド").font(.subheadline.bold())
            HStack {
                Text("開始"); Slider(value: $rampStart, in: 1...127, step: 1); Text("\(Int(rampStart))").frame(width: 32)
            }
            HStack {
                Text("終了"); Slider(value: $rampEnd, in: 1...127, step: 1); Text("\(Int(rampEnd))").frame(width: 32)
            }
            Button("選択範囲へ適用(開始→終了で線形変化)") {
                state.applyVelocityRamp(from: Int(rampStart), to: Int(rampEnd))
            }
        }
    }
}
