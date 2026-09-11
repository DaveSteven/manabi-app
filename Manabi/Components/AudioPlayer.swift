import SwiftUI
import AVFoundation
import Observation

@MainActor @Observable
final class AudioController {
    private var player: AVPlayer?
    private var observer: Any?
    private var statusObserver: NSKeyValueObservation?
    private var loadedURL: URL?
    private var endObserver: NSObjectProtocol?
    private var segment: SubtitleSegment?
    private var seekVersion = 0
    private var wantsPlayback = false
    var completedLoops = 0
    var repeatSegment = true
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
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.loadedURL == url else { return }
                self.isPlaying = false
                if self.segment != nil && self.wantsPlayback { self.completedLoops += 1 }
                if let segment = self.segment, self.repeatSegment, self.wantsPlayback { self.playSegment(segment) }
            }
        }
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
            if let segment { playSegment(segment); return }
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

    func pause() { wantsPlayback = false; seekVersion += 1; player?.pause(); isPlaying = false }

    func playSegment(_ segment: SubtitleSegment) {
        guard segment.endMs > segment.startMs, let player else { return }
        pause()
        if self.segment?.id != segment.id { completedLoops = 0 }
        self.segment = segment
        wantsPlayback = true
        let version = seekVersion
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: Double(segment.endMs) / 1000, preferredTimescale: 1000)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { self.error = "暂时无法启用音频播放，请重试。"; return }
        current = Double(segment.startMs) / 1000
        player.seek(to: CMTime(seconds: current, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            Task { @MainActor [weak self] in
                guard let self, completed, self.seekVersion == version else { return }
                self.player?.play()
                self.isPlaying = true
            }
        }
    }

    func stop() {
        pause()
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
        statusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        segment = nil
        completedLoops = 0
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


struct IntensiveListeningView: View {
    let practiceId: String
    let itemId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var audio = AudioController()
    @State private var lesson: IntensiveListening?
    @State private var index = 0
    @State private var revealed = false
    @State private var loading = true
    @State private var error: String?

    private var segment: SubtitleSegment? {
        guard let lesson, lesson.segments.indices.contains(index) else { return nil }
        return lesson.segments[index]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("先听见，再看见。").font(.largeTitle.bold())
                    Text("听清这一句，再由你决定什么时候继续。").font(.subheadline).foregroundStyle(.secondary)
                    if loading { ProgressView("正在准备逐句音频…").frame(maxWidth: .infinity) }
                    if let error { InlineError(message: error) { Task { await load() } } }
                    if let segment, let lesson {
                        Text("第 \(index + 1) / \(lesson.segments.count) 句")
                            .font(.headline).foregroundStyle(Sakura.rose).accessibilityIdentifier("sentencePosition")
                        VStack(alignment: .leading, spacing: 22) {
                            HStack { Label("日文原文", systemImage: "text.alignleft"); Spacer(); Image(systemName: revealed ? "eye" : "eye.slash") }
                                .font(.caption).foregroundStyle(.secondary)
                            Text(segment.text).font(.title2).lineSpacing(10)
                                .blur(radius: revealed ? 0 : 9)
                                .accessibilityHidden(!revealed)
                                .textSelection(.disabled)
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
                                .overlay {
                                    if !revealed { Text("原文已隐藏").font(.subheadline.weight(.medium)).padding(12).background(.regularMaterial, in: Capsule()).accessibilityHidden(true) }
                                }
                            Button(revealed ? "隐藏原文" : "显示原文") { revealed.toggle() }
                                .font(.subheadline.weight(.semibold)).accessibilityIdentifier("toggleTranscript")
                        }.studyCard()
                        Text("已听 \(audio.completedLoops) 遍").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Toggle("单句循环", isOn: $audio.repeatSegment).tint(Sakura.rose)
                        Text(audio.repeatSegment ? "播放完会重复这一句，不会自动跳到下一句。" : "播放完这一句后暂停，点击播放可以再听一次。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = audio.error {
                            InlineError(message: error) {
                                guard let url = model.mediaURL(lesson.audioUrl) else { return }
                                audio.stop(); audio.load(url)
                            }
                        }
                    } else if !loading && error == nil {
                        ContentUnavailableView("这段音频暂无逐句时间标记", systemImage: "waveform", description: Text("可以返回听力练习，继续听完整音频。"))
                    }
                }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background(SakuraBackground())
            .navigationTitle("精听练习").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回整段") { audio.stop(); dismiss() }.accessibilityIdentifier("closeIntensiveListening") } }
            .safeAreaInset(edge: .bottom) {
                if let segment, let lesson {
                    VStack(spacing: 14) {
                        ProgressView(value: min(max((audio.current * 1000 - Double(segment.startMs)) / Double(segment.endMs - segment.startMs), 0), 1))
                            .tint(Sakura.rose).accessibilityLabel("当前句播放进度")
                        HStack(spacing: 24) {
                            Button { move(-1) } label: { Label("上一句", systemImage: "backward.end.fill").labelStyle(.titleAndIcon).frame(minHeight: 48) }
                                .disabled(index == 0).accessibilityIdentifier("previousSentence")
                            Spacer(minLength: 0)
                            Button {
                                if audio.isPlaying { audio.pause() } else { audio.playSegment(segment) }
                            } label: {
                                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2).frame(width: 64, height: 64).foregroundStyle(.white).background(Sakura.rose, in: Circle())
                            }.accessibilityLabel(audio.isPlaying ? "暂停当前句" : "播放当前句").accessibilityIdentifier("playSentence")
                            Spacer(minLength: 0)
                            Button { move(1) } label: { Label("下一句", systemImage: "forward.end.fill").labelStyle(.titleAndIcon).frame(minHeight: 48) }
                                .disabled(index == lesson.segments.count - 1).accessibilityIdentifier("nextSentence")
                        }.font(.subheadline.weight(.semibold)).buttonStyle(.plain)
                    }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
        }
        .task { await load() }
        .onDisappear { audio.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { audio.pause() } }
    }

    private func move(_ delta: Int) {
        guard let lesson, lesson.segments.indices.contains(index + delta) else { return }
        audio.pause()
        index += delta
        revealed = false
        audio.playSegment(lesson.segments[index])
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let response: IntensiveListening = try await model.api.get("practices/\(practiceId)/items/\(itemId)/listening")
            guard !Task.isCancelled else { return }
            lesson = response
            index = 0
            revealed = false
            if let url = model.mediaURL(response.audioUrl) { audio.load(url) }
        } catch { self.error = AppModel.describe(error) }
    }
}
