import SwiftUI
import UIKit
import WebKit

struct RichText: View {
    let content: RichContent
    var fontSize: CGFloat = 18
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var webHeight: CGFloat = 48

    var body: some View {
        Group {
            if content.html.contains("<table") || content.html.contains("<ruby") {
                HTMLMaterial(content: content, size: scaledSize, dark: colorScheme == .dark, height: $webHeight)
                    .frame(maxWidth: .infinity)
                    .frame(height: webHeight)
            } else {
                NativeRichText(content: content, size: scaledSize, dark: colorScheme == .dark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(content.text)
    }

    private var scaledSize: CGFloat {
        // Read the environment so changes to system text size rebuild the representable.
        let _ = dynamicTypeSize
        return UIFontMetrics.default.scaledValue(for: fontSize)
    }
}

struct NativeRichText: UIViewRepresentable {
    let content: RichContent
    let size: CGFloat
    let dark: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let color = dark ? "#F5EBED" : "#352C30"
        let key = "\(size)-\(dark)-\(content.html)"
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        // HTML import spins a nested run loop. Keep it outside SwiftUI's layout/update
        // transaction so iOS 18 does not cache a partially laid-out practice page.
        DispatchQueue.main.async { [weak view] in
            guard let view, context.coordinator.key == key else { return }
            let markup = "<meta charset='utf-8'><style>body {font-family:-apple-system;font-size:\(size)px;color:\(color);} p,div {margin:0 0 8px;} </style>\(content.html)"
            if let attributed = try? NSAttributedString(data: Data(markup.utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) {
                let mutable = NSMutableAttributedString(attributedString: attributed)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 4
                mutable.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutable.length))
                view.attributedText = mutable
            } else {
                view.text = content.text
                view.font = .systemFont(ofSize: size)
                view.textColor = dark ? .white : .label
            }
            view.accessibilityLabel = content.text
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var key = "" }
}

struct HTMLMaterial: UIViewRepresentable {
    let content: RichContent
    let size: CGFloat
    let dark: Bool
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let script = "new ResizeObserver(() => window.webkit.messageHandlers.height.postMessage(document.body.scrollHeight)).observe(document.body);"
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: "height")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        let key = "\(size)-\(dark)-\(content.html)"
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <style>html{width:100%;}*{box-sizing:border-box;}body{width:100%;margin:0;font-family:-apple-system;font-size:\(size)px;line-height:1.6;color:\(dark ? "#F5EBED" : "#352C30");overflow-wrap:anywhere;}p,div{margin:0 0 7px}table{width:100%;table-layout:fixed;border-collapse:collapse}td,th{border:1px solid #9996;padding:6px}rt{font-size:0.55em}</style></head>
        <body>\(content.html)</body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "height")
        web.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: HTMLMaterial
        var key = ""
        init(_ parent: HTMLMaterial) { self.parent = parent }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? Double, value.isFinite, value > 0 {
                parent.height = CGFloat(value + 2)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
}
