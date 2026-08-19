import SwiftUI

struct RecordingView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("鼻歌を録音")
                        .font(.largeTitle.bold())
                    Text("メトロノームに合わせて歌うと、リズムの認識精度が上がります。")
                        .foregroundStyle(.secondary)
                }

                GroupBox("入力機器") {
                    HStack {
                        Picker("マイク", selection: $state.recorder.selectedDeviceID) {
                            Text("システム既定").tag(String?.none)
                            ForEach(state.recorder.availableDevices) { device in
                                Text(device.name).tag(String?.some(device.uniqueID))
                            }
                        }
                        .frame(width: 280)
                        .disabled(state.recorder.isRecording)
                        Button("更新", systemImage: "arrow.clockwise") { state.recorder.refreshDevices() }
                            .disabled(state.recorder.isRecording)
                            .accessibilityLabel("入力機器一覧を更新")
                        Spacer()
                    }
                    .padding(8)
                }

                GroupBox("メトロノーム") {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading) {
                            Text("テンポ")
                            HStack {
                                Slider(value: $state.metronome.bpm, in: 40...240, step: 1)
                                    .frame(width: 260)
                                    .onChange(of: state.metronome.bpm) { _, _ in state.metronome.restartIfRunning() }
                                Text("\(Int(state.metronome.bpm)) BPM").monospacedDigit().frame(width: 75)
                            }
                        }
                        Picker("拍子", selection: $state.metronome.beatsPerBar) {
                            Text("3/4").tag(3); Text("4/4").tag(4); Text("6/8").tag(6)
                        }
                        .frame(width: 130)
                        Stepper("カウントイン \(state.countInBars)小節", value: $state.countInBars, in: 0...4)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(0..<state.metronome.beatsPerBar, id: \.self) { beat in
                                Circle()
                                    .fill(state.metronome.isRunning && beat == (state.metronome.currentBeat + state.metronome.beatsPerBar - 1) % state.metronome.beatsPerBar ? Color.accentColor : Color.secondary.opacity(0.25))
                                    .frame(width: 12, height: 12)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("現在の拍")
                        .accessibilityValue(state.metronome.isRunning ? "\((state.metronome.currentBeat + state.metronome.beatsPerBar - 1) % state.metronome.beatsPerBar + 1) / \(state.metronome.beatsPerBar)" : "停止中")
                        Button(state.metronome.isRunning ? "停止" : "試す") {
                            state.metronome.isRunning ? state.metronome.stop() : state.metronome.start()
                        }
                    }
                    .padding(8)
                }

                VStack(spacing: 22) {
                    ZStack {
                        Circle().fill(state.recorder.isRecording ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.08)).frame(width: 190, height: 190)
                        VStack(spacing: 10) {
                            Image(systemName: state.recorder.isRecording ? "waveform" : "mic.fill")
                                .font(.system(size: 46)).foregroundStyle(state.recorder.isRecording ? Color.red : Color.accentColor)
                            Text(formatTime(state.recorder.elapsed)).font(.system(size: 30, design: .rounded).monospacedDigit())
                            Text(state.recorder.isRecording ? "録音中" : "録音待機").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(state.recorder.isRecording ? "録音中、経過時間\(formatTime(state.recorder.elapsed))" : "録音待機")

                    ProgressView(value: Double(state.recorder.inputLevel), total: 1)
                        .tint(state.recorder.inputLevel > 0.85 ? .red : .green)
                        .frame(maxWidth: 420)
                        .accessibilityLabel("入力レベル")
                        .accessibilityValue("\(Int(state.recorder.inputLevel * 100))パーセント")

                    if let warning = state.recorder.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(8)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityAddTraits(.isHeader)
                    }

                    HStack(spacing: 12) {
                        Button("録音開始", systemImage: "record.circle") { state.startRecording() }
                            .buttonStyle(.borderedProminent).tint(.red)
                            .disabled(state.recorder.isRecording || state.isAnalyzing)
                        Button("停止", systemImage: "stop.fill") { state.stopRecording() }
                            .disabled(!state.recorder.isRecording)
                        Button(state.recorder.isPlaying ? "再生停止" : "録音を聴く", systemImage: state.recorder.isPlaying ? "stop.fill" : "play.fill") {
                            state.recorder.isPlaying ? state.recorder.stopPlayback() : state.recorder.playRecording()
                        }
                        .disabled(state.recordingURL == nil || state.recorder.isRecording)
                    }
                }
                .frame(maxWidth: .infinity)

                GroupBox {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(state.isAnalyzing ? state.analysisStage.rawValue : "録音後に高精度解析を実行します")
                                .font(.headline)
                            Text("音程の相対関係を保ち、調と全体のピッチずれを推定します。")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.isAnalyzing {
                            ProgressView().controlSize(.small)
                            Button("キャンセル", systemImage: "xmark.circle") { state.cancelAnalysis() }
                        }
                        Button("解析する", systemImage: "waveform.badge.magnifyingglass") { state.analyzeRecording() }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.recordingURL == nil || state.recorder.isRecording || state.isAnalyzing)
                    }
                    .padding(8)
                }
            }
            .padding(28)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d.%01d", Int(seconds) / 60, Int(seconds) % 60, Int(seconds * 10) % 10)
    }
}
