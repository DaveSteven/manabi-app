import SwiftUI

enum Sakura {
    static let rose = Color.accentColor
    static let blossom = Color(red: 0.91, green: 0.63, blue: 0.68)
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.085, blue: 0.095, alpha: 1) : UIColor(red: 1, green: 0.973, blue: 0.969, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.16, green: 0.14, blue: 0.15, alpha: 1) : .white
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.96, green: 0.92, blue: 0.93, alpha: 1) : UIColor(red: 0.21, green: 0.17, blue: 0.19, alpha: 1)
    })
    static let muted = Color.secondary
    static let success = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.49, green: 0.80, blue: 0.66, alpha: 1) : UIColor(red: 0.19, green: 0.43, blue: 0.34, alpha: 1)
    })
}

struct SakuraBackground: View {
    var body: some View {
        Sakura.canvas
            .overlay(alignment: .topTrailing) {
                Circle().fill(Sakura.blossom.opacity(0.16)).frame(width: 310, height: 310).blur(radius: 55).offset(x: 150, y: -80)
            }
            .ignoresSafeArea()
    }
}

struct ManabiMark: View {
    var size: CGFloat = 60
    var body: some View {
        Image("ManabiLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var loading = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if loading { ProgressView().tint(.white) }
                Text(title).fontWeight(.semibold)
                if let symbol, !loading { Image(systemName: symbol) }
            }
            .font(.body)
            .frame(maxWidth: .infinity).frame(minHeight: 54)
            .foregroundStyle(.white)
            .background(Color(red: 0.725, green: 0.31, blue: 0.412).opacity(disabled ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
        .accessibilityLabel(title)
    }
}

extension View {
    func studyCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Sakura.surface, in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(Sakura.blossom.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder func sakuraGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(Sakura.blossom.opacity(0.12)), in: .rect(cornerRadius: 24))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct InlineError: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "wifi.exclamationmark").font(.subheadline).foregroundStyle(Sakura.ink)
            if let retry { Button("重试", action: retry).fontWeight(.semibold) }
        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
    }
}

private struct InlineMetricKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var inlineMetric: Bool {
        get { self[InlineMetricKey.self] }
        set { self[InlineMetricKey.self] = newValue }
    }
}

struct Metric: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.inlineMetric) private var inline
    let value: String
    let label: String
    var body: some View {
        let layout = (inline || typeSize.isAccessibilitySize) ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
        layout {
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            if inline || typeSize.isAccessibilitySize { Spacer(minLength: 16) }
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct MetricRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 18) { content() }.environment(\.inlineMetric, true)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { content().fixedSize(horizontal: true, vertical: false) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 16) { content() }.environment(\.inlineMetric, true)
            }
        }
    }
}
