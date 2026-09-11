import SwiftUI

@main
struct ManabiApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model).tint(Sakura.rose)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Group {
            if model.isLoading && model.user == nil {
                ProgressView("正在连接…").frame(maxWidth: .infinity, maxHeight: .infinity).background(SakuraBackground())
            } else if model.user?.isGuest == false && !model.needsAccount {
                mainTabs
            } else {
                NavigationStack {
                    AuthView().toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("连接设置", systemImage: "slider.horizontal.3") { model.showSettings = true }
                        }
                    }
                }
            }
        }
        .foregroundStyle(Sakura.ink)
        .task { await model.bootstrap() }
        .fullScreenCover(item: $model.presentedPractice, onDismiss: {
            Task { await model.refresh() }
        }) { practice in
            PracticeFlow(practice: practice).environment(model)
        }
        .sheet(isPresented: $model.showSettings) { ServerSettingsView().environment(model) }
    }

    private var mainTabs: some View {
        TabView {
            Tab("练习", systemImage: "square.grid.2x2.fill") { HomeView() }
            Tab("错题", systemImage: "bookmark.fill") { WrongQuestionsView() }
            Tab("我的", systemImage: "person.crop.circle") { ProfileView() }
        }
    }
}
