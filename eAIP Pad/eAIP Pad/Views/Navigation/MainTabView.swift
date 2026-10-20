import SwiftUI

// MARK: - iPhone 主导航，图标与 iPad 侧边栏保持一致
struct MainTabView: View {
    @State private var selectedTab: SidebarItem = .airports

    var body: some View {
        if #available(iOS 26.0, *) {
            tabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(SidebarItem.allCases) { item in
                page(for: item)
                    .tabItem {
                        Label(item.title, systemImage: item.icon)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .tag(item)
            }
        }
        .tint(.primaryBlue)
    }

    @ViewBuilder
    private func page(for item: SidebarItem) -> some View {
        switch item {
        case .airports: AirportListView()
        case .enroute: EnrouteView()
        case .regulations: RegulationsView()
        case .documents: DocumentsView()
        case .profile:
            NavigationStack { ProfileView() }
        }
    }
}

#Preview("iPhone TabView") {
    MainTabView()
}

#Preview("iPad Sidebar") {
    MainSidebarView()
}
