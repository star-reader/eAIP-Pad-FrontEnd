import SwiftUI
import SwiftData

// MARK: - 环境键：用于在 iPad 侧边栏模式下传递选中的航图和机场
private struct SelectedChartKey: EnvironmentKey {
    static let defaultValue: Binding<ChartResponse?>? = nil
}

private struct SelectedAirportKey: EnvironmentKey {
    static let defaultValue: Binding<AirportResponse?>? = nil
}

extension EnvironmentValues {
    var selectedChartBinding: Binding<ChartResponse?>? {
        get { self[SelectedChartKey.self] }
        set { self[SelectedChartKey.self] = newValue }
    }
    
    var selectedAirportBinding: Binding<AirportResponse?>? {
        get { self[SelectedAirportKey.self] }
        set { self[SelectedAirportKey.self] = newValue }
    }
}

// MARK: - iPad 侧边栏主视图
struct MainSidebarView: View {
    @State private var selectedSidebarItem: SidebarItem? = .airports
    @State private var selectedChart: ChartResponse?
    @State private var selectedAirport: AirportResponse?
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 第一栏：侧边栏
            SidebarView(selectedItem: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } content: {
            // 第二栏：内容视图
            if let item = selectedSidebarItem {
                ContentListView(
                    selectedItem: item,
                    selectedAirport: $selectedAirport
                )
                .environment(\.selectedChartBinding, $selectedChart)
                .environment(\.selectedAirportBinding, $selectedAirport)
                .navigationSplitViewColumnWidth(min: 350, ideal: 400)
                .onChange(of: item) { oldValue, newValue in
                    // 切换页面时清空选中的航图和机场
                    if oldValue != newValue {
                        print("🔄 切换页面: \(oldValue.title) -> \(newValue.title)")
                        selectedChart = nil
                        selectedAirport = nil
                    }
                }
                .onChange(of: selectedChart) { oldValue, newValue in
                    print("📊 selectedChart 变化: ID从 \(oldValue?.id ?? -1) -> \(newValue?.id ?? -1), Type: \(newValue?.chartType ?? "nil")")
                }
            } else {
                ContentUnavailableView(
                    "选择一个项目",
                    systemImage: "sidebar.left",
                    description: Text("从侧边栏选择一个项目开始")
                )
            }
        } detail: {
            // 第三栏：详情视图
            DetailView(
                selectedItem: selectedSidebarItem,
                selectedChart: selectedChart
            )
            .id(selectedChart?.id ?? -1)  // 强制根据 selectedChart 重新创建视图
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.primaryBlue)
    }
}

// MARK: - 侧边栏项目枚举
enum SidebarItem: String, CaseIterable, Identifiable {
    case airports = "airports"
    case enroute = "enroute"
    case regulations = "regulations"
    case documents = "documents"
    case profile = "profile"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .airports: return "机场"
        case .enroute: return "航路"
        case .regulations: return "细则"
        case .documents: return "文档"
        case .profile: return "个人"
        }
    }
    
    var icon: String {
        switch self {
        case .airports: return "airplane.circle.fill"
        case .enroute: return "map.fill"
        case .regulations: return "doc.text.fill"
        case .documents: return "folder.fill"
        case .profile: return "person.fill"
        }
    }
}

// MARK: - 侧边栏视图
struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?
    
    var body: some View {
        List(selection: $selectedItem) {
            Section("") {
                Label("机场", systemImage: "airplane.circle.fill")
                    .tag(SidebarItem.airports)
                
                Label("航路", systemImage: "map.fill")
                    .tag(SidebarItem.enroute)
                
                Label("细则", systemImage: "doc.text.fill")
                    .tag(SidebarItem.regulations)
                
                Label("文档", systemImage: "folder.fill")
                    .tag(SidebarItem.documents)
                
                Label("个人", systemImage: "person.fill")
                    .tag(SidebarItem.profile)
            }
        }
        .navigationTitle("eAIP Pad")
        .listStyle(.sidebar)
    }
}

// MARK: - 内容列表视图
struct ContentListView: View {
    let selectedItem: SidebarItem
    @Binding var selectedAirport: AirportResponse?
    @Environment(\.selectedAirportBinding) private var selectedAirportBinding
    
    var body: some View {
        Group {
            switch selectedItem {
            case .airports:
                // 机场页面需要处理机场选择
                if let binding = selectedAirportBinding, let airport = selectedAirport {
                    // iPad 模式且已选中机场：显示航图列表
                    AirportDetailView(airport: airport)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    binding.wrappedValue = nil
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                        Text("机场")
                                    }
                                }
                            }
                        }
                } else {
                    // 显示机场列表
                    AirportListView()
                }
            case .enroute:
                EnrouteView()
            case .regulations:
                RegulationsView()
            case .documents:
                DocumentsView()
            case .profile:
                ProfileView()
            }
        }
    }
}

// MARK: - 详情视图
struct DetailView: View {
    let selectedItem: SidebarItem?
    let selectedChart: ChartResponse?
    
    var body: some View {
        Group {
            // 个人中心页面不在右侧显示，留空
            if selectedItem == .profile {
                placeholderView
            } else if let chart = selectedChart {
                // 显示选中的 PDF
                let documentType: DocumentType = {
                    switch chart.chartType {
                    case "AD":
                        return .ad  // AD 细则（来自 RegulationsView）
                    case "AIP":
                        return .aip  // AIP 文档
                    case "ENROUTE", "AREA":
                        return .enroute  // 航路图
                    case "SUP":
                        return .sup
                    case "AMDT":
                        return .amdt
                    case "NOTAM":
                        return .notam
                    default:
                        return .chart  // 机场航图（SID、STAR、APP 等）
                    }
                }()
                
                // 调试信息
                let _ = print("📱 DetailView - Chart ID: \(chart.id), Type: \(chart.chartType), Name: \(chart.nameCn)")
                
                PDFReaderView(
                    chartID: "\(chart.chartType.lowercased())_\(chart.id)",
                    displayName: chart.nameCn,
                    documentType: documentType
                )
                .id("\(documentType.rawValue)_\(chart.chartType)_\(chart.id)")  // 包含 documentType 确保唯一
            } else {
                // 占位符
                placeholderView
            }
        }
    }
    
    @ViewBuilder
    private var placeholderView: some View {
        if let item = selectedItem {
            switch item {
            case .airports:
                ContentUnavailableView(
                    "选择机场或航图",
                    systemImage: "airplane.circle",
                    description: Text("从左侧列表选择一个机场和航图查看")
                )
            case .enroute:
                ContentUnavailableView(
                    "选择航路图",
                    systemImage: "map",
                    description: Text("从左侧列表选择一个航路图查看")
                )
            case .regulations:
                ContentUnavailableView(
                    "选择机场细则",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("从左侧列表选择一个机场查看细则")
                )
            case .documents:
                ContentUnavailableView(
                    "选择文档",
                    systemImage: "folder",
                    description: Text("从左侧列表选择一个文档查看")
                )
            case .profile:
                EmptyView()
            }
        } else {
            ContentUnavailableView(
                "选择内容",
                systemImage: "doc.text",
                description: Text("从左侧选择项目以查看详情")
            )
        }
    }
}

#Preview("Main Sidebar") {
    MainSidebarView()
}
