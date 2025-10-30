import SwiftUI
import SwiftData
import Foundation

// MARK: - iPhone 主导航 TabView
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pinnedCharts: [PinnedChart]
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 机场模块
            AirportListView()
                .tabItem {
                    Image(systemName: "airplane")
                    Text("机场")
                }
                .tag(0)
            
            // 航路模块
            EnrouteView()
                .tabItem {
                    Image(systemName: "map")
                    Text("航路")
                }
                .tag(1)
            
            // 细则模块
            RegulationsView()
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("细则")
                }
                .tag(2)
            
            // 文档模块
            DocumentsView()
                .tabItem {
                    Image(systemName: "folder")
                    Text("文档")
                }
                .tag(3)
            
            // 个人中心
            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("个人")
                }
                .tag(4)
        }
        .accentColor(.orange) // 航空橙色主题
        .overlay(alignment: .bottom) {
            // Pinboard 紧凑模式悬浮条
            if !pinnedCharts.isEmpty {
                PinboardCompactView()
                    .padding(.bottom, 90) // 避免遮挡 TabBar
            }
        }
    }
}

// MARK: - iPad 主导航 Sidebar
struct MainSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pinnedCharts: [PinnedChart]
    @Query private var userSettings: [UserSettings]
    @State private var selectedSidebarItem: SidebarItem? = .airports
    
    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }
    
    var body: some View {
        NavigationSplitView {
            // 侧边栏
            List(SidebarItem.allCases, id: \.self, selection: $selectedSidebarItem) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.iconName)
                }
            }
            .navigationTitle("eAIP Pad")
            .navigationBarTitleDisplayMode(.large)
            
            // Pinboard 侧边栏区域
            if !pinnedCharts.isEmpty {
                Section("快速访问") {
                    ForEach(pinnedCharts.prefix(5)) { pin in
                        NavigationLink {
                            // 跳转到对应的PDF阅读器
                            PDFReaderView(
                                chartID: pin.chartID,
                                displayName: pin.displayName,
                                documentType: DocumentType(rawValue: pin.documentType) ?? .chart
                            )
                        } label: {
                            HStack {
                                Image(systemName: iconForDocumentType(pin.documentType))
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pin.displayName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(pin.icao)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        } detail: {
            // 详情视图
            Group {
                switch selectedSidebarItem {
                case .airports:
                    AirportListView()
                case .enroute:
                    EnrouteView()
                case .regulations:
                    RegulationsView()
                case .documents:
                    DocumentsView()
                case .profile:
                    ProfileView()
                case .none:
                    Text("选择一个模块")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    private func iconForDocumentType(_ type: String) -> String {
        switch type {
        case "chart": return "airplane"
        case "enroute": return "map"
        case "aip": return "doc.text"
        case "sup": return "exclamationmark.triangle"
        case "amdt": return "pencil.and.outline"
        case "notam": return "bell"
        default: return "doc"
        }
    }
}

// MARK: - 侧边栏项目枚举
enum SidebarItem: String, CaseIterable {
    case airports = "airports"
    case enroute = "enroute"
    case regulations = "regulations"
    case documents = "documents"
    case profile = "profile"
    
    var title: String {
        switch self {
        case .airports: return "机场"
        case .enroute: return "航路"
        case .regulations: return "细则"
        case .documents: return "文档"
        case .profile: return "个人"
        }
    }
    
    var iconName: String {
        switch self {
        case .airports: return "airplane"
        case .enroute: return "map"
        case .regulations: return "doc.text"
        case .documents: return "folder"
        case .profile: return "person.circle"
        }
    }
}

#Preview("iPhone TabView") {
    MainTabView()
        .modelContainer(for: PinnedChart.self, inMemory: true)
}

#Preview("iPad Sidebar") {
    MainSidebarView()
        .modelContainer(for: PinnedChart.self, inMemory: true)
}
