import SwiftData
import SwiftUI

// MARK: - 环境键：用于在 iPad 侧边栏模式下传递选中的航图和机场
private struct SelectedChartKey: EnvironmentKey {
    static let defaultValue: Binding<ChartResponse?>? = nil
}

private struct SelectedAirportKey: EnvironmentKey {
    static let defaultValue: Binding<AirportResponse?>? = nil
}

private struct ColumnVisibilityKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationSplitViewVisibility>? = nil
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

    var columnVisibilityBinding: Binding<NavigationSplitViewVisibility>? {
        get { self[ColumnVisibilityKey.self] }
        set { self[ColumnVisibilityKey.self] = newValue }
    }
}

// MARK: - iPad 侧边栏主视图
struct MainSidebarView: View {
    @ObservedObject private var airacService = AIRACService.shared
    @State private var selectedSidebarItem: SidebarItem? = .airports
    @State private var selectedCharts: [SidebarItem: ChartResponse] = [:]
    @State private var selectedAirport: AirportResponse?
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 第一栏：侧边栏（缩小宽度以节省空间）
            SidebarView(selectedItem: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 140, ideal: 260, max: 200)
        } content: {
            NavigationStack {
                KeepAlivePages(selection: selectedSidebarItem ?? .airports, pages: SidebarItem.allCases) { item in
                    ContentListView(selectedItem: item, selectedAirport: $selectedAirport)
                        .environment(\.selectedChartBinding, chartSelection(for: item))
                        .environment(\.selectedAirportBinding, $selectedAirport)
                }
                .environment(\.columnVisibilityBinding, $columnVisibility)
                .environment(\.airacColumnTitle, contentTitle)
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 450)
        } detail: {
            NavigationStack {
                KeepAlivePages(selection: selectedSidebarItem ?? .airports, pages: SidebarItem.allCases) { item in
                    DetailView(selectedItem: item, selectedChart: selectedCharts[item])
                }
                .environment(\.columnVisibilityBinding, $columnVisibility)
                .environment(\.airacColumnTitle, selectedCharts[selectedSidebarItem ?? .airports]?.nameCn ?? "")
                .navigationTitle(selectedCharts[selectedSidebarItem ?? .airports]?.nameCn ?? "")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.primaryBlue)
        .onChange(of: airacService.dataRevision) { _, _ in
            selectedCharts.removeAll()
            selectedAirport = nil
        }
    }

    private var contentTitle: String {
        switch selectedSidebarItem ?? .airports {
        case .airports: return selectedAirport?.icao ?? "机场"
        case .enroute: return "航路图"
        case .regulations: return "机场细则"
        case .documents: return "文档"
        case .profile: return "个人"
        }
    }

    private func chartSelection(for item: SidebarItem) -> Binding<ChartResponse?> {
        Binding(get: { selectedCharts[item] }, set: { selectedCharts[item] = $0 })
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
        case .airports: return AppSymbols.airport
        case .enroute: return AppSymbols.enroute
        case .regulations: return AppSymbols.regulations
        case .documents: return AppSymbols.documents
        case .profile: return AppSymbols.profile
        }
    }
}

// MARK: - 侧边栏视图
struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?

    var body: some View {
        List(selection: $selectedItem) {
            Section("") {
                ForEach(SidebarItem.allCases) { item in
                    Label {
                        Text(item.title)
                    } icon: {
                        NavigationSymbolView(
                            systemImage: item.icon, isSelected: selectedItem == item
                        )
                    }
                    .tag(item)
                }
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
    @Environment(\.isAIRACPageActive) private var isPageActive

    var body: some View {
        Group {
            switch selectedItem {
            case .airports:
                KeepAlivePages(selection: selectedAirport != nil, pages: [false, true]) { showsDetails in
                    if showsDetails {
                        if let binding = selectedAirportBinding, let airport = selectedAirport {
                            AIRACNavigationContainer {
                                AirportDetailView(airport: airport)
                                    .toolbar {
                                        if isPageActive {
                                        ToolbarItem(placement: .navigationBarLeading) {
                                            Button("机场", systemImage: "chevron.left") {
                                                binding.wrappedValue = nil
                                            }
                                        }
                                        }
                                    }
                            }
                            .id(airport.icao)
                        }
                    } else {
                        AirportListView()
                    }
                }
            case .enroute:
                EnrouteView()
            case .regulations:
                RegulationsView()
            case .documents:
                DocumentsView()
            case .profile:
                AIRACNavigationContainer { ProfileView() }
            }
        }
    }
}

// MARK: - 详情视图
struct DetailView: View {
    let selectedItem: SidebarItem?
    let selectedChart: ChartResponse?

    @ViewBuilder
    var body: some View {
        // 个人中心页面不在右侧显示，留空
        if selectedItem == .profile {
            placeholderView.airacNavigationTitle("", displayMode: .inline)
        } else if let chart = selectedChart {
            // 与 iPhone 使用相同的文档来源和标识，读取正确缓存并共享收藏、标注。
            PDFReaderView(
                chartID: chart.readerChartID,
                displayName: chart.nameCn,
                documentType: chart.readerDocumentType,
                airacVersion: chart.airacVersion
            )
            .id(chart.readerChartID)
        } else {
            // 空白状态自有导航容器，不继承其他页面的文档标题或工具栏。
            placeholderView.airacNavigationTitle("", displayMode: .inline)
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let item = selectedItem {
            switch item {
            case .airports:
                EmptyStateView(
                    title: "选择机场或航图",
                    systemImage: "airplane.circle",
                    description: "从左侧列表选择一个机场和航图查看"
                )
            case .enroute:
                EmptyStateView(
                    title: "选择航路图",
                    systemImage: "map",
                    description: "从左侧列表选择一个航路图查看"
                )
            case .regulations:
                EmptyStateView(
                    title: "选择机场细则",
                    systemImage: "doc.text.magnifyingglass",
                    description: "从左侧列表选择一个机场查看细则"
                )
            case .documents:
                EmptyStateView(
                    title: "选择文档",
                    systemImage: "folder",
                    description: "从左侧列表选择一个文档查看"
                )
            case .profile:
                EmptyView()
            }
        } else {
            EmptyStateView(
                title: "选择内容",
                systemImage: "doc.text",
                description: "从左侧选择项目以查看详情"
            )
        }
    }
}

#Preview("Main Sidebar") {
    MainSidebarView()
}

