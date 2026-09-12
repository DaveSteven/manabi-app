import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    var api: APIClient
    var serverURL: URL
    var user: Profile?
    var levels: [LevelInfo] = []
    var types: [QuestionType] = []
    var stats: [StudyStat] = []
    var recent: [PracticeSummary] = []
    var selectedLevel = "N3"
    var isLoading = false
    var loadingTypes = false
    var message: String?
    var needsAccount = false
    var presentedPractice: Practice?
    var practiceReturnsToExamDirectory = false
    var showSettings = false
    private var started = false
    private var catalog: [String: [QuestionType]] = [:]
    private var vaultKey: String {
        serverURL.absoluteString + (ProcessInfo.processInfo.environment["MANABI_UI_TESTING"] == "1" ? "|ui-tests" : "")
    }

    private var serverPreferenceKey: String {
        ProcessInfo.processInfo.environment["MANABI_UI_TESTING"] == "1" ? "manabi.test.server" : "manabi.server"
    }

    init() {
        let testing = ProcessInfo.processInfo.environment["MANABI_UI_TESTING"] == "1"
        let defaults = UserDefaults.standard
        let preferenceKey = testing ? "manabi.test.server" : "manabi.server"
        let defaultURL = URL(string: testing ? "http://127.0.0.1:8001" : "https://biblenotes.cc")!
        var configured = defaults.string(forKey: preferenceKey).flatMap { try? APIClient.validatedURL($0) }
        if !testing && !defaults.bool(forKey: "manabi.online-default-migrated") {
            if let old = configured, old.scheme == "http", old.port == 8001,
               ["127.0.0.1", "localhost"].contains(old.host ?? "") {
                configured = defaultURL
                defaults.set(defaultURL.absoluteString, forKey: preferenceKey)
            }
            defaults.set(true, forKey: "manabi.online-default-migrated")
        }
        let initialURL = configured ?? defaultURL
        serverURL = initialURL
        let key = initialURL.absoluteString + (testing ? "|ui-tests" : "")
        api = APIClient(baseURL: initialURL, token: TokenVault.read(server: key))
    }

    var answeredCount: Int { stats.filter { $0.level == selectedLevel }.reduce(0) { $0 + $1.answered } }
    var accuracy: Int? {
        guard answeredCount > 0 else { return nil }
        let correct = stats.filter { $0.level == selectedLevel }.reduce(0) { $0 + $1.correct }
        return Int((Double(correct) / Double(answeredCount) * 100).rounded())
    }
    var totalAvailable: Int { levels.first { $0.level == selectedLevel }?.questionCount ?? 0 }
    var latestActive: PracticeSummary? { recent.first { $0.status == "active" && $0.level == selectedLevel } }

    func name(for typeId: String) -> String {
        catalog.values.flatMap { $0 }.first { $0.id == typeId }?.nameZh ?? "专项练习"
    }

    func bootstrap() async {
        guard !started else { return }
        started = true
        await connect()
    }

    func connect() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            guard TokenVault.read(server: vaultKey) != nil else {
                user = nil
                needsAccount = true
                return
            }
            let profile: Profile = try await api.get("me")
            guard !profile.isGuest else {
                TokenVault.remove(server: vaultKey)
                await api.setToken(nil)
                user = nil
                needsAccount = true
                return
            }
            user = profile
            selectedLevel = user?.level ?? "N3"
            needsAccount = false
            await refresh()
        } catch {
            handle(error)
        }
    }

    func refresh() async {
        guard user != nil else { return }
        let currentAPI = api
        let level = selectedLevel
        let userId = user?.id
        do {
            async let levelsResult: ItemList<LevelInfo> = currentAPI.get("catalog/levels")
            async let typesResult: ItemList<QuestionType> = currentAPI.get("catalog/types", query: [.init(name: "level", value: level)])
            async let statsResult: ItemList<StudyStat> = currentAPI.get("me/stats")
            async let historyResult: Page<PracticeSummary> = currentAPI.get("practices", query: [.init(name: "limit", value: "30")])
            let (newLevels, newTypes, newStats, history) = try await (levelsResult, typesResult, statsResult, historyResult)
            guard level == selectedLevel, currentAPI === api, userId == user?.id else { return }
            levels = newLevels.items
            types = newTypes.items
            catalog[level] = types
            stats = newStats.items
            recent = history.items
            message = nil
            for otherLevel in Set(history.items.map(\.level)).subtracting([level]) where catalog[otherLevel] == nil {
                if let additional: ItemList<QuestionType> = try? await currentAPI.get("catalog/types", query: [.init(name: "level", value: otherLevel)]), userId == user?.id, currentAPI === api {
                    catalog[otherLevel] = additional.items
                }
            }
        } catch { handle(error) }
    }

    func changeLevel(_ level: String) async {
        guard !loadingTypes, level != selectedLevel else { return }
        loadingTypes = true
        defer { loadingTypes = false }
        do {
            let updated: Profile = try await api.patch("me", body: LevelBody(level: level))
            user = updated
            selectedLevel = level
            types = catalog[level] ?? []
            await refresh()
        } catch { handle(error) }
    }

    func start(type: QuestionType, count: Int, mode: String = "normal", level: String? = nil) async throws {
        let level = level ?? selectedLevel
        let cacheKey = "manabi.pending.\(serverURL.absoluteString).\(user?.id ?? "").\(level).\(type.id).\(count).\(mode)"
        let key = UserDefaults.standard.string(forKey: cacheKey) ?? UUID().uuidString
        UserDefaults.standard.set(key, forKey: cacheKey)
        let body = CreatePractice(level: level, typeId: type.id, count: count, mode: mode, requestKey: key)
        let practice: Practice = try await api.post("practices", body: body)
        UserDefaults.standard.removeObject(forKey: cacheKey)
        presentedPractice = practice
    }

    func resume(_ id: String) async throws {
        presentedPractice = try await api.get("practices/\(id)")
    }

    func signIn(username: String, password: String, register: Bool) async throws {
        let body = Credentials(username: username, password: password)
        if register && user?.isGuest == true && !needsAccount {
            let updated: Profile = try await api.post("auth/upgrade", body: body)
            user = updated
        } else {
            let response: AuthResponse = try await api.post(register ? "auth/register" : "auth/login", body: body)
            try await accept(response)
        }
        needsAccount = false
        selectedLevel = user?.level ?? "N3"
        await refresh()
    }

    func logout() async throws {
        do {
            let _: EmptyBody = try await api.post("auth/logout", body: EmptyBody())
        } catch APIError.http(401, _) {
            // An expired session is already logged out on the server.
        }
        TokenVault.remove(server: vaultKey)
        await api.setToken(nil)
        user = nil
        presentedPractice = nil
        types = []
        levels = []
        catalog = [:]
        stats = []
        recent = []
        needsAccount = true
    }

    func updateServer(_ address: String) async throws {
        let url = try APIClient.validatedURL(address)
        guard url != serverURL else { await connect(); return }
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: serverPreferenceKey)
        api = APIClient(baseURL: url, token: TokenVault.read(server: vaultKey))
        user = nil
        levels = []
        types = []
        stats = []
        recent = []
        catalog = [:]
        needsAccount = false
        await connect()
    }

    func mediaURL(_ path: String?) -> URL? {
        guard let path, let url = URL(string: path, relativeTo: serverURL)?.absoluteURL,
              url.host == serverURL.host, url.port == serverURL.port, url.scheme == serverURL.scheme else { return nil }
        return url
    }

    func handle(_ error: Error) {
        if error is CancellationError { return }
        if case APIError.http(401, _) = error {
            TokenVault.remove(server: vaultKey)
            user = nil
            presentedPractice = nil
            stats = []
            recent = []
            needsAccount = true
        }
        message = Self.describe(error)
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return "请求已取消，请重试。" }
            return "暂时连接不上学习服务，请检查网络后重试。"
        }
        if error is DecodingError { return "学习内容暂时无法读取，请刷新后重试。" }
        return error.localizedDescription
    }

    private func accept(_ auth: AuthResponse) async throws {
        try TokenVault.save(auth.accessToken, server: vaultKey)
        await api.setToken(auth.accessToken)
        if user?.id != auth.user.id {
            stats = []
            recent = []
            presentedPractice = nil
        }
        user = auth.user
    }
}
