import SwiftUI

struct ExamPracticeView: View {
    let level: String
    @Environment(AppModel.self) private var model
    @State private var exams: [ExamProgress] = []
    @State private var loading = true
    @State private var error: String?
    @State private var requestID = UUID()

    private var years: [Int] { Set(exams.map { $0.year ?? 0 }).sorted(by: >) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("\(level) · 历年真题").font(.title2.bold())
                Text("先选试卷，再自由选择想练的模块。").font(.subheadline).foregroundStyle(.secondary)
                if let error { InlineError(message: error) { Task { await load() } } }
                if loading && exams.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                if !loading && exams.isEmpty && error == nil {
                    ContentUnavailableView("暂无可练试卷", systemImage: "calendar")
                }
                ForEach(years, id: \.self) { year in
                    Text(year == 0 ? "其他试卷" : "\(year) 年")
                        .font(.headline).padding(.top, 8)
                    ForEach(exams.filter { ($0.year ?? 0) == year }) { exam in
                        NavigationLink {
                            ExamDirectoryView(exam: exam)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(exam.dateTitle).font(.headline).foregroundStyle(Sakura.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Sakura.rose)
                                }
                                ExamProgressLabel(status: exam.status, answered: exam.answered, total: exam.total)
                            }.studyCard(padding: 16)
                        }.buttonStyle(.plain).accessibilityIdentifier("exam_\(exam.id)")
                    }
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle("按试卷练习").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: model.presentedPractice?.id) { _, id in if id == nil { Task { await load() } } }
    }

    private func load() async {
        let request = UUID()
        requestID = request
        loading = true
        let api = model.api
        let userID = model.user?.id
        let selectedLevel = level
        defer { if requestID == request { loading = false } }
        do {
            let rows = try await withThrowingTaskGroup(of: [ExamProgress].self) { group in
                for category in StudyCategory.allCases {
                    group.addTask {
                        let page: ItemList<ExamProgress> = try await api.get("exam-practice/exams", query: [.init(name: "level", value: selectedLevel), .init(name: "category", value: category.rawValue)])
                        return page.items
                    }
                }
                var rows: [ExamProgress] = []
                for try await page in group { rows += page }
                return rows
            }
            guard !Task.isCancelled, requestID == request, api === model.api, userID == model.user?.id else { return }
            exams = ExamProgress.combined(rows)
            error = nil
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            self.error = AppModel.describe(error)
        }
    }
}

private struct ExamProgressLabel: View {
    let status: String
    let answered: Int
    let total: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

private struct ExamDirectoryView: View {
    let exam: ExamProgress
    @Environment(AppModel.self) private var model
    @State private var types: [ExamTypeProgress] = []
    @State private var loading = true
    @State private var opening: String?
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var lastTypeID: String?

    private var lastModuleKey: String { "manabi.exam.last-module.\(model.user?.id ?? "").\(exam.id)" }
    private var resumable: ExamTypeProgress? {
        types.first { $0.id == lastTypeID && $0.practiceId != nil && $0.status != "completed" }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(exam.level) · \(exam.dateTitle)").font(.title2.bold())
                    Text("自由选择模块练习，完成后返回目录。进度仅记录练习覆盖情况。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let error { InlineError(message: error) { Task { await load() } } }
                    if loading && types.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                    if !types.isEmpty {
                        ExamProgressLabel(status: types.allSatisfy { $0.status == "completed" } ? "completed" : types.contains { $0.practiceId != nil } ? "active" : "not_started",
                                          answered: types.reduce(0) { $0 + $1.answered }, total: types.reduce(0) { $0 + $1.total })
                        if let type = resumable {
                            Button { Task { await open(type) } } label: {
                                Label("继续上次模块 · \(type.nameZh)", systemImage: "play.circle.fill")
                                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.disabled(opening != nil).accessibilityIdentifier("continueExamModule")
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(StudyCategory.allCases) { category in
                                    Button { withAnimation { proxy.scrollTo(category.rawValue, anchor: .top) } } label: {
                                        Text(category == .vocabulary ? "词汇" : category.title)
                                            .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                                            .background(Sakura.blossom.opacity(0.12), in: Capsule())
                                    }.buttonStyle(.plain).accessibilityIdentifier("examJump_\(category.rawValue)")
                                }
                            }
                        }
                        ForEach(StudyCategory.allCases) { category in
                            VStack(alignment: .leading, spacing: 10) {
                                Label(category.title, systemImage: category.symbol).font(.headline)
                                let modules = types.filter { $0.category == category.rawValue }
                                if modules.isEmpty { Text("暂无可练模块").font(.caption).foregroundStyle(.secondary) }
                                ForEach(modules) { type in
                                    Button { Task { await open(type) } } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(type.nameZh).font(.subheadline.weight(.semibold)).foregroundStyle(Sakura.ink)
                                                Spacer(minLength: 8)
                                                if opening == type.id { ProgressView() }
                                                else { Text(type.status == "completed" ? "回顾" : type.practiceId == nil ? "开始" : "继续").font(.caption.weight(.semibold)).foregroundStyle(Sakura.rose) }
                                            }
                                            ExamProgressLabel(status: type.status, answered: type.answered, total: type.total)
                                        }.studyCard(padding: 16)
                                    }.buttonStyle(.plain).disabled(opening != nil).accessibilityIdentifier("examType_\(type.id)")
                                }
                            }.id(category.rawValue)
                        }
                    } else if !loading && error == nil {
                        ContentUnavailableView("暂无可练模块", systemImage: "book.closed")
                    }
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
        }.background(SakuraBackground()).navigationTitle("试卷目录").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: model.presentedPractice?.id) { _, id in if id == nil { Task { await load() } } }
    }

    private func load() async {
        let request = UUID()
        requestID = request
        loading = true
        let api = model.api
        let userID = model.user?.id
        let examID = exam.id
        defer { if requestID == request { loading = false } }
        do {
            let rows = try await withThrowingTaskGroup(of: [ExamTypeProgress].self) { group in
                for category in StudyCategory.allCases {
                    group.addTask {
                        let page: ItemList<ExamTypeProgress> = try await api.get("exam-practice/exams/\(examID)/types", query: [.init(name: "category", value: category.rawValue)])
                        return page.items
                    }
                }
                var rows: [ExamTypeProgress] = []
                for try await page in group { rows += page }
                return rows
            }
            guard !Task.isCancelled, requestID == request, api === model.api, userID == model.user?.id else { return }
            types = rows
            lastTypeID = UserDefaults.standard.string(forKey: lastModuleKey)
            error = nil
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            self.error = AppModel.describe(error)
        }
    }

    private func open(_ type: ExamTypeProgress) async {
        guard opening == nil else { return }
        opening = type.id
        defer { opening = nil }
        let api = model.api
        let userID = model.user?.id
        do {
            let practice: Practice = try await api.post("exam-practice/exams/\(exam.id)/types/\(type.id)/practice", body: EmptyBody())
            guard api === model.api, userID == model.user?.id else { return }
            lastTypeID = type.id
            UserDefaults.standard.set(type.id, forKey: lastModuleKey)
            model.practiceReturnsToExamDirectory = true
            model.presentedPractice = practice
            error = nil
        } catch { self.error = AppModel.describe(error) }
    }
}
