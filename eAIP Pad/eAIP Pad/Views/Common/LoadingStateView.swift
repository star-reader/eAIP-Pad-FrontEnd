import SwiftUI

// MARK: - 状态图标与入场过渡
struct StateSymbolView: View {
    let systemImage: String
    var tint: Color = .blue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var symbolSize = 52
    @State private var appeared = false

    var body: some View {
        Image(systemName: AppSymbols.stateSymbol(systemImage))
            .font(.system(size: min(symbolSize, 72), weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint.gradient)
            .frame(width: min(symbolSize, 72) * 1.3, height: min(symbolSize, 72) * 1.15)
            .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
            .symbolEffectsRemoved(reduceMotion)
            .accessibilityHidden(true)
            .onAppear { appeared = true }
    }
}

struct StateEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : 8)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
                    appeared = true
                }
            }
    }
}

// MARK: - 图标、标题与说明的统一层级
struct StateMessageContent: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    var tint: Color = .blue

    var body: some View {
        VStack(spacing: 20) {
            StateSymbolView(systemImage: systemImage, tint: tint)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 340)
        .modifier(StateEntranceModifier())
    }
}

// MARK: - 通用加载状态视图
struct LoadingStateView<Content: View>: View {
    let isLoading: Bool
    let errorMessage: String?
    let retryAction: (() async -> Void)?
    let loadingMessage: String
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isLoading: Bool,
        errorMessage: String? = nil,
        loadingMessage: String = "加载中…",
        retryAction: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.loadingMessage = loadingMessage
        self.retryAction = retryAction
        self.content = content
    }

    private var isMissingLocalData: Bool {
        guard let errorMessage else { return false }
        return AIRACHelper.isMissingDataError(errorMessage)
    }

    private var phase: Int {
        if isLoading { return 0 }
        if isMissingLocalData { return 1 }
        return errorMessage == nil ? 3 : 2
    }

    var body: some View {
        ZStack {
            if isLoading {
                LoadingIndicatorView(message: loadingMessage)
                    .transition(.opacity)
            } else if isMissingLocalData {
                NoLocalDataStateView()
                    .transition(.opacity)
            } else if let errorMessage {
                ErrorStateView(message: errorMessage, retryAction: retryAction)
                    .transition(.opacity)
            } else {
                content()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
    }
}

struct LoadingIndicatorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(.blue)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(StateEntranceModifier())
    }
}

// MARK: - 错误状态视图
struct ErrorStateView: View {
    let message: String
    var icon: String = "exclamationmark.triangle.fill"
    var retryAction: (() async -> Void)? = nil
    @State private var isRetrying = false

    var body: some View {
        EmptyStateView(
            title: "暂时无法加载",
            systemImage: icon,
            description: message,
            tint: .orange,
            actionTitle: retryAction == nil ? nil : "重试"
        ) {
            guard let retryAction, !isRetrying else { return }
            isRetrying = true
            Task {
                await retryAction()
                isRetrying = false
            }
        }
        .disabled(isRetrying)
    }
}

// MARK: - 空状态：优先居中，小屏与大字体下允许滚动
struct EmptyStateView: View {
    let title: String
    var systemImage: String = "tray.fill"
    var description: String? = nil
    var tint: Color = .blue
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                message
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: some View {
        VStack(spacing: 24) {
            StateMessageContent(
                title: title, systemImage: systemImage,
                description: description, tint: tint
            )

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(CompactCapsuleButtonStyle())
            }
        }
        .padding(24)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct NoLocalDataStateView: View {
    var body: some View {
        EmptyStateView(
            title: "暂无本地数据",
            systemImage: "tray.and.arrow.down.fill",
            description: "前往「个人」导入 AIRAC 数据包，\n即可离线浏览航图与文档。"
        )
    }
}

struct SearchEmptyStateView: View {
    @Binding var searchText: String
    let title: String
    let systemImage: String
    let description: String

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        EmptyStateView(
            title: isSearching ? "没有找到相关内容" : title,
            systemImage: isSearching ? "magnifyingglass" : systemImage,
            description: isSearching ? "试试其他关键词，或调整筛选条件。" : description,
            actionTitle: isSearching ? "清除搜索" : nil,
            action: isSearching ? { searchText = "" } : nil
        )
    }
}

#Preview("No Local Data State") {
    NoLocalDataStateView()
}

#Preview("Error State") {
    ErrorStateView(message: "无法读取文件，请重新选择数据包。", retryAction: {})
}

#Preview("Search State") {
    SearchEmptyStateView(
        searchText: .constant("ZBAA"), title: "暂无机场数据",
        systemImage: "airplane", description: "导入 AIRAC 数据包后即可查看机场。"
    )
}
