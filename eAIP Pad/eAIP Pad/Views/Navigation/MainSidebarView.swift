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
    @State private var selectedSidebarItem: SidebarItem? = .airports
    @State private var selectedChart: ChartResponse?
    @State private var selectedAirport: AirportResponse?
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @StateObject private var authService = AuthenticationService.shared
    @State private var showingLoginSheet = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 第一栏：侧边栏（缩小宽度以节省空间）
            SidebarView(selectedItem: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 140, ideal: 260, max: 200)
        } content: {
            // 第二栏：内容视图
            if let item = selectedSidebarItem {
                ContentListView(
                    selectedItem: item,
                    selectedAirport: $selectedAirport,
                    onLoginRequired: {
                        showingLoginSheet = true
                    }
                )
                .environment(\.selectedChartBinding, $selectedChart)
                .environment(\.selectedAirportBinding, $selectedAirport)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 450)
                .id(item.rawValue)  // 强制在切换页面时重新创建视图
                .onChange(of: item) { oldValue, newValue in
                    // 切换页面时清空选中的航图和机场
                    if oldValue != newValue {
                        LoggerService.shared.info(
                            module: "MainSidebarView",
                            message: "切换页面: \(oldValue.title) -> \(newValue.title)")
                        selectedChart = nil
                        selectedAirport = nil
                    }
                }
                .onChange(of: selectedChart) { oldValue, newValue in
                    LoggerService.shared.info(
                        module: "MainSidebarView",
                        message:
                            "selectedChart 变化: ID从 \(oldValue?.id ?? -1) -> \(newValue?.id ?? -1), Type: \(newValue?.chartType ?? "nil")"
                    )
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
            .environment(\.columnVisibilityBinding, $columnVisibility)
            .id(selectedChart?.id ?? -1)  // 强制根据 selectedChart 重新创建视图
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.primaryBlue)
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
    let onLoginRequired: () -> Void
    @Environment(\.selectedAirportBinding) private var selectedAirportBinding
    @StateObject private var authService = AuthenticationService.shared

    var body: some View {
        Group {
            if selectedItem != .profile && authService.authenticationState != .authenticated {
                SidebarLoginRequiredPlaceholderView(featureName: selectedItem.title) {
                    onLoginRequired()
                }
            } else {
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
                // 个人中心使用 sheet 显示设置，不需要 NavigationStack
                ProfileView()
            }
            }
        }
    }
}

private struct SidebarLoginRequiredPlaceholderView: View {
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
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.secondarySystemBackground))

                Image(placeholderImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            }
            .frame(maxWidth: 520, maxHeight: 360)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)

            VStack(spacing: 10) {
                Text("请先登录")
                    .font(.title3.weight(.semibold))

                Text("当前为游客模式，登录后可使用\(featureName)模块")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            Button {
                onLoginTapped()
            } label: {
                Label("前往登录", systemImage: "person.badge.key")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 126)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground).opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
