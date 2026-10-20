import SwiftUI

// MARK: - 业务图标：导航、列表和状态页使用相同语义
enum AppSymbols {
    static let airport = "airplane"
    static let enroute = "map.fill"
    static let regulations = "doc.text.fill"
    static let documents = "folder.fill"
    static let profile = "person.fill"

    static func contentSymbol(_ name: String) -> String {
        switch name {
        case "airplane.circle", "airplane.circle.fill": return airport
        case "map", "map.circle.fill": return enroute
        case "folder", "folder.circle.fill": return documents
        case "doc", "doc.text": return regulations
        case "person.circle.fill", "person.crop.circle.fill": return profile
        case "pin": return "pin.fill"
        case "pin.slash": return "pin.slash.fill"
        case "bell": return "bell.fill"
        case "exclamationmark.triangle": return "exclamationmark.triangle.fill"
        default: return name
        }
    }

    static func stateSymbol(_ name: String) -> String {
        contentSymbol(name)
    }
}

extension DocumentType {
    var symbolName: String {
        switch self {
        case .chart: return AppSymbols.airport
        case .enroute: return AppSymbols.enroute
        case .aip, .ad: return AppSymbols.regulations
        case .sup: return "doc.badge.ellipsis"
        case .amdt: return "square.and.pencil"
        case .notam: return "bell.fill"
        }
    }

    var symbolTint: Color {
        switch self {
        case .chart, .enroute, .aip: return .blue
        case .ad: return .indigo
        case .sup: return .orange
        case .amdt: return .green
        case .notam: return .purple
        }
    }
}

extension PinnedChart {
    var documentSymbol: String {
        DocumentType(rawValue: documentType)?.symbolName ?? AppSymbols.regulations
    }

    var documentSymbolTint: Color {
        DocumentType(rawValue: documentType)?.symbolTint ?? .blue
    }
}

// MARK: - 列表与功能入口图标
struct AppSymbolView: View {
    enum Size {
        case compact, regular, large

        var edge: CGFloat {
            switch self {
            case .compact: return 24
            case .regular: return 30
            case .large: return 40
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .compact: return 17
            case .regular: return 21
            case .large: return 28
            }
        }
    }

    let systemImage: String
    var tint: Color = .blue
    var size: Size = .regular
    @ScaledMetric(relativeTo: .body) private var scale = 1.0

    private var edge: CGFloat { size.edge * min(scale, 1.35) }

    var body: some View {
        Image(systemName: AppSymbols.contentSymbol(systemImage))
            .font(.system(size: size.fontSize * min(scale, 1.35), weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint.gradient)
            .frame(width: edge, height: edge)
            .accessibilityHidden(true)
    }
}

// MARK: - 导航选中反馈：只在选中时播放，不随列表滚动重复播放
struct NavigationSymbolView: View {
    let systemImage: String
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionPulse = 0

    var body: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.body.weight(.medium))
            .symbolEffect(.bounce, options: .nonRepeating, value: selectionPulse)
            .symbolEffectsRemoved(reduceMotion)
            .onChange(of: isSelected) { _, selected in
                if selected { selectionPulse += 1 }
            }
            .accessibilityHidden(true)
    }
}

struct PinSymbolView: View {
    let isPinned: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pinPulse = 0

    var body: some View {
        Image(systemName: isPinned ? "pin.fill" : "pin")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isPinned ? Color.orange : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: pinPulse)
            .symbolEffectsRemoved(reduceMotion)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isPinned)
            .onChange(of: isPinned) { _, pinned in
                if pinned { pinPulse += 1 }
            }
            .accessibilityHidden(true)
    }
}
