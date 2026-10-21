import SwiftUI

private struct AIRACPageActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isAIRACPageActive: Bool {
        get { self[AIRACPageActiveKey.self] }
        set { self[AIRACPageActiveKey.self] = newValue }
    }
}

/// 只创建访问过的页面，切换时保留视图身份、导航、搜索和滚动状态。
struct KeepAlivePages<Selection: Hashable, Content: View>: View {
    let selection: Selection
    let pages: [Selection]
    @ViewBuilder let content: (Selection) -> Content
    @State private var visited: Set<Selection> = []
    @Environment(\.isAIRACPageActive) private var parentIsActive

    var body: some View {
        ZStack { retainedPages }
            .onChange(of: selection, initial: true) { _, selected in visited.insert(selected) }
    }

    private var retainedPages: some View {
        ForEach(pages, id: \.self) { page in
            if visited.contains(page) || page == selection {
                content(page)
                    .environment(\.isAIRACPageActive, parentIsActive && page == selection)
                    .opacity(page == selection ? 1 : 0)
                    .allowsHitTesting(page == selection)
                    .accessibilityHidden(page != selection)
                    .zIndex(page == selection ? 1 : 0)
                    .tag(page)
            }
        }
    }
}

private struct AIRACPageTaskModifier: ViewModifier {
    let key: String
    let action: @MainActor () async -> Void
    @Environment(\.isAIRACPageActive) private var isActive

    private struct TaskID: Equatable {
        let key: String
        let isActive: Bool
    }

    func body(content: Content) -> some View {
        content.task(id: TaskID(key: key, isActive: isActive)) {
            guard isActive else { return }
            await action()
        }
    }
}

extension View {
    /// 隐藏页只失效、不自动联网；激活后由页面模型判断是否需要加载。
    func airacPageTask(key: String, action: @escaping @MainActor () async -> Void) -> some View {
        modifier(AIRACPageTaskModifier(key: key, action: action))
    }
}

private struct AIRACColumnTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var airacColumnTitle: String? {
        get { self[AIRACColumnTitleKey.self] }
        set { self[AIRACColumnTitleKey.self] = newValue }
    }
}

/// iPad 每个分栏只拥有一个 NavigationStack；iPhone 页面沿用自己的导航栈。
struct AIRACNavigationContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.columnVisibilityBinding) private var columnVisibility

    var body: some View {
        if columnVisibility == nil {
            NavigationStack { content() }
        } else {
            content()
        }
    }
}

private struct AIRACNavigationTitleModifier: ViewModifier {
    let title: String
    let displayMode: NavigationBarItem.TitleDisplayMode
    @Environment(\.airacColumnTitle) private var columnTitle

    func body(content: Content) -> some View {
        content.navigationTitle(columnTitle ?? title)
            .navigationBarTitleDisplayMode(columnTitle == nil ? displayMode : .inline)
    }
}

extension View {
    func airacNavigationTitle(_ title: String, displayMode: NavigationBarItem.TitleDisplayMode = .large) -> some View {
        modifier(AIRACNavigationTitleModifier(title: title, displayMode: displayMode))
    }
}
