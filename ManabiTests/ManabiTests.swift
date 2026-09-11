import XCTest
@testable import Manabi

final class ManabiTests: XCTestCase {
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
}
