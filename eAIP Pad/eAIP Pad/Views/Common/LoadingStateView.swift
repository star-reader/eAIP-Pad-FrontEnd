import SwiftUI

// MARK: - 通用加载状态视图
struct LoadingStateView<Content: View>: View {
    let isLoading: Bool
    let errorMessage: String?
    let retryAction: (() async -> Void)?
    let loadingMessage: String
    @ViewBuilder let content: () -> Content
    
    init(
        isLoading: Bool,
        errorMessage: String? = nil,
        loadingMessage: String = "加载中...",
        retryAction: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.loadingMessage = loadingMessage
        self.retryAction = retryAction
        self.content = content
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView(loadingMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                ErrorStateView(
                    message: errorMessage,
                    retryAction: retryAction
                )
            } else {
                content()
            }
        }
    }
}

// MARK: - 错误状态视图
struct ErrorStateView: View {
    let message: String
    let icon: String
    let retryAction: (() async -> Void)?
    
    init(
        message: String,
        icon: String = "exclamationmark.triangle",
        retryAction: (() async -> Void)? = nil
    ) {
        self.message = message
        self.icon = icon
        self.retryAction = retryAction
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            if let retry = retryAction {
                Button("重试") {
                    Task {
                        await retry()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - 空状态视图（统一的 ContentUnavailableView 包装）
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String?
    let action: (() -> Void)?
    let actionTitle: String?
    
    init(
        title: String,
        systemImage: String = "tray",
        description: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.action = action
        self.actionTitle = actionTitle
    }
    
    var body: some View {
        if let description = description {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
        } else {
            ContentUnavailableView(
                title,
                systemImage: systemImage
            )
        }
    }
}

// MARK: - 预览
#Preview("Loading State") {
    LoadingStateView(
        isLoading: true,
        loadingMessage: "加载数据..."
    ) {
        Text("Content")
    }
}

#Preview("Error State") {
    LoadingStateView(
        isLoading: false,
        errorMessage: "加载失败，请重试"
    ) {
        Text("Content")
    }
}

#Preview("Empty State") {
    EmptyStateView(
        title: "暂无数据",
        systemImage: "tray",
        description: "这里还没有任何内容"
    )
}
