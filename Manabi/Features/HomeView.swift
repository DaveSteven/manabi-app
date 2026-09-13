import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var resuming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("毎日の学び").font(.caption.weight(.medium)).tracking(3).foregroundStyle(Sakura.rose)
                            Text("把日语，\n一点点学会。").font(.system(.largeTitle, design: .rounded, weight: .bold)).lineSpacing(4)
                            Text("从一组专项练习开始。").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        ManabiMark(size: 72).padding(.top, 20)
                    }.padding(.top, 4)

                    if model.isLoading {
                        HStack { ProgressView(); Text("正在准备你的学习空间…").font(.subheadline) }.frame(maxWidth: .infinity).padding()
                    }
                    if model.needsAccount {
                        accountCard
                    } else if let message = model.message {
                        InlineError(message: message) { Task { await model.connect() } }
                    }

                    MetricRow {
                        Metric(value: model.totalAvailable.formatted(), label: "可练题目")
                        Metric(value: model.answeredCount.formatted(), label: "累计作答")
                        Metric(value: model.accuracy.map { "\($0)%" } ?? "—", label: "正确率")
                    }.studyCard()

                    if let active = model.latestActive, !model.needsAccount {
                        Button {
                            resuming = true
                            Task {
                                defer { resuming = false }
                                do { try await model.resume(active.id) } catch { model.handle(error) }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().stroke(Sakura.blossom.opacity(0.25), lineWidth: 4)
                                    Circle().trim(from: 0, to: active.progress).stroke(Sakura.rose, style: .init(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                                    Image(systemName: "play.fill").font(.caption)
                                }.frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("继续上次练习").font(.subheadline.weight(.semibold))
                                    Text("\(model.name(for: active.typeId)) · 已完成 \(active.answered)/\(active.total)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if resuming { ProgressView() } else { Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)) }
                            }.padding(19).sakuraGlass()
                        }.buttonStyle(.plain).disabled(resuming).accessibilityIdentifier("continuePractice")
                    }

                    NavigationLink {
                        ExamPracticeView(level: model.selectedLevel)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Sakura.rose)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("按试卷练习").font(.headline).foregroundStyle(Sakura.ink)
                                Text("按年份选真题，自由练习各模块").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Sakura.rose)
                        }.studyCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("examPracticeEntry")

                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("专项练习").font(.title3.bold())
                            Spacer()
                            Text("JLPT · \(model.selectedLevel)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 14) {
                            ForEach(StudyCategory.allCases) { category in
                                NavigationLink(value: category) {
                                    categoryCard(category)
                                }.buttonStyle(.plain)
                                    .disabled(model.user == nil || model.needsAccount || model.loadingTypes)
                                    .accessibilityIdentifier("category_\(category.rawValue)")
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "leaf")
                        Text("不用着急，每一次练习都算数。")
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.padding(.horizontal, 22).padding(.bottom, 24).frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
            .background(SakuraBackground())
            .navigationTitle("Manabi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { LevelMenu() }
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("连接设置")
                }
            }
            .navigationDestination(for: StudyCategory.self) { category in CategoryView(category: category) }
            .refreshable { await model.refresh() }
        }
    }

    private func categoryCard(_ category: StudyCategory) -> some View {
        let count = model.types.filter { $0.category == category.rawValue }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: category.symbol).font(.system(size: 23, weight: .medium)).foregroundStyle(Sakura.rose)
                    .frame(width: 46, height: 46).background(Sakura.blossom.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(Sakura.blossom)
            }
            Spacer(minLength: 20)
            Text(category.title).font(.headline).foregroundStyle(Sakura.ink)
            Text("\(count) 个专项题型").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
        }.frame(minHeight: 135, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).studyCard(padding: 18)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("登录后，接着学").font(.headline)
            Text("登录你的账号以恢复学习记录。").font(.subheadline).foregroundStyle(.secondary)
            NavigationLink("登录账号") { AuthView() }.fontWeight(.semibold)
        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
    }
}

struct LevelMenu: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Menu {
            ForEach(model.levels) { level in
                Button {
                    Task { await model.changeLevel(level.level) }
                } label: {
                    if level.level == model.selectedLevel { Label(level.level, systemImage: "checkmark") }
                    else { Text(level.level) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.selectedLevel).font(.subheadline.weight(.bold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }.foregroundStyle(Sakura.rose).padding(.horizontal, 5)
        }.disabled(model.user == nil || model.loadingTypes).accessibilityIdentifier("levelMenu")
    }
}

struct CategoryView: View {
    @Environment(AppModel.self) private var model
    let category: StudyCategory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(model.selectedLevel) / \(category.japanese)").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Sakura.rose)
                    Text(category.caption).font(.title2.bold())
                    Text("选择一个题型，专注练习。").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 12)
                ForEach(model.types.filter { $0.category == category.rawValue }) { type in
                    NavigationLink {
                        PracticeSetupView(type: type, level: model.selectedLevel)
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(type.nameZh).font(.headline).foregroundStyle(Sakura.ink)
                                Text(type.nameJa).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 7) {
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Sakura.rose)
                                Text("\(type.questionCount) 题").font(.caption).foregroundStyle(.secondary)
                            }
                        }.studyCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("type_\(type.id)")
                }
            }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle(category.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct PracticeSetupView: View {
    @Environment(AppModel.self) private var model
    let type: QuestionType
    let level: String
    var mode = "normal"
    @State private var count = 10
    @State private var starting = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: type.studyCategory.symbol).font(.system(size: 35)).foregroundStyle(Sakura.rose)
                        .frame(width: 76, height: 76).background(Sakura.blossom.opacity(0.15), in: RoundedRectangle(cornerRadius: 25))
                    Text(type.nameZh).font(.largeTitle.bold())
                    Text("\(level) · \(type.nameJa)").font(.subheadline).foregroundStyle(.secondary)
                    Text(mode == "wrong" ? "再练一次，让不熟悉的地方变得熟悉。" : "专注眼前这一组，让理解更扎实一点。")
                        .font(.body).lineSpacing(5).padding(.top, 5)
                }.padding(.top, 15)

                VStack(alignment: .leading, spacing: 18) {
                    Text("这次练多少题？").font(.headline)
                    Picker("练习题数", selection: $count) {
                        Text("5 题").tag(5)
                        Text("10 题").tag(10)
                        Text("20 题").tag(20)
                    }.pickerStyle(.segmented).accessibilityIdentifier("questionCount")
                    Label("提交后即刻查看答案与解析", systemImage: "checkmark.bubble").font(.subheadline).foregroundStyle(.secondary)
                    Label("中途离开，也能下次继续", systemImage: "bookmark").font(.subheadline).foregroundStyle(.secondary)
                }.studyCard()

                if type.category == "reading" || type.category == "listening" || type.id == "text_grammar" {
                    Text("文章和关联小题会完整保留，实际题数可能略有调整。")
                        .font(.footnote).foregroundStyle(.secondary).lineSpacing(5)
                }
                if let error { InlineError(message: error) }
                PrimaryButton(mode == "wrong" ? "开始复习" : "开始练习", symbol: "arrow.right", loading: starting) {
                    error = nil
                    starting = true
                    Task {
                        defer { starting = false }
                        do { try await model.start(type: type, count: count, mode: mode, level: level) }
                        catch { self.error = AppModel.describe(error) }
                    }
                }.accessibilityIdentifier("startPractice")
                Text(mode == "wrong" ? "将抽取含错题的完整材料组" : "从 \(type.questionCount) 道真题中抽取")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle(mode == "wrong" ? "错题复习" : "准备练习").navigationBarTitleDisplayMode(.inline)
    }
}

extension PrimaryButton {
    init(_ title: String, symbol: String? = nil, loading: Bool = false, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.loading = loading
        self.disabled = disabled
        self.action = action
    }
}
