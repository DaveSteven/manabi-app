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
    func testSentencePlaybackLoopsAndStopsAtBoundary() async throws {
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
        for _ in 0..<80 {
            if audio.completedLoops >= 2 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThanOrEqual(audio.completedLoops, 2)
        audio.pause()
        let loops = audio.completedLoops
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(audio.completedLoops, loops)
        XCTAssertFalse(audio.isPlaying)
        audio.repeatSegment = false
        audio.playSegment(sentence)
        for _ in 0..<50 {
            if audio.completedLoops > loops && !audio.isPlaying { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(audio.completedLoops, loops + 1)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertLessThanOrEqual(audio.current, 0.5)
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
        XCTAssertEqual(usage.automaticBytes, 3)
        let pinned = try await cache.fetch(resource, baseURL: base, owner: "user/paper")
        XCTAssertEqual(pinned.deletingLastPathComponent().path, persistent.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path))
        let restarted = ResourceCache(automaticDirectory: automatic, persistentDirectory: persistent, downloader: { try await fixture.download($0) })
        let restored = try await restarted.localURL(for: resource, baseURL: base)
        XCTAssertEqual(restored, pinned)
        let offline = try await restarted.existingURL(for: base.appendingPathComponent("api/v1/assets/sample"), baseURL: base)
        XCTAssertEqual(offline, pinned)
        try Data("bad".utf8).write(to: pinned)
        let corrupted = try await restarted.localURL(for: resource, baseURL: base)
        XCTAssertNil(corrupted)
        let repaired = try await restarted.fetch(resource, baseURL: base)
        XCTAssertEqual(repaired, pinned, "Repair preserves download ownership")
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
        XCTAssertEqual(usage.automaticBytes + usage.downloadedBytes, 0)
        let invalid = MediaResource(id: "sample", kind: "audio", url: "https://other.example/api/v1/assets/sample", mimeType: "audio/mpeg", byteSize: 3, sha256: sampleResource.sha256)
        do { _ = try await cache.fetch(invalid, baseURL: base); XCTFail("Cross-environment URL accepted") }
        catch ResourceCacheError.invalidResource { }
    }
}
