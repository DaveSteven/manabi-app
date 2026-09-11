import SwiftUI

struct ExamCategoriesView: View {
    let level: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("从一份真题开始").font(.largeTitle.bold())
                Text("\(level) · 先选专项，再选试卷年月。每个题型的进度都会为你保留。")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(StudyCategory.allCases) { category in
                    NavigationLink {
                        ExamListView(level: level, category: category)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: category.symbol).font(.title2).foregroundStyle(Sakura.rose).frame(width: 42)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(category.title).font(.headline).foregroundStyle(Sakura.ink)
                                Text(category.caption).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Sakura.rose)
                        }.studyCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("examCategory_\(category.rawValue)")
                }
            }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle("按试卷练习").navigationBarTitleDisplayMode(.inline)
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

struct ExamListView: View {
    let level: String
    let category: StudyCategory
    @Environment(AppModel.self) private var model
    @State private var exams: [ExamProgress] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("选择试卷年月").font(.title.bold())
                Text("\(level) · \(category.title)").font(.subheadline).foregroundStyle(.secondary)
                if let error { InlineError(message: error) { Task { await load() } } }
                if loading && exams.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                if !loading && exams.isEmpty && error == nil {
                    ContentUnavailableView("暂无可练试卷", systemImage: "calendar", description: Text("这个等级的专项题目还在整理中。"))
                }
                ForEach(exams) { exam in
                    NavigationLink {
                        ExamTypesView(exam: exam, category: category)
                    } label: {
                        VStack(alignment: .leading, spacing: 17) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exam.dateTitle).font(.title3.bold()).foregroundStyle(Sakura.ink)
                                    Text("\(exam.level) · \(category.title)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Sakura.rose)
                            }
                            ExamProgressLabel(status: exam.status, answered: exam.answered, total: exam.total)
                        }.studyCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("exam_\(exam.id)")
                }
            }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle(category.title).navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: model.presentedPractice?.id) { _, id in if id == nil { Task { await load() } } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let api = model.api
        let userId = model.user?.id
        do {
            let page: ItemList<ExamProgress> = try await api.get("exam-practice/exams", query: [.init(name: "level", value: level), .init(name: "category", value: category.rawValue)])
            guard api === model.api, userId == model.user?.id else { return }
            exams = page.items
            error = nil
        } catch { self.error = AppModel.describe(error) }
    }
}

struct ExamTypesView: View {
    let exam: ExamProgress
    let category: StudyCategory
    @Environment(AppModel.self) private var model
    @State private var types: [ExamTypeProgress] = []
    @State private var loading = true
    @State private var opening: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(exam.dateTitle).font(.largeTitle.bold())
                Text("\(exam.level) · \(category.title)").font(.subheadline).foregroundStyle(.secondary)
                Text("选择题型，按这份试卷的顺序练习。未完成的题型可以随时接着练。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let error { InlineError(message: error) { Task { await load() } } }
                if loading && types.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                if !loading && types.isEmpty && error == nil {
                    ContentUnavailableView("暂无可练题型", systemImage: "book.closed")
                }
                ForEach(types) { type in
                    Button { Task { await open(type) } } label: {
                        VStack(alignment: .leading, spacing: 16) {
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
            }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle("选择题型").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
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
