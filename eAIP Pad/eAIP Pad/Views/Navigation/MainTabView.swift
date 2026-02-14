import Foundation
import SwiftData
import SwiftUI

// MARK: - iPhone 主导航 TabView
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authService = AuthenticationService.shared
    @State private var selectedTab = 0
    @State private var showingLoginSheet = false

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
        .sheet(isPresented: $showingLoginSheet) {
            NavigationStack {
                LoginView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") {
                                showingLoginSheet = false
                            }
                        }
                    }
            }
        }
        .onChange(of: authService.authenticationState) { _, newState in
            if newState == .authenticated {
                showingLoginSheet = false
            }
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(featureName: String, content: Content) -> some View {
        if authService.authenticationState == .authenticated {
            content
        } else {
            LoginRequiredPlaceholderView(featureName: featureName) {
                showingLoginSheet = true
            }
        }
    }
}

private struct LoginRequiredPlaceholderView: View {
    let featureName: String
    let onLoginTapped: () -> Void

    private var placeholderImageName: String {
        switch featureName {
        case "机场": return "placeholder_airports"
        case "航路": return "placeholder_enroute"
        case "细则": return "placeholder_regulations"
        case "文档": return "placeholder_documents"
        default: return "placeholder_airports"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.secondarySystemBackground))

                Image(placeholderImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            }
            .frame(maxWidth: 360, maxHeight: 300)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 8)

            VStack(spacing: 10) {
                Text("请先登录")
                    .font(.title3.weight(.semibold))

                Text("登录后可使用\(featureName)模块的完整功能")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)

            Button {
                onLoginTapped()
            } label: {
                Label("前往登录", systemImage: "person.badge.key")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground).opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

#Preview("iPhone TabView") {
    MainTabView()
}

#Preview("iPad Sidebar") {
    MainSidebarView()
}
