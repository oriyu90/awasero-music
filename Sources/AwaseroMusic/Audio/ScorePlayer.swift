import AVFoundation
import Foundation

@MainActor
final class ScorePlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func play(score: ScoreDocument) {
        stop()
        do {
            let data = try WaveExporter.data(for: score)
            player = try AVAudioPlayer(data: data)
            player?.play()
            isPlaying = true
            let duration = player?.duration ?? 0
            Task {
                try? await Task.sleep(for: .seconds(duration))
                if self.player?.isPlaying == false { self.isPlaying = false }
            }
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}
