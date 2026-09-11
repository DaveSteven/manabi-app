import SwiftUI
import AVFoundation
import Observation

@MainActor @Observable
final class AudioController {
    private var player: AVPlayer?
    private var observer: Any?
    private var statusObserver: NSKeyValueObservation?
    private var loadedURL: URL?
    var isPlaying = false
    var current: Double = 0
    var duration: Double = 0
    var error: String?

    func load(_ url: URL) {
        guard url != loadedURL else { return }
        stop()
        loadedURL = url
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor [weak self] in
                guard self?.loadedURL == url else { return }
                if failed { self?.error = "音频暂时无法播放，请检查网络后重试。"; self?.isPlaying = false }
            }
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self, self.loadedURL == url else { return }
                self.current = seconds.isFinite ? seconds : 0
                let total = self.player?.currentItem?.duration.seconds ?? 0
                self.duration = total.isFinite ? total : 0
                self.isPlaying = (self.player?.rate ?? 0) > 0
            }
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { pause() }
        else {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                if duration > 0 && current >= duration - 0.3 { seek(0) }
                player.play()
                isPlaying = true
            } catch { self.error = "暂时无法启用音频播放，请重试。" }
        }
    }

    func seek(_ seconds: Double) {
        let value = max(0, min(seconds, duration > 0 ? duration : seconds))
        player?.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        current = value
    }

    func pause() { player?.pause(); isPlaying = false }

    func stop() {
        pause()
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
        statusObserver = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        loadedURL = nil
        current = 0
        duration = 0
        error = nil
    }

    func replay(_ segment: SubtitleSegment) { seek(Double(segment.startMs) / 1000); if !isPlaying { toggle() } }
}

struct ListeningPlayer: View {
    let url: URL
    let controller: AudioController
    @State private var scrub: Double = 0
    @State private var scrubbing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 13) {
                Image(systemName: "waveform").foregroundStyle(Sakura.rose)
                Text("听力音频").font(.subheadline.weight(.semibold))
                Spacer()
                Text(controller.duration > 0 ? time(controller.duration) : "准备播放").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Button { controller.seek(controller.current - 10) } label: { Image(systemName: "gobackward.10").font(.title3) }.accessibilityLabel("后退十秒")
                Button { controller.toggle() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 48, height: 48).background(Sakura.rose, in: Circle()).foregroundStyle(.white)
                }.accessibilityLabel(controller.isPlaying ? "暂停音频" : "播放音频").accessibilityIdentifier("audioPlay")
                VStack(spacing: 0) {
                    Slider(value: Binding(get: { scrubbing ? scrub : min(controller.current, max(controller.duration, 1)) }, set: { scrub = $0 }), in: 0...max(controller.duration, 1), onEditingChanged: { editing in
                        scrubbing = editing
                        if !editing { controller.seek(scrub) }
                    }).disabled(controller.duration <= 0).accessibilityLabel("音频进度")
                    Text(time(controller.current)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error = controller.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("重新加载") { controller.stop(); controller.load(url) }.font(.caption.weight(.semibold))
            }
        }.padding(18).sakuraGlass().task(id: url) { controller.load(url) }
    }

    private func time(_ value: Double) -> String {
        let seconds = Int(max(value, 0))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
