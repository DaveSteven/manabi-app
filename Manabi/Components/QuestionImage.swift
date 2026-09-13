import SwiftUI

struct QuestionImage: View {
    let url: URL
    let examID: String
    @Environment(AppModel.self) private var model
    @State private var enlarged = false
    @State private var reloadID = UUID()
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let image {
                Button { enlarged = true } label: { Image(uiImage: image).resizable().scaledToFit() }
                    .buttonStyle(.plain).accessibilityLabel("放大查看题目配图")
                Button { enlarged = true } label: { Label("放大查看", systemImage: "plus.magnifyingglass").font(.caption) }
            } else if failed {
                VStack(spacing: 10) {
                    Label("图片加载失败", systemImage: "photo.badge.exclamationmark").font(.footnote)
                    Button("重试") { reloadID = UUID() }
                }.frame(maxWidth: .infinity).padding()
            } else { ProgressView().frame(maxWidth: .infinity).padding(30) }
        }.studyCard(padding: 12)
            .sheet(isPresented: $enlarged) { if let image { ImageDetail(image: image) } }
            .task(id: "\(url.absoluteString)-\(reloadID)") {
                image = nil
                failed = false
                do {
                    let source = try await model.cachedMediaURL(url, examID: examID)
                    let data: Data
                    if source.isFileURL {
                        data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: source) }.value
                    } else {
                        let (received, response) = try await URLSession.shared.data(from: source)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ResourceCacheError.invalidResponse }
                        data = received
                    }
                    try Task.checkCancellation()
                    guard let decoded = UIImage(data: data) else { throw ResourceCacheError.invalidResponse }
                    image = decoded
                } catch { if !Task.isCancelled { failed = true } }
            }
    }
}

private struct ImageDetail: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var previousScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: max(100, geometry.size.width - 24) * scale)
                        .gesture(MagnifyGesture().onChanged { value in scale = min(5, max(1, previousScale * value.magnification)) }
                            .onEnded { _ in previousScale = scale })
                        .padding(12)
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
