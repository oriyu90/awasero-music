import AppKit
import Foundation

@MainActor
final class Metronome: ObservableObject {
    @Published var bpm = 120.0
    @Published var beatsPerBar = 4
    @Published private(set) var isRunning = false
    @Published private(set) var currentBeat = 0
    private var timer: Timer?

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
}
