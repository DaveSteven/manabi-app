import XCTest
import AVFoundation
import CryptoKit
@testable import Manabi

final class ManabiTests: XCTestCase {
    func testWholePaperProgressMergesCategoriesAndKeepsPartialPapers() {
        let rows = [
            ExamProgress(id: "a", title: "A", level: "N3", year: 2025, month: 7, total: 2, answered: 2, correct: 1, status: "completed"),
            ExamProgress(id: "a", title: "A", level: "N3", year: 2025, month: 7, total: 5, answered: 0, correct: 0, status: "not_started"),
            ExamProgress(id: "b", title: "B", level: "N3", year: 2024, month: 12, total: 3, answered: 3, correct: 2, status: "completed")
        ]
        let result = ExamProgress.combined(rows)
        XCTAssertEqual(result.map(\.id), ["a", "b"])
        XCTAssertEqual(result[0].total, 7)
        XCTAssertEqual(result[0].answered, 2)
        XCTAssertEqual(result[0].status, "active")
        XCTAssertEqual(result[1].status, "completed")
        XCTAssertTrue(ExamProgress.combined([]).isEmpty)
    }

    func testServerAddressValidation() throws {
        XCTAssertEqual(try APIClient.validatedURL(" http://127.0.0.1:8001/ ").absoluteString, "http://127.0.0.1:8001")
        for invalid in ["file:///tmp/data", "https://user:pass@example.com", "http://localhost/api/v1", "http://localhost?token=secret", "not-a-url"] {
            XCTAssertThrowsError(try APIClient.validatedURL(invalid))
        }
    }

    func testSnakeCaseDecodingMatchesServerContract() throws {
        let data = Data(#"{"id":"type-1","category":"reading","name_zh":"短篇理解","name_ja":"内容理解","question_count":101,"group_count":50}"#.utf8)
        let result = try APIClient.decoder().decode(QuestionType.self, from: data)
        XCTAssertEqual(result.questionCount, 101)
        XCTAssertEqual(result.studyCategory, .reading)
        XCTAssertEqual(result.nameZh, "短篇理解")
    }

    func testPracticeAnswerReplayDoesNotDoubleCount() throws {
        let json = #"""
        {"id":"practice","level":"N2","type_id":"kanji_reading","mode":"normal","status":"active","requested_count":1,"total":1,"answered":0,"correct":0,"elapsed_ms":0,"created_at":"2026-09-10T00:00:00Z","next_item_id":"item","items":[{"id":"item","position":0,"question":{"id":"question","occurrence_id":"occurrence","type_id":"kanji_reading","group_id":"group","prompt":{"text":"柱","html":"<u>柱</u>"},"material":{"id":"material","content":{"text":"","html":""},"audio_url":null,"image_url":null},"options":[{"id":"option","position":0,"content":{"text":"はしら","html":"はしら"}}],"source":{"exam_id":"exam","exam_title":"2025年7月","level":"N2","section":{"text":"説明","html":"説明"},"position":1}},"feedback":null}]}
        """#
        var practice = try APIClient.decoder().decode(Practice.self, from: Data(json.utf8))
        XCTAssertNil(practice.items[0].feedback)
        let feedback = Feedback(chosenOptionId: "option", correctOptionId: "option", isCorrect: true,
                                explanation: RichContent(text: "柱子", html: "柱子"), explanationAvailable: true,
                                translation: RichContent(text: "", html: ""), subtitles: [], answeredAt: "2026-09-10T00:00:05Z", elapsedMs: 5000)
        let answered = PracticeItem(id: "item", position: 0, question: practice.items[0].question, feedback: feedback)
        practice.apply(answered)
        practice.apply(answered)
        XCTAssertEqual(practice.answered, 1)
        XCTAssertEqual(practice.correct, 1)
        XCTAssertEqual(practice.elapsedMs, 5000)
        XCTAssertEqual(practice.status, "completed")
        XCTAssertNil(practice.nextItemId)
    }

    func testCreateRequestUsesStableSnakeCaseKey() throws {
        let body = CreatePractice(level: "N3", typeId: "short_reading", count: 5, mode: "normal", requestKey: "stable-retry-key")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any])
        XCTAssertEqual(value["request_key"] as? String, "stable-retry-key")
        XCTAssertEqual(value["type_id"] as? String, "short_reading")
    }

    @MainActor
    func testRealMP3SentenceRevisit() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("mojitest_spider/data/assets/audio/62193870-689f-48ff-8bef-1d18a2f4f7ee2025年12月N3-問題3-1番.mp3")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local source exam MP3 is unavailable")
        }
        let audio = AudioController()
        defer { audio.stop() }
        audio.load(url)
        let first = SubtitleSegment(startMs: 23150, endMs: 26000, text: "女：そうなの？どうだった？")
        let second = SubtitleSegment(startMs: 34400, endMs: 36000, text: "女：そうなんだ。")
        for target in [first, second, first, second, first] {
            audio.playSegment(target)
            for _ in 0..<200 {
                if audio.isPlaying { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(audio.isPlaying)
            XCTAssertEqual(audio.current, Double(target.startMs) / 1000, accuracy: 0.1)
            let started = Date()
            for _ in 0..<250 {
                if audio.completedPlays == 1 && !audio.isPlaying { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(audio.completedPlays, 1)
            XCTAssertFalse(audio.isPlaying)
            let expectedDuration = Double(target.endMs - target.startMs) / 1000
            // Initial decoder startup can delay playback; it must never truncate it.
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), expectedDuration - 0.1)
            XCTAssertLessThan(Date().timeIntervalSince(started), expectedDuration + 1.0)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(audio.current, Double(target.endMs) / 1000, accuracy: 0.05)
        }
    }

    @MainActor
    func testSentencePlaybackStopsAtBoundaryAndCanReplay() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 16000)
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let audio = AudioController()
        defer { audio.stop() }
        let bytes = try Data(contentsOf: url)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = MediaDownloadFixture(data: bytes)
        let cache = ResourceCache(automaticDirectory: root.appendingPathComponent("a"), persistentDirectory: root.appendingPathComponent("p"), downloader: { try await fixture.download($0) })
        let resource = MediaResource(id: "sound", kind: "audio", url: "/api/v1/assets/sound", mimeType: "audio/x-caf", byteSize: Int64(bytes.count), sha256: hash)
        let cached = try await cache.fetch(resource, baseURL: URL(string: "https://biblenotes.cc")!)
        XCTAssertEqual(cached.pathExtension, "caf")
        audio.load(cached)
        let sentence = SubtitleSegment(startMs: 100, endMs: 450, text: "test")
        audio.playSegment(sentence)
        for _ in 0..<50 {
            if audio.isPlayingSegment(sentence) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(audio.isPlayingSegment(sentence))
        for _ in 0..<80 {
            if audio.completedPlays == 1 && !audio.isPlaying { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(audio.completedPlays, 1)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertFalse(audio.isPlayingSegment(sentence))
        audio.pause()
        let loops = audio.completedPlays
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(audio.completedPlays, loops)
        XCTAssertFalse(audio.isPlaying)
        audio.playSegment(sentence)
        for _ in 0..<50 {
            if audio.completedPlays > loops && !audio.isPlaying { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(audio.completedPlays, loops + 1)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertLessThanOrEqual(audio.current, 0.5)
        let later = SubtitleSegment(startMs: 1200, endMs: 1700, text: "later")
        for target in [later, sentence, later, sentence, later] {
            audio.playSegment(target)
            try await Task.sleep(for: .milliseconds(15))
        }
        for _ in 0..<50 {
            if audio.isPlaying && audio.current >= 1.2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(audio.isPlaying)
        XCTAssertGreaterThanOrEqual(audio.current, 1.2)
        XCTAssertLessThan(audio.current, 1.7)
        for _ in 0..<40 {
            if audio.completedPlays == 1 && !audio.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(audio.completedPlays, 1)
        XCTAssertFalse(audio.isPlaying)
        audio.playSegment(sentence)
        for _ in 0..<40 {
            if audio.completedPlays == 1 && !audio.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(audio.completedPlays, 1)
        XCTAssertLessThanOrEqual(audio.current, 0.5)
        // Play each sentence to completion, then walk backwards repeatedly.
        // Check actual progress and wall time, not just the selected sentence ID.
        for target in [later, sentence, later, sentence] {
            let started = Date()
            audio.playSegment(target)
            for _ in 0..<100 {
                if audio.isPlaying { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(audio.isPlaying)
            XCTAssertEqual(audio.current, Double(target.startMs) / 1000, accuracy: 0.1)
            for _ in 0..<100 {
                if audio.completedPlays == 1 && !audio.isPlaying { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(audio.completedPlays, 1)
            XCTAssertFalse(audio.isPlaying)
            // Allow the periodic observer to report the final player position.
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(audio.current, Double(target.endMs) / 1000, accuracy: 0.05)
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started),
                                      Double(target.endMs - target.startMs) / 1000 - 0.05)
        }
        audio.playFrom(Double(sentence.startMs) / 1000)
        for _ in 0..<30 {
            if audio.current > 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(audio.current, 1)
        XCTAssertFalse(audio.isPlayingSegment(sentence))
    }

}

private actor MediaDownloadFixture {
    var calls = 0
    let data: Data
    let failFirst: Bool
    init(data: Data, failFirst: Bool = false) { self.data = data; self.failFirst = failFirst }
    func download(_ url: URL) async throws -> (URL, HTTPURLResponse) {
        calls += 1
        if failFirst && calls == 1 { throw URLError(.networkConnectionLost) }
        try await Task.sleep(for: .milliseconds(30))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        return (file, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

extension ManabiTests {
    private var sampleResource: MediaResource {
        MediaResource(id: "sample", kind: "audio", url: "/api/v1/assets/sample", mimeType: "audio/mpeg", byteSize: 3,
                      sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testResourceCacheDeduplicatesPersistsAndRepairs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let automatic = root.appendingPathComponent("automatic")
        let persistent = root.appendingPathComponent("persistent")
        let fixture = MediaDownloadFixture(data: Data("abc".utf8), failFirst: true)
        let cache = ResourceCache(automaticDirectory: automatic, persistentDirectory: persistent, downloader: { try await fixture.download($0) })
        let base = URL(string: "https://biblenotes.cc")!
        let resource = sampleResource
        async let first = cache.fetch(resource, baseURL: base)
        async let second = cache.fetch(resource, baseURL: base)
        let urls = try await [first, second]
        XCTAssertEqual(urls[0], urls[1])
        let calls = await fixture.calls
        XCTAssertEqual(calls, 2, "One shared download plus one transient retry")
        let usage = try await cache.usage()
        XCTAssertEqual(usage.totalBytes, 3)
        let cached = try await cache.fetch(resource, baseURL: base)
        XCTAssertEqual(cached.deletingLastPathComponent().path, automatic.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
        let restarted = ResourceCache(automaticDirectory: automatic, persistentDirectory: persistent, downloader: { try await fixture.download($0) })
        let restored = try await restarted.localURL(for: resource, baseURL: base)
        XCTAssertEqual(restored, cached)
        let offline = try await restarted.existingURL(for: base.appendingPathComponent("api/v1/assets/sample"), baseURL: base)
        XCTAssertEqual(offline, cached)
        try Data("bad".utf8).write(to: cached)
        let corrupted = try await restarted.localURL(for: resource, baseURL: base)
        XCTAssertNil(corrupted)
        let repaired = try await restarted.fetch(resource, baseURL: base)
        XCTAssertEqual(repaired, cached, "Repair reuses the same cache path")
        XCTAssertEqual(try Data(contentsOf: repaired), Data("abc".utf8))
        let otherEnvironment = try await restarted.localURL(for: resource, baseURL: URL(string: "http://localhost:8001")!)
        XCTAssertNil(otherEnvironment)
        let updated = MediaResource(id: resource.id, kind: resource.kind, url: resource.url, mimeType: resource.mimeType,
                                    byteSize: 3, sha256: String(repeating: "0", count: 64))
        let otherVersion = try await restarted.localURL(for: updated, baseURL: base)
        XCTAssertNil(otherVersion)
    }

    func testResourceCacheRejectsInvalidDownloadsAndCanRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = MediaDownloadFixture(data: Data("wrong".utf8))
        let cache = ResourceCache(automaticDirectory: root.appendingPathComponent("a"), persistentDirectory: root.appendingPathComponent("p"), downloader: { try await fixture.download($0) })
        let base = URL(string: "https://biblenotes.cc")!
        for _ in 0..<2 {
            do { _ = try await cache.fetch(sampleResource, baseURL: base); XCTFail("Invalid file accepted") }
            catch ResourceCacheError.checksumMismatch { }
        }
        let calls = await fixture.calls
        XCTAssertEqual(calls, 2, "Failed tasks must not poison later retries")
        let usage = try await cache.usage()
        XCTAssertEqual(usage.totalBytes, 0)
        let invalid = MediaResource(id: "sample", kind: "audio", url: "https://other.example/api/v1/assets/sample", mimeType: "audio/mpeg", byteSize: 3, sha256: sampleResource.sha256)
        do { _ = try await cache.fetch(invalid, baseURL: base); XCTFail("Cross-environment URL accepted") }
        catch ResourceCacheError.invalidResource { }
    }
}

private actor SchedulingDownloads {
    var started: [String] = []
    var cancelled: [String] = []
    var active = 0
    var peak = 0
    func download(_ url: URL) async throws -> (URL, HTTPURLResponse) {
        let id = url.lastPathComponent
        started.append(id); active += 1; peak = max(peak, active)
        defer { active -= 1 }
        do { try await Task.sleep(for: .milliseconds(400)) }
        catch { cancelled.append(id); throw error }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: file)
        return (file, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

extension ManabiTests {
    private func media(_ id: String) -> MediaResource {
        MediaResource(id: id, kind: "audio", url: "/api/v1/assets/\(id)", mimeType: "audio/mpeg", byteSize: 3, sha256: sampleResource.sha256)
    }

    func testPrefetchSchedulingCancellationAndForegroundPromotion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = SchedulingDownloads()
        let cache = ResourceCache(automaticDirectory: root.appendingPathComponent("a"), persistentDirectory: root.appendingPathComponent("p"), downloader: { try await fixture.download($0) })
        let base = URL(string: "https://biblenotes.cc")!
        let scope = UUID()
        let a = media("a"), b = media("b"), c = media("c")
        let first = Task { try await cache.fetch(a, baseURL: base, prefetchScope: scope) }
        for _ in 0..<100 {
            if await fixture.started.contains("a") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let queued = Task { try await cache.fetch(b, baseURL: base, prefetchScope: scope) }
        try await Task.sleep(for: .milliseconds(30))
        let visible = Task { try await cache.fetch(c, baseURL: base) }
        for _ in 0..<100 {
            if await fixture.started.contains("c") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await cache.cancelPrefetch(scope: scope)
        _ = try await visible.value
        _ = await first.result; _ = await queued.result
        let started = await fixture.started
        XCTAssertEqual(started, ["a", "c"])
        let peak = await fixture.peak
        XCTAssertEqual(peak, 2)
        let cancelled = await fixture.cancelled
        XCTAssertTrue(cancelled.contains("a"))

        let promotedScope = UUID()
        let d = media("d")
        let speculative = Task { try await cache.fetch(d, baseURL: base, prefetchScope: promotedScope) }
        for _ in 0..<100 {
            if await fixture.started.contains("d") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let promoted = Task { try await cache.fetch(d, baseURL: base) }
        try await Task.sleep(for: .milliseconds(30))
        await cache.cancelPrefetch(scope: promotedScope)
        let paths = try await [speculative.value, promoted.value]
        XCTAssertEqual(paths[0], paths[1])
        let finalStarts = await fixture.started
        XCTAssertEqual(finalStarts.filter { $0 == "d" }.count, 1)
    }


}

extension ManabiTests {
    func testCancellingOneDownloadKeepsAnotherSharedDownloadAlive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = SchedulingDownloads()
        let cache = ResourceCache(automaticDirectory: root.appendingPathComponent("a"), persistentDirectory: root.appendingPathComponent("p"), downloader: { try await fixture.download($0) })
        let base = URL(string: "https://biblenotes.cc")!
        let resource = media("shared-download")
        let one = UUID(), two = UUID()
        let first = Task { try await cache.fetch(resource, baseURL: base, prefetchScope: one) }
        for _ in 0..<100 {
            if await fixture.started.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let second = Task { try await cache.fetch(resource, baseURL: base, prefetchScope: two) }
        try await Task.sleep(for: .milliseconds(30))
        first.cancel()
        await cache.cancelPrefetch(scope: one)
        let file = try await second.value
        _ = await first.result
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let starts = await fixture.started
        let cancellations = await fixture.cancelled
        XCTAssertEqual(starts.count, 1)
        XCTAssertTrue(cancellations.isEmpty)
    }
}

extension ManabiTests {
    func testClearingCachePreservesCurrentlyUsedMedia() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = MediaDownloadFixture(data: Data("abc".utf8))
        let cache = ResourceCache(automaticDirectory: root.appendingPathComponent("a"), persistentDirectory: root.appendingPathComponent("p"), downloader: { try await fixture.download($0) })
        let base = URL(string: "https://biblenotes.cc")!
        let scope = UUID()
        let path = try await cache.fetch(media("playing"), baseURL: base, prefetchScope: scope)
        let unused = try await cache.fetch(media("unused"), baseURL: base, prefetchScope: scope)
        await cache.protect(scope: scope, baseURL: base, paths: ["/api/v1/assets/playing"])
        try await cache.clearAutomatic()
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unused.path))
        await cache.releaseProtection(scope: scope)
        try await cache.clearAutomatic()
        let usage = try await cache.usage()
        XCTAssertEqual(usage.totalBytes, 0)
    }

    func testLegacyDownloadsBecomeClearableAutomaticCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let automatic = root.appendingPathComponent("a"), persistent = root.appendingPathComponent("p")
        let fixture = MediaDownloadFixture(data: Data("abc".utf8))
        let cache = ResourceCache(automaticDirectory: automatic, persistentDirectory: persistent, downloader: { try await fixture.download($0) })
        let base = URL(string: "https://biblenotes.cc")!
        let local = try await cache.fetch(sampleResource, baseURL: base, prefetchScope: UUID())
        let old = persistent.appendingPathComponent(local.lastPathComponent)
        try FileManager.default.moveItem(at: local, to: old)
        let index = persistent.appendingPathComponent("index.json")
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: [String: Any]])
        let key = try XCTUnwrap(rows.keys.first)
        rows[key]?["owners"] = ["old-paper-download"]
        try JSONSerialization.data(withJSONObject: rows).write(to: index)
        let restarted = ResourceCache(automaticDirectory: automatic, persistentDirectory: persistent)
        let restored = try await restarted.localURL(for: sampleResource, baseURL: base)
        XCTAssertEqual(restored, local)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        try await restarted.clearAutomatic()
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
    }
}

extension ManabiTests {
    func testCacheWriteFailureCanRecoverWithoutPublishingBrokenEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let automatic = root.appendingPathComponent("a")
        let fixture = MediaDownloadFixture(data: Data("abc".utf8))
        let cache = ResourceCache(automaticDirectory: automatic, persistentDirectory: root.appendingPathComponent("p"), downloader: { try await fixture.download($0) })
        _ = try await cache.usage()
        try FileManager.default.removeItem(at: automatic)
        try Data("unavailable directory".utf8).write(to: automatic)
        let base = URL(string: "https://biblenotes.cc")!
        do { _ = try await cache.fetch(sampleResource, baseURL: base); XCTFail("Write should fail") }
        catch { XCTAssertFalse(error is CancellationError) }
        let missing = try await cache.localURL(for: sampleResource, baseURL: base)
        XCTAssertNil(missing)
        try FileManager.default.removeItem(at: automatic)
        try FileManager.default.createDirectory(at: automatic, withIntermediateDirectories: true)
        let recovered = try await cache.fetch(sampleResource, baseURL: base)
        XCTAssertEqual(try Data(contentsOf: recovered), Data("abc".utf8))
    }
}
