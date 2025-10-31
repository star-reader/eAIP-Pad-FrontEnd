import SwiftUI
import SwiftData
import Foundation

// MARK: - 机场详情视图
struct AirportDetailView: View {
    let airport: AirportResponse
    @Environment(\.modelContext) private var modelContext
    @State private var charts: [ChartResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChartType: ChartType = .all
    
    // 过滤后的航图列表
    private var filteredCharts: [ChartResponse] {
        // 过滤掉 OTHERS 类型
        let nonOthersCharts = charts.filter { $0.chartType != "OTHERS" }
        
        if selectedChartType == .all {
            return nonOthersCharts
        } else {
            return nonOthersCharts.filter { $0.chartType == selectedChartType.rawValue }
        }
    }
    
    // 按类型分组的航图
    private var groupedCharts: [ChartType: [ChartResponse]] {
        Dictionary(grouping: filteredCharts) { chart in
            ChartType(rawValue: chart.chartType) ?? .others
        }
    }
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("加载航图数据...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task {
                            await loadCharts()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // 机场信息卡片
                    AirportInfoCard(airport: airport)
                        .padding()
                    
                    // 使用原生 Picker 作为分段控制器
                    Picker("航图类型", selection: $selectedChartType) {
                        ForEach(ChartType.allCases, id: \.self) { type in
                            if (type != .others) {
                                Text(type.displayName).tag(type)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    // 航图列表
                    List {
                        if selectedChartType == .all {
                            // 分组显示
                            ForEach(ChartType.allCases.filter { $0 != .all }, id: \.self) { type in
                                if let chartsForType = groupedCharts[type], !chartsForType.isEmpty {
                                    Section(type.displayName) {
                                        ForEach(chartsForType, id: \.id) { chart in
                                            ChartRowView(chart: chart)
                                        }
                                    }
                                }
                            }
                        } else {
                            // 单一类型显示
                            ForEach(filteredCharts, id: \.id) { chart in
                                ChartRowView(chart: chart)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    PinboardToolbarButton()
                    
                    Button {
                        Task {
                            await loadCharts()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            await loadCharts()
        }
    }
    
    private func loadCharts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取当前 AIRAC 版本
            guard let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "AirportDetail", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }
            
            // 使用机场 ICAO 作为缓存键
            let cacheKey = "charts_\(airport.icao)"
            
            // 1. 先尝试从缓存加载
            if let cachedCharts = PDFCacheService.shared.loadCachedData(
                [ChartResponse].self,
                airacVersion: currentAIRAC,
                dataType: cacheKey
            ) {
                await MainActor.run {
                    self.charts = cachedCharts
                    syncChartsToLocal(cachedCharts)
                }
                isLoading = false
                return
            }
            
            // 2. 缓存未命中，从网络获取
            let response = try await NetworkService.shared.getAirportCharts(icao: airport.icao)
            
            // 3. 保存到缓存
            try? PDFCacheService.shared.cacheData(
                response,
                airacVersion: currentAIRAC,
                dataType: cacheKey
            )
            
            await MainActor.run {
                self.charts = response
                
                // 同步到本地 SwiftData
                syncChartsToLocal(response)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载航图数据失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    private func syncChartsToLocal(_ charts: [ChartResponse]) {
        for chartResponse in charts {
            // 检查是否已存在
            let existingCharts = try? modelContext.fetch(
                FetchDescriptor<LocalChart>(
                    predicate: #Predicate { $0.documentID == chartResponse.documentId }
                )
            )
            
            if existingCharts?.isEmpty ?? true {
                let chart = LocalChart(
                    chartID: "chart_\(chartResponse.id)",
                    documentID: chartResponse.documentId,
                    nameEn: chartResponse.nameEn,
                    nameCn: chartResponse.nameCn,
                    chartType: chartResponse.chartType,
                    airacVersion: chartResponse.airacVersion,
                    documentType: "chart"
                )
                chart.icao = chartResponse.icao
                chart.parentID = chartResponse.parentId
                chart.pdfPath = chartResponse.pdfPath
                chart.htmlPath = chartResponse.htmlPath
                chart.htmlEnPath = chartResponse.htmlEnPath
                chart.isModified = chartResponse.isModified
                chart.isOpened = chartResponse.isOpened ?? false
                
                modelContext.insert(chart)
            }
        }
        
        try? modelContext.save()
    }
}

// MARK: - 机场信息卡片
struct AirportInfoCard: View {
    let airport: AirportResponse
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // Text(airport.icao)
                        //     .font(.largeTitle)
                        //     .fontWeight(.bold)

                        Text(airport.nameCn)
                        .font(.headline)
                        .foregroundColor(.primary)
                        
                        // 更新提示 - 橙色小圆点
                        if airport.isModified == true {
                            Circle()
                                .fill(.orange)
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Text(airport.nameEn)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    // TODO: 添加 METAR 天气信息
                    Button("天气") {
                        // 获取 METAR 信息
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}


// MARK: - 航图行视图
struct ChartRowView: View {
    let chart: ChartResponse
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @Query private var pinnedCharts: [PinnedChart]
    
    private var isPinned: Bool {
        pinnedCharts.contains { $0.chartID == "chart_\(chart.id)" }
    }
    
    private var chartTypeColor: Color {
        ChartType(rawValue: chart.chartType)?.color ?? .gray
    }
    
    var body: some View {
        Group {
            if let binding = selectedChartBinding {
                // iPad 侧边栏模式：点击设置环境中的 selectedChart
                Button {
                    print("🔵 ChartRowView - 点击航图: ID=\(chart.id), Type=\(chart.chartType), Name=\(chart.nameCn)")
                    binding.wrappedValue = chart
                } label: {
                    chartRowContent
                }
                .buttonStyle(.plain)
            } else {
                // iPhone 模式：使用 NavigationLink
                NavigationLink {
                    PDFReaderView(
                        chartID: "chart_\(chart.id)",
                        displayName: chart.nameCn,
                        documentType: .chart
                    )
                } label: {
                    chartRowContent
                }
            }
        }
    }
    
    @ViewBuilder
    private var chartRowContent: some View {
            HStack(spacing: 0) {
                // 左侧颜色边框
                Rectangle()
                    .fill(chartTypeColor)
                    .frame(width: 4)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(chart.nameCn)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(2)
                            
                            // 更新提示 - 橙色小圆点
                            if chart.isModified {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        
                        Text(chart.nameEn)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        HStack {
                            Text(chart.chartType)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(chartTypeColor.opacity(0.2), in: Capsule())
                                .foregroundColor(chartTypeColor)
                            
                            Text("AIRAC \(chart.airacVersion)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                    .padding(.leading, 12)
                    
                    Spacer()
                    
                    Button {
                        togglePin()
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .foregroundColor(isPinned ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
    }
    
    private func togglePin() {
        if isPinned {
            // 移除收藏
            if let pinToRemove = pinnedCharts.first(where: { $0.chartID == "chart_\(chart.id)" }) {
                modelContext.delete(pinToRemove)
            }
        } else {
            // 添加收藏
            let newPin = PinnedChart(
                chartID: "chart_\(chart.id)",
                displayName: chart.nameCn,
                icao: chart.icao ?? "",
                type: chart.chartType,
                documentType: "chart",
                airacVersion: chart.airacVersion
            )
            modelContext.insert(newPin)
        }
        
        try? modelContext.save()
    }
}

// MARK: - 航图类型枚举
enum ChartType: String, CaseIterable {
    case all = "ALL"
    case sid = "SID"
    case star = "STAR"
    case app = "APP"
    case apt = "APT"
    case others = "OTHERS"
    
    var displayName: String {
        switch self {
        case .all: return "全部"
        case .sid: return "SID"
        case .star: return "STAR"
        case .app: return "APP"
        case .apt: return "APT"
        case .others: return "OTHER"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .gray
        case .sid: return .blue
        case .star: return .green
        case .app: return .orange
        case .apt: return .purple
        case .others: return .brown
        }
    }
    
    var lightColor: Color {
        return color.opacity(0.2)
    }
}

#Preview {
    NavigationStack {
        AirportDetailView(airport: AirportResponse(
            icao: "ZBAA",
            nameEn: "Beijing Capital International Airport",
            nameCn: "北京首都国际机场",
            hasTerminalCharts: true,
            createdAt: "2024-01-01T00:00:00Z",
            isModified: false
        ))
    }
    .modelContainer(for: PinnedChart.self, inMemory: true)
}
