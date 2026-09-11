import Foundation

struct RichContent: Codable, Sendable, Equatable {
    let text: String
    let html: String
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct Profile: Codable, Sendable {
    let id: String
    var username: String?
    var level: String
    var isGuest: Bool
}

struct AuthResponse: Decodable, Sendable {
    let accessToken: String
    let expiresAt: String
    let user: Profile
}

struct ItemList<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
}

struct Page<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let total: Int
    let limit: Int
    let offset: Int
}

struct LevelInfo: Decodable, Identifiable, Sendable {
    var id: String { level }
    let level: String
    let questionCount: Int
    let examCount: Int
}

enum StudyCategory: String, CaseIterable, Identifiable, Sendable {
    case vocabulary, grammar, reading, listening
    var id: String { rawValue }
    var title: String {
        switch self { case .vocabulary: "文字・词汇"; case .grammar: "语法"; case .reading: "阅读"; case .listening: "听力" }
    }
    var japanese: String {
        switch self { case .vocabulary: "文字・語彙"; case .grammar: "文法"; case .reading: "読解"; case .listening: "聴解" }
    }
    var symbol: String {
        switch self { case .vocabulary: "character.book.closed.fill"; case .grammar: "textformat.abc"; case .reading: "book.pages.fill"; case .listening: "headphones" }
    }
    var caption: String {
        switch self {
        case .vocabulary: "从一个词开始，慢慢积累。"
        case .grammar: "读懂句子之间的细微差别。"
        case .reading: "静下心来，读懂一段日文。"
        case .listening: "让耳朵渐渐熟悉日语。"
        }
    }
}

struct QuestionType: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    let category: String
    let nameZh: String
    let nameJa: String
    let questionCount: Int
    let groupCount: Int
    var studyCategory: StudyCategory { StudyCategory(rawValue: category) ?? .vocabulary }
}

struct PracticeSummary: Decodable, Identifiable, Sendable {
    let id: String
    let level: String
    let typeId: String
    let mode: String
    let status: String
    let total: Int
    let answered: Int
    let correct: Int
    let elapsedMs: Int
    let createdAt: String
    let nextItemId: String?
    var progress: Double { total == 0 ? 0 : Double(answered) / Double(total) }
}

struct Practice: Decodable, Identifiable, Sendable {
    let id: String
    let level: String
    let typeId: String
    let mode: String
    var status: String
    let requestedCount: Int
    let total: Int
    var answered: Int
    var correct: Int
    var elapsedMs: Int
    let createdAt: String
    var nextItemId: String?
    var items: [PracticeItem]

    mutating func apply(_ item: PracticeItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        answered = items.filter { $0.feedback != nil }.count
        correct = items.filter { $0.feedback?.isCorrect == true }.count
        elapsedMs = items.reduce(0) { $0 + ($1.feedback?.elapsedMs ?? 0) }
        nextItemId = items.first(where: { $0.feedback == nil })?.id
        if answered == total { status = "completed" }
    }
}

struct PracticeItem: Decodable, Identifiable, Sendable {
    let id: String
    let position: Int
    let question: StudyQuestion
    let feedback: Feedback?
}

struct StudyQuestion: Decodable, Identifiable, Sendable {
    let id: String
    let occurrenceId: String
    let typeId: String
    let groupId: String
    let prompt: RichContent
    let material: StudyMaterial
    let options: [StudyOption]
    let source: QuestionSource
}

struct StudyMaterial: Decodable, Identifiable, Sendable {
    let id: String
    let content: RichContent
    let audioUrl: String?
    let imageUrl: String?
}

struct StudyOption: Decodable, Identifiable, Sendable {
    let id: String
    let position: Int
    let content: RichContent
}

struct QuestionSource: Decodable, Sendable {
    let examId: String
    let examTitle: String
    let level: String
    let section: RichContent
    let position: Int
}

struct Feedback: Decodable, Sendable {
    let chosenOptionId: String
    let correctOptionId: String
    let isCorrect: Bool
    let explanation: RichContent
    let explanationAvailable: Bool
    let translation: RichContent
    let subtitles: [SubtitleSegment]
    let answeredAt: String
    let elapsedMs: Int
}

struct SubtitleSegment: Decodable, Identifiable, Sendable {
    var id: String { "\(startMs)-\(endMs)-\(text)" }
    let startMs: Int
    let endMs: Int
    let text: String
}

struct WrongQuestion: Decodable, Identifiable, Sendable {
    var id: String { occurrenceId }
    let occurrenceId: String
    let level: String
    let typeId: String?
    let prompt: RichContent
    let wrongCount: Int
    let resolved: Bool
    let available: Bool
    let updatedAt: String
}

struct StudyStat: Decodable, Sendable {
    let level: String
    let typeId: String
    let answered: Int
    let correct: Int
    let accuracy: Double
    let elapsedMs: Int
}

struct CreatePractice: Codable, Sendable, Equatable {
    let level: String
    let typeId: String
    let count: Int
    let mode: String
    let requestKey: String
}

struct AnswerBody: Encodable, Sendable {
    let optionId: String
    let elapsedMs: Int
}

struct Credentials: Encodable, Sendable {
    let username: String
    let password: String
}

struct LevelBody: Encodable, Sendable { let level: String }
struct EmptyBody: Codable, Sendable {}
