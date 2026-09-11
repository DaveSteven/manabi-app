import SwiftUI

struct PracticeFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var practice: Practice
    @State private var index: Int
    @State private var selected: String?
    @State private var submitting = false
    @State private var error: String?
    @State private var showingResult = false
    @State private var confirmingExit = false
    @State private var showMaterial = false
    @State private var intensiveItem: PracticeItem?
    @State private var audio = AudioController()
    @State private var foregroundStart = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var pendingElapsed: Int?

    init(practice: Practice) {
        _practice = State(initialValue: practice)
        _index = State(initialValue: practice.items.firstIndex { $0.id == practice.nextItemId } ?? 0)
        _showingResult = State(initialValue: practice.status == "completed")
    }

    private var item: PracticeItem? { practice.items.indices.contains(index) ? practice.items[index] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if showingResult {
                    resultView
                } else if let item {
                    questionView(item)
                } else {
                    ContentUnavailableView("暂时没有题目", systemImage: "book.closed", description: Text("请返回后重新开始练习。"))
                }
            }
            .background(SakuraBackground())
            .navigationTitle(showingResult ? "练习完成" : model.name(for: practice.typeId))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if showingResult { dismiss() } else { confirmingExit = true } } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("退出练习").accessibilityIdentifier("exitPractice").disabled(submitting)
                }
                if !showingResult {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(index + 1) / \(practice.total)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .alert("退出本次练习？", isPresented: $confirmingExit) {
                Button("保存进度并退出") { dismiss() }.accessibilityIdentifier("confirmPracticeExit")
                Button("继续练习", role: .cancel) {}.accessibilityIdentifier("cancelPracticeExit")
            } message: { Text("已提交的答案会保留，下次可以接着练习。尚未提交的选择不会保存。") }
            .interactiveDismissDisabled(submitting)
        }
        .sheet(item: $intensiveItem) { item in
            IntensiveListeningView(practiceId: practice.id, itemId: item.id).environment(model)
        }
        .onDisappear { audio.stop() }
        .onChange(of: index) { _, _ in
            selected = nil
            error = nil
            pendingElapsed = nil
            elapsed = 0
            foregroundStart = Date()
            showMaterial = !(item?.question.material.content.isEmpty ?? true)
            audio.pause()
        }
        .onChange(of: scenePhase) { old, new in
            if old == .active { elapsed += Date().timeIntervalSince(foregroundStart); audio.pause() }
            if new == .active { foregroundStart = Date() }
        }
    }

    private func questionView(_ item: PracticeItem) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    Color.clear.frame(height: 0).id("top")
                    ProgressView(value: Double(index + 1), total: Double(max(practice.total, 1))).tint(Sakura.rose)
                    HStack {
                        Text("\(practice.level) · \(item.question.source.examTitle)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text("真题专项").font(.caption2.weight(.medium)).foregroundStyle(Sakura.rose)
                    }

                    if let url = model.mediaURL(item.question.material.audioUrl) {
                        ListeningPlayer(url: url, controller: audio)
                        Button {
                            audio.pause()
                            intensiveItem = item
                        } label: {
                            Label("进入精听 · 逐句练习", systemImage: "ear.badge.waveform")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.accessibilityIdentifier("openIntensiveListening")
                    }
                    if !item.question.material.content.isEmpty {
                        DisclosureGroup(isExpanded: $showMaterial) {
                            RichText(content: item.question.material.content).padding(.top, 14)
                        } label: {
                            Label("阅读材料", systemImage: "doc.text").font(.subheadline.weight(.semibold))
                        }.studyCard().accessibilityIdentifier("readingMaterial")
                            .onAppear { showMaterial = true }
                    }
                    if let imageURL = model.mediaURL(item.question.material.imageUrl) {
                        QuestionImage(url: imageURL)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("第 \(index + 1) 题").font(.caption.weight(.semibold)).foregroundStyle(Sakura.rose)
                        let siblings = practice.items.filter { $0.question.groupId == item.question.groupId }
                        let ordinal = (siblings.firstIndex { $0.id == item.id } ?? 0) + 1
                        if siblings.count > 1 {
                            Text("本材料第 \(ordinal) / \(siblings.count) 小题").font(.caption).foregroundStyle(.secondary)
                        }
                        if item.question.prompt.isEmpty {
                            Text(item.question.typeId == "text_grammar" ? "请选择文章中第 \(ordinal) 个空的答案。" : (item.question.material.audioUrl == nil ? "阅读材料，选出最合适的答案。" : "请听音频，选出最合适的答案。"))
                                .font(.title3.weight(.medium))
                        } else {
                            RichText(content: item.question.prompt, fontSize: 20)
                        }
                        DisclosureGroup("答题说明") {
                            RichText(content: item.question.source.section, fontSize: 15).padding(.top, 10)
                        }.font(.caption).foregroundStyle(.secondary)
                    }.studyCard()

                    VStack(spacing: 12) {
                        ForEach(item.question.options) { option in optionButton(option, item: item) }
                    }
                    if let feedback = item.feedback {
                        feedbackView(feedback, item: item).id("feedback")
                    }
                    if let error { InlineError(message: error) }
                    Color.clear.frame(height: 10)
                }.padding(.horizontal, 22).padding(.bottom, 12).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    PrimaryButton(item.feedback == nil ? (pendingElapsed == nil ? "确认答案" : "重试提交") : (index == practice.items.count - 1 ? "查看练习结果" : "下一题"), symbol: item.feedback == nil ? nil : "arrow.right", loading: submitting, disabled: item.feedback == nil && selected == nil) {
                        if item.feedback != nil {
                            if index == practice.items.count - 1 { showingResult = true; audio.pause() }
                            else { index += 1; proxy.scrollTo("top", anchor: .top) }
                        } else {
                            Task { await submit(item); if self.item?.feedback != nil { withAnimation { proxy.scrollTo("feedback", anchor: .top) } } }
                        }
                    }.accessibilityIdentifier("answerAction")
                }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 12)
                    .background(.regularMaterial)
            }
            .onChange(of: item.feedback != nil) { _, hasFeedback in
                if hasFeedback {
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo("feedback", anchor: .top) }
                    }
                }
            }
        }
    }

    private func optionButton(_ option: StudyOption, item: PracticeItem) -> some View {
        let feedback = item.feedback
        let chosen = (feedback?.chosenOptionId ?? selected) == option.id
        let right = feedback?.correctOptionId == option.id
        let wrong = feedback != nil && chosen && !right
        let tint = right ? Sakura.success : (wrong ? Color.red : Sakura.rose)
        return Button {
            guard pendingElapsed == nil, !submitting, feedback == nil else { return }
            selected = option.id
        } label: {
            HStack(alignment: .top, spacing: 13) {
                Text("\(option.position + 1)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    .frame(width: 30, height: 30)
                    .background((chosen || right) ? tint.opacity(0.14) : Sakura.blossom.opacity(0.10), in: Circle())
                    .foregroundStyle((chosen || right) ? tint : .secondary)
                RichText(content: option.content, fontSize: 18).allowsHitTesting(false)
                if right || wrong || chosen {
                    Image(systemName: right ? "checkmark.circle.fill" : (wrong ? "xmark.circle.fill" : "circle.inset.filled"))
                        .foregroundStyle(tint).padding(.top, 5)
                }
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background((chosen || right) ? tint.opacity(0.06) : Sakura.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder((chosen || right) ? tint : Sakura.blossom.opacity(0.20), lineWidth: chosen || right ? 1.5 : 1))
        }.buttonStyle(.plain).allowsHitTesting(!submitting && feedback == nil && pendingElapsed == nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("选项 \(option.position + 1)，\(option.content.text)")
            .accessibilityValue(feedback != nil ? "已提交答案" : (chosen ? "已选择" : "未选择"))
            .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("option_\(option.position)")
    }

    private func feedbackView(_ feedback: Feedback, item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(feedback.isCorrect ? "答对了，继续保持" : "没关系，再理解一次", systemImage: feedback.isCorrect ? "checkmark.circle.fill" : "lightbulb")
                .font(.headline).foregroundStyle(feedback.isCorrect ? Sakura.success : Sakura.rose)
            let number = item.question.options.first { $0.id == feedback.correctOptionId }.map { $0.position + 1 } ?? 0
            Text("正确答案：\(number)").font(.subheadline.weight(.semibold))
            Divider()
            Text("解析").font(.subheadline.weight(.semibold))
            if feedback.explanationAvailable { RichText(content: feedback.explanation, fontSize: 17) }
            else { Text("这道题暂时没有解析。").font(.subheadline).foregroundStyle(.secondary) }
            if !feedback.translation.isEmpty {
                DisclosureGroup("参考译文") { RichText(content: feedback.translation, fontSize: 17).padding(.top, 12) }.font(.subheadline)
            }
            if !feedback.subtitles.isEmpty {
                DisclosureGroup("听力原文 · 点击定位") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(feedback.subtitles) { segment in
                            Button { audio.replay(segment) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "play.circle").foregroundStyle(Sakura.rose)
                                    Text(segment.text).font(.body).lineSpacing(5).foregroundStyle(Sakura.ink)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.top, 14)
                }.font(.subheadline)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).studyCard().accessibilityIdentifier("answerFeedback")
    }

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 26) {
                PetalMark(size: 100).padding(.top, 35)
                Text("又积累了一点。").font(.largeTitle.bold())
                Text("\(practice.level) · \(model.name(for: practice.typeId))").font(.subheadline).foregroundStyle(.secondary)
                MetricRow {
                    Metric(value: "\(practice.correct)/\(practice.total)", label: "答对题数")
                    Metric(value: "\(practice.total == 0 ? 0 : Int(Double(practice.correct) / Double(practice.total) * 100))%", label: "正确率")
                    Metric(value: "\(practice.elapsedMs / 60000)分\((practice.elapsedMs / 1000) % 60)秒", label: "作答用时")
                }.studyCard()
                if practice.correct < practice.total {
                    Text("错题已为你收好，随时可以再练一次。").font(.subheadline).foregroundStyle(.secondary)
                }
                PrimaryButton("回顾本组题目", symbol: "book") { index = 0; showingResult = false }
                Button("完成，回到练习") { dismiss() }.font(.body.weight(.semibold)).padding(.vertical, 6).accessibilityIdentifier("finishPractice")
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
    }

    private func submit(_ item: PracticeItem) async {
        guard let selected, !submitting else { return }
        if pendingElapsed == nil { pendingElapsed = min(86_400_000, max(0, Int((elapsed + Date().timeIntervalSince(foregroundStart)) * 1000))) }
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            let updated: PracticeItem = try await model.api.post("practices/\(practice.id)/items/\(item.id)/answer", body: AnswerBody(optionId: selected, elapsedMs: pendingElapsed ?? 0))
            practice.apply(updated)
        } catch { self.error = AppModel.describe(error) }
    }
}
