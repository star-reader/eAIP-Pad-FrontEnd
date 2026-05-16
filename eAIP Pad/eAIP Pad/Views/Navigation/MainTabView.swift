import Foundation
import SwiftData
import SwiftUI

// MARK: - iPhone 主导航 TabView
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                TabView(selection: $selectedTab) {
                    // 机场模块
                    tabContent(
                        featureName: "机场",
                        content: AirportListView()
                    )
                        .tabItem {
                            Image(systemName: "airplane.circle.fill")
                            Text("机场")
                        }
                        .tag(0)

                    // 航路模块
                    tabContent(
                        featureName: "航路",
                        content: EnrouteView()
                    )
                        .tabItem {
                            Image(systemName: "map.circle.fill")
                            Text("航路")
                        }
                        .tag(1)

                    // 细则模块
                    tabContent(
                        featureName: "细则",
                        content: RegulationsView()
                    )
                        .tabItem {
                            Image(systemName: "doc.text.fill")
                            Text("细则")
                        }
                        .tag(2)

                    // 文档模块
                    tabContent(
                        featureName: "文档",
                        content: DocumentsView()
                    )
                        .tabItem {
                            Image(systemName: "folder.circle.fill")
                            Text("文档")
                        }
                        .tag(3)

                    // 个人中心
                    NavigationStack {
                        ProfileView()
                    }
                    .tabItem {
                        Image(systemName: "person.circle.fill")
                        Text("个人")
                    }
                    .tag(4)
                }
                .tint(.primaryBlue)  // 蓝色主题
                .tabBarMinimizeBehavior(.onScrollDown)
            } else {
                TabView(selection: $selectedTab) {
                    // 机场模块
                    tabContent(
                        featureName: "机场",
                        content: AirportListView()
                    )
                        .tabItem {
                            Image(systemName: "airplane.circle.fill")
                            Text("机场")
                        }
                        .tag(0)

                    // 航路模块
                    tabContent(
                        featureName: "航路",
                        content: EnrouteView()
                    )
                        .tabItem {
                            Image(systemName: "map.circle.fill")
                            Text("航路")
                        }
                        .tag(1)

                    // 细则模块
                    tabContent(
                        featureName: "细则",
                        content: RegulationsView()
                    )
                        .tabItem {
                            Image(systemName: "doc.text.fill")
                            Text("细则")
                        }
                        .tag(2)

                    // 文档模块
                    tabContent(
                        featureName: "文档",
                        content: DocumentsView()
                    )
                        .tabItem {
                            Image(systemName: "folder.circle.fill")
                            Text("文档")
                        }
                        .tag(3)

                    // 个人中心
                    NavigationStack {
                        ProfileView()
                    }
                    .tabItem {
                        Image(systemName: "person.circle.fill")
                        Text("个人")
                    }
                    .tag(4)
                }
                .tint(.primaryBlue)  // 蓝色主题
            }
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(featureName: String, content: Content) -> some View {
        content
    }
}

#Preview("iPhone TabView") {
    MainTabView()
}

#Preview("iPad Sidebar") {
    MainSidebarView()
}
