import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Records via AVAudioEngine (rather than AVAudioRecorder) so a specific input device can be
/// bound to just this app's input node, without touching the user's system-wide default input.
@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {
    struct InputDevice: Identifiable, Hashable {
        var uniqueID: String
        var name: String
        var id: String { uniqueID }
    }

    static let maxRecordingSeconds: TimeInterval = 300
    private static let nearLimitWarningSeconds: TimeInterval = 270
    private static let silenceWarningThreshold: TimeInterval = 3

    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var inputLevel: Float = 0
    @Published var lastError: String?
    @Published private(set) var warning: String?
    @Published private(set) var availableDevices: [InputDevice] = []
    @Published var selectedDeviceID: String?

    private let engine = AVAudioEngine()
    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var recordingStartDate: Date?
    private var silenceStartDate: Date?
    private(set) var recordingURL: URL?

    override init() {
        super.init()
        refreshDevices()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceChangeNotification), name: .AVCaptureDeviceWasConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceChangeNotification), name: .AVCaptureDeviceWasDisconnected, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private nonisolated func handleDeviceChangeNotification() {
        Task { @MainActor [weak self] in self?.refreshDevices() }
    }

    /// Refreshes the list of selectable input devices. If the currently selected device
    /// disconnected, silently falls back to the system default input.
    func refreshDevices() {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
        availableDevices = session.devices.map { InputDevice(uniqueID: $0.uniqueID, name: $0.localizedName) }
        if let selectedDeviceID, !availableDevices.contains(where: { $0.uniqueID == selectedDeviceID }) {
            self.selectedDeviceID = nil
        }
    }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func startRecording() async {
        guard await requestPermission() else {
            lastError = "マイクの使用が許可されていません。システム設定から許可してください。"
            return
        }
        if let previous = recordingURL {
            try? FileManager.default.removeItem(at: previous)
        }
        engine.inputNode.removeTap(onBus: 0)
        if let selectedDeviceID {
            do {
                try Self.bindInput(engine.inputNode, toDeviceUID: selectedDeviceID)
            } catch {
                self.selectedDeviceID = nil
                warning = "選択した入力機器を使用できなかったため、システム既定の入力を使用します。"
            }
        }
        do {
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioRecorderError.noInput }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("awasero-\(UUID().uuidString).caf")
            let file = try AVAudioFile(forWriting: url, settings: format.settings)

            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                try? file.write(from: buffer)
                let level = Self.rmsLevel(of: buffer)
                let peak = Self.peakLevel(of: buffer)
                Task { @MainActor [weak self] in self?.observe(level: level, peak: peak) }
            }
            engine.prepare()
            try engine.start()

            recordingURL = url
            elapsed = 0
            recordingStartDate = Date()
            silenceStartDate = nil
            warning = nil
            isRecording = true
            lastError = nil

            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func tick() {
        guard let recordingStartDate, isRecording else { return }
        elapsed = Date().timeIntervalSince(recordingStartDate)
        if elapsed >= Self.maxRecordingSeconds {
            stopRecording()
            lastError = "録音時間が上限(\(Int(Self.maxRecordingSeconds / 60))分)に達したため停止しました。"
        }
    }

    private func observe(level: Float, peak: Float) {
        inputLevel = level
        guard isRecording else { return }
        if level < 0.02 {
            if silenceStartDate == nil { silenceStartDate = Date() }
        } else {
            silenceStartDate = nil
        }
        if peak >= 0.98 {
            warning = "入力が大きすぎます(クリッピング)。マイクから離れるか入力レベルを下げてください。"
        } else if let silenceStartDate, Date().timeIntervalSince(silenceStartDate) >= Self.silenceWarningThreshold {
            warning = "無音が続いています。マイクの位置や入力レベルを確認してください。"
        } else if elapsed >= Self.nearLimitWarningSeconds {
            warning = "まもなく録音時間の上限(\(Int(Self.maxRecordingSeconds / 60))分)に達します。"
        } else {
            warning = nil
        }
    }

    func stopRecording() {
        guard isRecording || meterTimer != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        inputLevel = 0
        warning = nil
        isRecording = false
        recordingStartDate = nil
        silenceStartDate = nil
    }

    func playRecording() {
        guard let recordingURL else { return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: recordingURL)
            newPlayer.delegate = self
            player = newPlayer
            newPlayer.play()
            isPlaying = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        let channel = channelData[0]
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        return sqrt(sum / Float(count))
    }

    private static func peakLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        let channel = channelData[0]
        var peak: Float = 0
        for index in 0..<count { peak = max(peak, abs(channel[index])) }
        return peak
    }

    /// Binds `inputNode`'s underlying audio unit to the CoreAudio device identified by `uid`,
    /// scoped to this app only (does not change the user's system-wide default input device).
    private static func bindInput(_ inputNode: AVAudioInputNode, toDeviceUID uid: String) throws {
        guard let audioUnit = inputNode.audioUnit else { throw AudioRecorderError.deviceUnavailable }
        var deviceID = try resolveDeviceID(forUID: uid)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw AudioRecorderError.deviceUnavailable }
    }

    private static func resolveDeviceID(forUID uid: String) throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var uidCF: CFString = uid as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &uidCF) { uidPtr -> OSStatus in
            withUnsafeMutablePointer(to: &deviceID) { devicePtr -> OSStatus in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(uidPtr),
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: UnsafeMutableRawPointer(devicePtr),
                    mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &translation)
            }
        }
        guard status == noErr, deviceID != 0 else { throw AudioRecorderError.deviceUnavailable }
        return deviceID
    }
}

private enum AudioRecorderError: LocalizedError {
    case noInput
    case deviceUnavailable

    var errorDescription: String? {
        switch self {
        case .noInput: "利用可能な入力機器が見つかりません。"
        case .deviceUnavailable: "選択した入力機器を使用できません。"
        }
    }
}
