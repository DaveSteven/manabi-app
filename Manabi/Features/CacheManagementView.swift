import SwiftUI

private func resourceSize(_ bytes: Int64) -> String {
    bytes == 0 ? "0KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct CacheManagementView: View {
    @State private var usage = ResourceCache.Usage(totalBytes: 0)
    @State private var error: String?
    @State private var confirmClear = false
    @State private var clearing = false

    var body: some View {
        Form {
            Section("本机缓存") {
                LabeledContent("缓存总大小", value: resourceSize(usage.totalBytes))
                LabeledContent("音频占用", value: resourceSize(usage.audioBytes))
                LabeledContent("图片占用", value: resourceSize(usage.imageBytes))
            }
            Section {
                Button("清理缓存", role: .destructive) { confirmClear = true }
                    .disabled(clearing).accessibilityIdentifier("clearMediaCache")
                Text("练习中的音频和图片会自动缓存。清理时保留正在使用的资源，不影响练习记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("缓存管理").navigationBarTitleDisplayMode(.inline)
            .task { await refresh() }
            .refreshable { await refresh() }
            .alert("清理缓存？", isPresented: $confirmClear) {
                Button("取消", role: .cancel) { }
                Button("清理", role: .destructive) {
                    Task {
                        clearing = true
                        defer { clearing = false }
                        do { try await ResourceCache.shared.clearAutomatic(); await refresh() }
                        catch { self.error = "清理失败，请稍后重试。" }
                    }
                }
            } message: { Text("已缓存的音频和图片可在下次练习时重新获取。正在使用的资源会保留。") }
    }

    private func refresh() async {
        do { usage = try await ResourceCache.shared.usage(); error = nil }
        catch { self.error = "暂时无法读取缓存大小。" }
    }
}
