import SwiftUI
import SwiftData

// MARK: - 航路图视图
struct EnrouteView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var localCharts: [LocalChart]
    @State private var enrouteCharts: [ChartResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChartType: EnrouteChartType = .all
    
    // 过滤本地航路图
    private var localEnrouteCharts: [LocalChart] {
        localCharts.filter { $0.documentType == "enroute" }
    }
    
    // 过滤后的航路图列表
    private var filteredCharts: [ChartResponse] {
        if selectedChartType == .all {
            return enrouteCharts
        } else {
            return enrouteCharts.filter { $0.chartType == selectedChartType.rawValue }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("加载航路图数据...")
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
                                await loadEnrouteCharts()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // 航路图类型选择器
                        EnrouteChartTypeSelector(selectedType: $selectedChartType)
                            .padding(.horizontal)
                        
                        // 航路图列表
                        List {
                            if !localEnrouteCharts.isEmpty {
                                Section("本地缓存") {
                                    ForEach(localEnrouteCharts, id: \.chartID) { chart in
                                        NavigationLink {
                                            PDFReaderView(
                                                chartID: chart.chartID,
                                                displayName: chart.nameCn,
                                                documentType: .enroute
                                            )
                                        } label: {
                                            EnrouteChartRowView(localChart: chart)
                                        }
                                    }
                                }
                            }
                            
                            if !filteredCharts.isEmpty {
                                Section("在线航路图") {
                                    ForEach(filteredCharts, id: \.id) { chart in
                                        NavigationLink {
                                            PDFReaderView(
                                                chartID: "enroute_\(chart.id)",
                                                displayName: chart.nameCn,
                                                documentType: .enroute
                                            )
                                        } label: {
                                            EnrouteChartRowView(chart: chart)
                                        }
                                    }
                                }
                            }
                            
                            if localEnrouteCharts.isEmpty && filteredCharts.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "map")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text("暂无航路图数据")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("航路图")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        PinboardToolbarButton()
                        
                        Menu {
                            ForEach(EnrouteChartType.allCases, id: \.self) { type in
                                Button {
                                    selectedChartType = type
                                } label: {
                                    HStack {
                                        Text(type.displayName)
                                        if selectedChartType == type {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .task {
            await loadEnrouteCharts()
        }
    }
    
    private func loadEnrouteCharts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let type = selectedChartType == .all ? nil : selectedChartType.rawValue
            let response = try await NetworkService.shared.getEnrouteCharts(type: type)
            await MainActor.run {
                self.enrouteCharts = response
                
                // 同步到本地 SwiftData
                syncEnrouteChartsToLocal(response)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载航路图数据失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    private func syncEnrouteChartsToLocal(_ charts: [ChartResponse]) {
        for chartResponse in charts {
            // 检查是否已存在
            let existingCharts = try? modelContext.fetch(
                FetchDescriptor<LocalChart>(
                    predicate: #Predicate { $0.documentID == chartResponse.documentId }
                )
            )
            
            if existingCharts?.isEmpty ?? true {
                let chart = LocalChart(
                    chartID: "enroute_\(chartResponse.id)",
                    documentID: chartResponse.documentId,
                    nameEn: chartResponse.nameEn,
                    nameCn: chartResponse.nameCn,
                    chartType: chartResponse.chartType,
                    airacVersion: chartResponse.airacVersion,
                    documentType: "enroute"
                )
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

// MARK: - 航路图类型选择器
struct EnrouteChartTypeSelector: View {
    @Binding var selectedType: EnrouteChartType
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(EnrouteChartType.allCases, id: \.self) { type in
                    Button {
                        selectedType = type
                    } label: {
                        Text(type.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedType == type ? .orange : .clear,
                                in: Capsule()
                            )
                            .foregroundColor(selectedType == type ? .white : .primary)
                            .overlay(
                                Capsule()
                                    .stroke(.orange, lineWidth: selectedType == type ? 0 : 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - 航路图行视图
struct EnrouteChartRowView: View {
    let chart: ChartResponse?
    let localChart: LocalChart?
    @Environment(\.modelContext) private var modelContext
    @Query private var pinnedCharts: [PinnedChart]
    
    init(chart: ChartResponse) {
        self.chart = chart
        self.localChart = nil
    }
    
    init(localChart: LocalChart) {
        self.chart = nil
        self.localChart = localChart
    }
    
    private var chartID: String {
        if let chart = chart {
            return "enroute_\(chart.id)"
        } else if let localChart = localChart {
            return localChart.chartID
        }
        return ""
    }
    
    private var displayName: String {
        chart?.nameCn ?? localChart?.nameCn ?? ""
    }
    
    private var englishName: String {
        chart?.nameEn ?? localChart?.nameEn ?? ""
    }
    
    private var chartType: String {
        chart?.chartType ?? localChart?.chartType ?? ""
    }
    
    private var airacVersion: String {
        chart?.airacVersion ?? localChart?.airacVersion ?? ""
    }
    
    private var isModified: Bool {
        chart?.isModified ?? localChart?.isModified ?? false
    }
    
    private var isPinned: Bool {
        pinnedCharts.contains { $0.chartID == chartID }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    
                    if isModified {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                    
                    if localChart != nil {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                Text(englishName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    Text(chartType)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                    
                    Text("AIRAC \(airacVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
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
    
    private func togglePin() {
        if isPinned {
            // 移除收藏
            if let pinToRemove = pinnedCharts.first(where: { $0.chartID == chartID }) {
                modelContext.delete(pinToRemove)
            }
        } else {
            // 添加收藏
            let newPin = PinnedChart(
                chartID: chartID,
                displayName: displayName,
                icao: "",
                type: chartType,
                documentType: "enroute",
                airacVersion: airacVersion
            )
            modelContext.insert(newPin)
        }
        
        try? modelContext.save()
    }
}

// MARK: - 航路图类型枚举
enum EnrouteChartType: String, CaseIterable {
    case all = "ALL"
    case enroute = "ENROUTE"
    case area = "AREA"
    case others = "OTHERS"
    
    var displayName: String {
        switch self {
        case .all: return "全部"
        case .enroute: return "航路图"
        case .area: return "区域图"
        case .others: return "其他"
        }
    }
}

#Preview {
    NavigationStack {
        EnrouteView()
    }
    .modelContainer(for: LocalChart.self, inMemory: true)
}
