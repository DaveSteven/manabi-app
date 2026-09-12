import SwiftUI

struct ExamPracticeView: View {
    let level: String
    @Environment(AppModel.self) private var model
    @State private var category: StudyCategory = .listening
    @State private var selectedExamID = ""
    @State private var exams: [ExamProgress] = []
    @State private var loadedCategory: StudyCategory?
    @State private var loading = true
    @State private var error: String?
    @State private var requestID = UUID()

    private var selectedExam: ExamProgress? { exams.first { $0.id == selectedExamID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(level) · 选择试卷与专项").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(StudyCategory.allCases) { choice in
                                Button { category = choice } label: {
                                    Text(choice == .vocabulary ? "词汇" : choice.title)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 16).frame(minHeight: 44)
                                        .foregroundStyle(category == choice ? .white : Sakura.ink)
                                        .background(category == choice ? Sakura.rose : Sakura.blossom.opacity(0.12), in: Capsule())
                                }.buttonStyle(.plain)
                                    .accessibilityIdentifier("examCategory_\(choice.rawValue)")
                                    .accessibilityAddTraits(category == choice ? .isSelected : [])
                            }
                        }
                    }
                    if loadedCategory == category && !exams.isEmpty {
                        HStack {
                            Label("试卷年月", systemImage: "calendar").font(.subheadline)
                            Spacer(minLength: 8)
                            Menu {
                                ForEach(exams) { exam in
                                    Button { selectedExamID = exam.id } label: {
                                        if exam.id == selectedExamID { Label(exam.dateTitle, systemImage: "checkmark") }
                                        else { Text(exam.dateTitle) }
                                    }.accessibilityIdentifier("exam_\(exam.id)")
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedExam?.dateTitle ?? "选择年月")
                                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                                }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                            }.accessibilityIdentifier("examDatePicker")
                        }
                    }
                }.studyCard(padding: 16)
                if let error { InlineError(message: error) { Task { await load() } } }
                if loading || loadedCategory != category {
                    ProgressView("正在加载试卷…").frame(maxWidth: .infinity)
                } else if let exam = selectedExam {
                    ExamTypesView(exam: exam, category: category)
                        .id("\(exam.id)-\(category.rawValue)")
                } else if error == nil {
                    ContentUnavailableView("暂无可练试卷", systemImage: "calendar", description: Text("这个等级的专项题目还在整理中。"))
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle("按试卷练习").navigationBarTitleDisplayMode(.inline)
            .task(id: category) { await load() }
            .refreshable { await load() }
    }

    private func load() async {
        let request = UUID()
        requestID = request
        loading = true
        error = nil
        let requestedCategory = category
        let api = model.api
        let userID = model.user?.id
        defer { if requestID == request { loading = false } }
        do {
            let page: ItemList<ExamProgress> = try await api.get("exam-practice/exams", query: [.init(name: "level", value: level), .init(name: "category", value: requestedCategory.rawValue)])
            guard !Task.isCancelled, requestID == request, category == requestedCategory,
                  api === model.api, userID == model.user?.id else { return }
            exams = page.items
            loadedCategory = requestedCategory
            if !exams.contains(where: { $0.id == selectedExamID }) { selectedExamID = exams.first?.id ?? "" }
        } catch {
            guard !Task.isCancelled, requestID == request, category == requestedCategory else { return }
            exams = []
            loadedCategory = requestedCategory
            self.error = AppModel.describe(error)
        }
    }
}

private struct ExamProgressLabel: View {
    let status: String
    let answered: Int
    let total: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(status == "completed" ? "已完成" : status == "not_started" ? "未开始" : "进行中",
                      systemImage: status == "completed" ? "checkmark.circle.fill" : status == "not_started" ? "circle" : "clock")
                Spacer()
                Text("\(answered) / \(total) 题").monospacedDigit()
            }.font(.caption.weight(.medium)).foregroundStyle(status == "completed" ? Sakura.rose : .secondary)
            ProgressView(value: Double(answered), total: Double(max(total, 1))).tint(Sakura.rose)
        }
    }
}

private struct ExamTypesView: View {
    let exam: ExamProgress
    let category: StudyCategory
    @Environment(AppModel.self) private var model
    @State private var types: [ExamTypeProgress] = []
    @State private var loading = true
    @State private var opening: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择题型").font(.headline)
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && types.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            if !loading && types.isEmpty && error == nil {
                ContentUnavailableView("暂无可练题型", systemImage: "book.closed")
            }
            ForEach(types) { type in
                Button { Task { await open(type) } } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(type.nameZh).font(.headline).foregroundStyle(Sakura.ink)
                                Text(type.nameJa).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if opening == type.id { ProgressView() }
                            else {
                                Text(type.status == "completed" ? "回顾" : type.practiceId == nil ? "开始" : "继续")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Sakura.rose)
                            }
                        }
                        ExamProgressLabel(status: type.status, answered: type.answered, total: type.total)
                        if type.answered > 0 {
                            Text("答对 \(type.correct) 题").font(.caption).foregroundStyle(.secondary)
                        }
                    }.studyCard()
                }.buttonStyle(.plain).disabled(opening != nil).accessibilityIdentifier("examType_\(type.id)")
            }
        }
            .task { await load() }
            .onChange(of: model.presentedPractice?.id) { _, id in if id == nil { Task { await load() } } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let api = model.api
        let userId = model.user?.id
        do {
            let page: ItemList<ExamTypeProgress> = try await api.get("exam-practice/exams/\(exam.id)/types", query: [.init(name: "category", value: category.rawValue)])
            guard api === model.api, userId == model.user?.id else { return }
            types = page.items
            error = nil
        } catch { self.error = AppModel.describe(error) }
    }

    private func open(_ type: ExamTypeProgress) async {
        guard opening == nil else { return }
        opening = type.id
        defer { opening = nil }
        let api = model.api
        let userId = model.user?.id
        do {
            let practice: Practice = try await api.post("exam-practice/exams/\(exam.id)/types/\(type.id)/practice", body: EmptyBody())
            guard api === model.api, userId == model.user?.id else { return }
            model.presentedPractice = practice
            error = nil
        } catch { self.error = AppModel.describe(error) }
    }
}
