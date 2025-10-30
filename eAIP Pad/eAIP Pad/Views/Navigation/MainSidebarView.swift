import SwiftUI
import SwiftData

// MARK: - iPad 侧边栏主视图
struct MainSidebarView: View {
    @Query private var pinnedCharts: [PinnedChart]
    @State private var selectedSidebarItem: SidebarItem = .airports
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 侧边栏
            SidebarView(selectedItem: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } content: {
            // 内容列表
            ContentListView(selectedItem: selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 350, ideal: 400)
        } detail: {
            // 详情视图
            DetailView(selectedItem: selectedSidebarItem)
        }
        .tint(.primaryBlue)
    }
}

// MARK: - 侧边栏项目枚举
enum SidebarItem: String, CaseIterable, Identifiable {
    case airports = "airports"
    case enroute = "enroute"
    case pinboard = "pinboard"
    case documents = "documents"
    case profile = "profile"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .airports: return "机场"
        case .enroute: return "航路"
        case .pinboard: return "收藏"
        case .documents: return "文档"
        case .profile: return "个人"
        }
    }
    
    var icon: String {
        switch self {
        case .airports: return "airplane.circle.fill"
        case .enroute: return "map.circle.fill"
        case .pinboard: return "pin.circle.fill"
        case .documents: return "folder.circle.fill"
        case .profile: return "person.circle.fill"
        }
    }
}

// MARK: - 侧边栏视图
struct SidebarView: View {
    @Binding var selectedItem: SidebarItem
    @Query private var pinnedCharts: [PinnedChart]
    
    // 主要功能部分
    @ViewBuilder
    private var mainFeaturesSection: some View {
        Section("主要功能") {
            let mainItems = Array(SidebarItem.allCases.dropLast())
            ForEach(mainItems, id: \.self) { item in
                #if os(iOS)
                Button {
                    selectedItem = item
                } label: {
                    Label(item.title, systemImage: item.icon)
                }
                .badge(item == .pinboard ? pinnedCharts.count : 0)
                .tag(item)
                #else
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.icon)
                }
                .badge(item == .pinboard ? pinnedCharts.count : 0)
                #endif
            }
        }
    }
    
    // 个人中心部分
    @ViewBuilder
    private var profileSection: some View {
        Section {
            #if os(iOS)
            Button {
                selectedItem = .profile
            } label: {
                Label("个人中心", systemImage: "person.circle.fill")
            }
            #else
            NavigationLink(value: SidebarItem.profile) {
                Label("个人中心", systemImage: "person.circle.fill")
            }
            #endif
        }
    }
    
    // 快速收藏部分
    @ViewBuilder
    private var quickFavoritesSection: some View {
        Section("快速收藏") {
            ForEach(Array(pinnedCharts.prefix(5)), id: \.chartID) { chart in
                NavigationLink {
                    // TODO: 打开航图详情
                    Text("航图详情: \(chart.displayName)")
                } label: {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.primaryBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chart.displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                            if !chart.icao.isEmpty {
                                Text(chart.icao)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            if pinnedCharts.count > 5 {
                NavigationLink {
                    PinboardView()
                } label: {
                    HStack {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                        Text("查看全部 \(pinnedCharts.count) 个收藏")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    var body: some View {
        #if os(iOS)
        List {
            mainFeaturesSection
            
            if !pinnedCharts.isEmpty {
                quickFavoritesSection
            }
            
            profileSection
        }
        .navigationTitle("eAIP Pad")
        .listStyle(SidebarListStyle())
        #else
        List(selection: $selectedItem) {
            mainFeaturesSection
            
            if !pinnedCharts.isEmpty {
                quickFavoritesSection
            }
            
            profileSection
        }
        .navigationTitle("eAIP Pad")
        .listStyle(SidebarListStyle())
        #endif
    }
}

// MARK: - 内容列表视图
struct ContentListView: View {
    let selectedItem: SidebarItem
    
    var body: some View {
        Group {
            switch selectedItem {
            case .airports:
                AirportListView()
            case .enroute:
                EnrouteView()
            case .pinboard:
                PinboardView()
            case .documents:
                DocumentsView()
            case .profile:
                ProfileView()
            }
        }
        .navigationTitle(selectedItem.title)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - 详情视图
struct DetailView: View {
    let selectedItem: SidebarItem
    
    var body: some View {
        Group {
            switch selectedItem {
            case .airports:
                AirportDetailPlaceholder()
            case .enroute:
                EnrouteDetailPlaceholder()
            case .pinboard:
                PinboardDetailPlaceholder()
            case .documents:
                DocumentDetailPlaceholder()
            case .profile:
                ProfileDetailPlaceholder()
            }
        }
    }
}

// MARK: - 占位符详情视图
struct AirportDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "选择机场",
            systemImage: "airplane.circle",
            description: Text("从左侧列表选择一个机场查看详情")
        )
        .foregroundColor(.primaryBlue)
    }
}

struct EnrouteDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "选择航路图",
            systemImage: "map.circle",
            description: Text("从左侧列表选择一个航路图查看详情")
        )
        .foregroundColor(.primaryBlue)
    }
}

struct PinboardDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "选择收藏",
            systemImage: "pin.circle",
            description: Text("从左侧列表选择一个收藏查看详情")
        )
        .foregroundColor(.primaryBlue)
    }
}

struct DocumentDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "选择文档",
            systemImage: "folder.circle",
            description: Text("从左侧列表选择一个文档查看详情")
        )
        .foregroundColor(.primaryBlue)
    }
}

struct ProfileDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "个人中心",
            systemImage: "person.circle",
            description: Text("管理您的账户和设置")
        )
        .foregroundColor(.primaryBlue)
    }
}

#Preview("Main Sidebar") {
    MainSidebarView()
}
