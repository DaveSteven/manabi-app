import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?
    @State private var logoutConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 17) {
                        ManabiMark(size: 64).padding(10).background(Sakura.blossom.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.user?.username ?? "学习中的你").font(.title2.bold())
                            Text("每一天，都有一点新收获。").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 12)
                    MetricRow {
                        Metric(value: model.stats.reduce(0) { $0 + $1.answered }.formatted(), label: "累计作答")
                        Metric(value: "\(model.stats.reduce(0) { $0 + $1.elapsedMs } / 60000)", label: "累计学习分钟")
                    }.studyCard()

                    if model.user?.isGuest != false || model.needsAccount {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("让学习记录一直陪着你").font(.headline)
                            Text("使用内部账号登录，查看你的练习与错题记录。").font(.subheadline).foregroundStyle(.secondary)
                            NavigationLink("登录账号") { AuthView() }.fontWeight(.semibold)
                        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
                    }

                    VStack(spacing: 0) {
                        NavigationLink { CacheManagementView() } label: { settingsRow("缓存管理", symbol: "arrow.down.circle") }
                            .accessibilityIdentifier("cacheManagement")
                        Divider().padding(.leading, 40)
                        NavigationLink { HistoryView() } label: { settingsRow("练习记录", symbol: "clock.arrow.circlepath") }
                        Divider().padding(.leading, 40)
                        HStack {
                            settingsLabel("当前学习等级", symbol: "graduationcap")
                            Spacer()
                            LevelMenu()
                        }.padding(.vertical, 18)
                        Divider().padding(.leading, 40)
                        Button { model.showSettings = true } label: { settingsRow("学习服务设置", symbol: "network") }
                    }.studyCard(padding: 19)
                    if model.user != nil {
                        Button("退出登录") { logoutConfirmation = true }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    if let error { InlineError(message: error) }
                    VStack(spacing: 7) {
                        Text("Manabi").font(.system(.headline, design: .rounded))
                        Text("学びを、毎日に。").font(.caption).tracking(2)
                        Text("版本 0.1.0").font(.caption2)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 15)
                }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.background(SakuraBackground()).navigationTitle("我的")
                .refreshable { await model.refresh() }
                .alert("退出当前账号？", isPresented: $logoutConfirmation) {
                    Button("取消", role: .cancel) { }
                    Button("退出登录", role: .destructive) {
                        Task { do { try await model.logout() } catch { self.error = AppModel.describe(error) } }
                    }.accessibilityIdentifier("confirmLogout")
                } message: {
                    Text("再次登录即可继续查看你的学习记录。")
                }
        }
    }

    private func settingsLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 28, height: 24)
                .accessibilityHidden(true)
            Text(title).font(.body)
        }.foregroundStyle(Sakura.ink)
    }

    private func settingsRow(_ title: String, symbol: String) -> some View {
        HStack {
            settingsLabel(title, symbol: symbol)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 18).contentShape(Rectangle())
    }
}

struct AuthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    // 内部使用阶段关闭注册；保留 AppModel 中的注册逻辑，方便后续恢复。
    private let register = false
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ManabiMark(size: 70).padding(.top, 25)
                Text(register ? "把进步，留在这里。" : "欢迎回来。").font(.largeTitle.bold())
                Text(register && model.user?.isGuest == true ? "创建账号后，当前的练习记录会继续保留。" : "登录账号，接着上一次的学习。")
                    .font(.subheadline).foregroundStyle(.secondary)
                // Picker("账号操作", selection: $register) { Text("创建账号").tag(true); Text("登录").tag(false) }.pickerStyle(.segmented)
                VStack(spacing: 18) {
                    TextField("用户名", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("username")
                    Divider()
                    SecureField("密码（至少 8 位）", text: $password).textContentType(register ? .newPassword : .password)
                        .accessibilityIdentifier("password")
                }.studyCard()
                Text("用户名可使用 3–64 位英文字母、数字、下划线、点和短横线。").font(.caption).foregroundStyle(.secondary)
                if let error { InlineError(message: error) }
                else if let message = model.message { InlineError(message: message) }
                PrimaryButton(register ? "创建账号" : "登录", loading: busy, disabled: username.count < 3 || password.count < 8) {
                    busy = true
                    error = nil
                    Task {
                        defer { busy = false }
                        do {
                            try await model.signIn(username: username, password: password, register: register)
                            password = ""
                            dismiss()
                        } catch { self.error = AppModel.describe(error) }
                    }
                }
            }.padding(24).frame(maxWidth: 550).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle("账号").navigationBarTitleDisplayMode(.inline)
    }
}

struct ServerSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("学习服务地址") {
                    TextField("https://biblenotes.cc", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("serverAddress")
                }
                Section {
                    Text("模拟器可连接本机服务。真机请填写电脑在同一 Wi-Fi 下的可访问地址，或已部署的 HTTPS 地址。").font(.footnote).foregroundStyle(.secondary)
                    Text("不同服务的登录信息分别保存，切换不会覆盖原来的账号。").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                try await model.updateServer(address)
                                if model.message == nil { dismiss() } else { error = model.message }
                            } catch { self.error = AppModel.describe(error) }
                        }
                    } label: {
                        HStack { Text("保存并连接"); Spacer(); if busy { ProgressView() } }
                    }.disabled(busy)
                }
            }.scrollContentBackground(.hidden).background(SakuraBackground())
                .navigationTitle("连接设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
                .onAppear { address = model.serverURL.absoluteString }
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [PracticeSummary] = []
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var opening: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                if let error { InlineError(message: error) { Task { await load(reset: true) } } }
                if rows.isEmpty && !loading {
                    ContentUnavailableView("学习从第一组开始", systemImage: "clock", description: Text("完成的练习和未完成的进度都会保存在这里。"))
                }
                ForEach(rows) { row in
                    Button {
                        opening = row.id
                        Task {
                            defer { opening = nil }
                            do { try await model.resume(row.id) } catch { self.error = AppModel.describe(error) }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(row.level) · \(model.name(for: row.typeId))").font(.headline).foregroundStyle(Sakura.ink)
                                Text("\(row.status == "completed" ? "已完成" : row.status == "abandoned" ? "已放弃" : "进行中") · \(row.answered)/\(row.total) 题").font(.caption).foregroundStyle(.secondary)
                                Text(String(row.createdAt.prefix(10))).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if opening == row.id { ProgressView() } else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Sakura.rose) }
                        }.studyCard()
                    }.buttonStyle(.plain).disabled(opening != nil || row.status == "abandoned")
                }
                if loading { ProgressView() }
                if rows.count < total { Button("加载更多") { Task { await load(reset: false) } }.disabled(loading) }
            }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SakuraBackground()).navigationTitle("练习记录").navigationBarTitleDisplayMode(.inline)
            .task { await load(reset: true) }.refreshable { await load(reset: true) }
            .onChange(of: model.presentedPractice?.id) { _, new in if new == nil { Task { await load(reset: true) } } }
    }

    private func load(reset: Bool) async {
        guard model.user != nil else { return }
        loading = true
        defer { loading = false }
        do {
            let page: Page<PracticeSummary> = try await model.api.get("practices", query: [.init(name: "limit", value: "20"), .init(name: "offset", value: String(reset ? 0 : rows.count))])
            rows = reset ? page.items : rows + page.items
            total = page.total
            error = nil
        } catch { self.error = AppModel.describe(error) }
    }
}
