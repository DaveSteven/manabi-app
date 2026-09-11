import SwiftUI

struct WrongQuestionsView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [WrongQuestion] = []
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var resolved = false
    @State private var selectedType = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    Text("把不熟悉，变成熟悉。").font(.title2.bold()).padding(.top, 10)
                    Text("错过的题目，也是下一次进步的起点。").font(.subheadline).foregroundStyle(.secondary)
                    Picker("错题状态", selection: $resolved) {
                        Text("待复习").tag(false)
                        Text("已答对").tag(true)
                    }.pickerStyle(.segmented)

                    HStack {
                        Menu {
                            Button("全部题型") { selectedType = "" }
                            ForEach(model.types) { type in Button(type.nameZh) { selectedType = type.id } }
                        } label: {
                            Label(selectedType.isEmpty ? "全部题型" : model.name(for: selectedType), systemImage: "line.3.horizontal.decrease")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        Text("\(total) 道题").font(.caption).foregroundStyle(.secondary)
                    }

                    if loading && rows.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(30) }
                    if let error { InlineError(message: error) { Task { await load(reset: true) } } }
                    if rows.isEmpty && !loading && error == nil {
                        ContentUnavailableView(resolved ? "还没有已掌握的错题" : "这里还没有错题", systemImage: "bookmark", description: Text(resolved ? "把错题重新答对后，会收录在这里。" : "做错的题目会自动收好，随时回来复习。"))
                            .studyCard(padding: 12)
                    }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Text("\(row.level) · \(model.name(for: row.typeId ?? ""))").font(.caption.weight(.semibold)).foregroundStyle(Sakura.rose)
                                Spacer()
                                Text("错过 \(row.wrongCount) 次").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(row.prompt.isEmpty ? "听力或材料关联题" : row.prompt.text).font(.body).lineSpacing(5).lineLimit(4)
                            if row.available && !resolved, let type = model.types.first(where: { $0.id == row.typeId }) {
                                NavigationLink {
                                    PracticeSetupView(type: type, level: row.level, mode: "wrong")
                                } label: {
                                    Label("复习这个题型", systemImage: "arrow.clockwise").font(.subheadline.weight(.semibold))
                                }
                            } else if !row.available {
                                Text("这道题正在核对，暂时无法练习。").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Label("已在后续练习中答对", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Sakura.success)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
                    }
                    if rows.count < total {
                        Button { Task { await load(reset: false) } } label: {
                            if loading { ProgressView() } else { Text("加载更多") }
                        }.frame(maxWidth: .infinity).disabled(loading)
                    }
                }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.background(SakuraBackground()).navigationTitle("错题本")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { LevelMenu() } }
                .task(id: "\(model.user?.id ?? "").\(model.selectedLevel).\(resolved).\(selectedType)") { await load(reset: true) }
                .refreshable { await load(reset: true) }
                .onChange(of: model.presentedPractice?.id) { _, new in
                    if new == nil { Task { await load(reset: true) } }
                }
        }
    }

    private func load(reset: Bool) async {
        guard model.user != nil, !model.needsAccount else { rows = []; total = 0; return }
        loading = true
        error = nil
        let level = model.selectedLevel
        let filter = selectedType
        let state = resolved
        let userId = model.user?.id
        defer { loading = false }
        do {
            var query = [URLQueryItem(name: "level", value: level), .init(name: "resolved", value: String(state)),
                         .init(name: "limit", value: "20"), .init(name: "offset", value: String(reset ? 0 : rows.count))]
            if !filter.isEmpty { query.append(.init(name: "type_id", value: filter)) }
            let page: Page<WrongQuestion> = try await model.api.get("wrong-questions", query: query)
            guard level == model.selectedLevel, filter == selectedType, state == resolved, userId == model.user?.id else { return }
            rows = reset ? page.items : rows + page.items
            total = page.total
        } catch is CancellationError {} catch { self.error = AppModel.describe(error) }
    }
}
