import SwiftUI
import SwiftData
import Foundation

// MARK: - iPhone 主导航 TabView
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    
    var body: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $selectedTab) {
                // 机场模块
                AirportListView()
                    .tabItem {
                        Image(systemName: "airplane.circle.fill")
                        Text("机场")
                    }
                    .tag(0)
                
                // 航路模块
                EnrouteView()
                    .tabItem {
                        Image(systemName: "map.circle.fill")
                        Text("航路")
                    }
                    .tag(1)
                
                // 细则模块
                RegulationsView()
                    .tabItem {
                        Image(systemName: "doc.text.fill")
                        Text("细则")
                    }
                    .tag(2)
                
                // 文档模块
                DocumentsView()
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
            .tint(.primaryBlue) // 蓝色主题
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            TabView(selection: $selectedTab) {
                // 机场模块
                AirportListView()
                    .tabItem {
                        Image(systemName: "airplane.circle.fill")
                        Text("机场")
                    }
                    .tag(0)
                
                // 航路模块
                EnrouteView()
                    .tabItem {
                        Image(systemName: "map.circle.fill")
                        Text("航路")
                    }
                    .tag(1)
                
                // 细则模块
                RegulationsView()
                    .tabItem {
                        Image(systemName: "doc.text.fill")
                        Text("细则")
                    }
                    .tag(2)
                
                // 文档模块
                DocumentsView()
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
            .tint(.primaryBlue) // 蓝色主题
        }
    }
}
#Preview("iPhone TabView") {
    MainTabView()
}

#Preview("iPad Sidebar") {
    MainSidebarView()
}
