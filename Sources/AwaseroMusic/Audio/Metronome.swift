import AppKit
import Foundation

@MainActor
final class Metronome: ObservableObject {
    @Published var bpm = 120.0
    @Published var beatsPerBar = 4
    @Published private(set) var isRunning = false
    @Published private(set) var currentBeat = 0
    @Published private(set) var tapCount = 0
    private var timer: Timer?
    private var tapTimestamps: [Date] = []
    private static let tapTimeoutSeconds: TimeInterval = 2.0
    private static let maxTrackedTaps = 8

    func start() {
        stop()
        isRunning = true
        currentBeat = 0
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 60 / max(30, bpm), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentBeat = 0
    }

    func restartIfRunning() {
        if isRunning { start() }
    }

    private func tick() {
        if currentBeat == 0 {
            NSSound(named: "Tink")?.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
        currentBeat = (currentBeat + 1) % max(1, beatsPerBar)
    }

    /// Records one tap and, once at least two taps have landed, sets `bpm` to the average
    /// interval between recent taps. A gap of more than `tapTimeoutSeconds` starts a fresh streak.
    func tapTempo() {
        let now = Date()
        if let last = tapTimestamps.last, now.timeIntervalSince(last) > Self.tapTimeoutSeconds {
            tapTimestamps.removeAll()
            tapCount = 0
        }
        tapTimestamps.append(now)
        tapCount += 1
        // Only the most recent taps feed the average, so the tempo tracks tempo drift;
        // `tapCount` itself keeps counting the whole streak so the on-screen counter doesn't
        // look stuck once more than `maxTrackedTaps` taps have landed.
        if tapTimestamps.count > Self.maxTrackedTaps {
            tapTimestamps.removeFirst(tapTimestamps.count - Self.maxTrackedTaps)
        }
        guard tapTimestamps.count >= 2 else { return }
        let intervals = zip(tapTimestamps, tapTimestamps.dropFirst()).map { $1.timeIntervalSince($0) }
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard averageInterval > 0 else { return }
        bpm = max(40, min(240, (60 / averageInterval).rounded()))
    }

    func resetTapTempo() {
        tapTimestamps.removeAll()
        tapCount = 0
    }
}
