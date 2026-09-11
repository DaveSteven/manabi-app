import SwiftUI

struct QuestionImage: View {
    let url: URL
    @State private var enlarged = false
    @State private var reloadId = UUID()

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    Button { enlarged = true } label: { image.resizable().scaledToFit() }
                        .buttonStyle(.plain).accessibilityLabel("放大查看题目配图")
                case .failure:
                    VStack(spacing: 10) {
                        Label("图片加载失败", systemImage: "photo.badge.exclamationmark").font(.footnote)
                        Button("重试") { reloadId = UUID() }
                    }.frame(maxWidth: .infinity).padding()
                default: ProgressView().frame(maxWidth: .infinity).padding(30)
                }
            }.id(reloadId)
            Button { enlarged = true } label: { Label("放大查看", systemImage: "plus.magnifyingglass").font(.caption) }
        }.studyCard(padding: 12)
            .sheet(isPresented: $enlarged) { ImageDetail(url: url) }
    }
}

private struct ImageDetail: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var previousScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit().frame(width: max(100, geometry.size.width - 24) * scale)
                                .gesture(MagnifyGesture().onChanged { value in scale = min(5, max(1, previousScale * value.magnification)) }
                                    .onEnded { _ in previousScale = scale })
                        } else if phase.error != nil { Text("图片暂时无法加载，请关闭后重试。").padding() }
                        else { ProgressView().padding(50) }
                    }.padding(12)
                }.background(Sakura.canvas)
            }.navigationTitle("题目配图").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { scale = max(1, scale - 0.5); previousScale = scale } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("缩小")
                        Button { scale = min(5, scale + 0.5); previousScale = scale } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("放大")
                    }
                }
        }
    }
}
