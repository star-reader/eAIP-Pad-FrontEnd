import SwiftUI
import SwiftData

// MARK: - 航路图视图
struct EnrouteView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var enrouteCharts: [ChartResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChartType: EnrouteChartType = .enroute
    
    // 过滤后的航路图列表
    private var filteredCharts: [ChartResponse] {
        switch selectedChartType {
        case .enroute:
            return enrouteCharts.filter { $0.chartType == "ENROUTE" }
        case .area:
            return enrouteCharts.filter { $0.chartType == "AREA" }
        case .others:
            return enrouteCharts.filter { $0.chartType == "OTHERS" }
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
                        // 原生航路图类型选择器
                        Picker("航路图类型", selection: $selectedChartType) {
                            ForEach(EnrouteChartType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        
                        // 航路图列表
                        if filteredCharts.isEmpty {
                            ContentUnavailableView(
                                "暂无\(selectedChartType.displayName)",
                                systemImage: "map",
                                description: Text("该分类暂无航路图数据")
                            )
                        } else {
                            List(filteredCharts, id: \.id) { chart in
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
                            .listStyle(.insetGrouped)
                        }
                    }
                }
            }
            .navigationTitle("航路图")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PinboardToolbarButton()
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
            // 加载所有航路图，前端进行过滤
            let response = try await NetworkService.shared.getEnrouteCharts(type: nil)
            await MainActor.run {
                self.enrouteCharts = response
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载航路图数据失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
}

// MARK: - 航路图行视图
struct EnrouteChartRowView: View {
    let chart: ChartResponse
    @Environment(\.modelContext) private var modelContext
    @Query private var pinnedCharts: [PinnedChart]
    
    private var chartID: String {
        "enroute_\(chart.id)"
    }
    
    private var isPinned: Bool {
        pinnedCharts.contains { $0.chartID == chartID }
    }
    
    var body: some View {
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
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundColor(.orange)
                    
                    Text("AIRAC \(chart.airacVersion)")
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
                displayName: chart.nameCn,
                icao: "",
                type: chart.chartType,
                documentType: "enroute",
                airacVersion: chart.airacVersion
            )
            modelContext.insert(newPin)
        }
        
        try? modelContext.save()
    }
}

// MARK: - 航路图类型枚举
enum EnrouteChartType: String, CaseIterable {
    case enroute = "ENROUTE"
    case area = "AREA"
    case others = "OTHERS"
    
    var displayName: String {
        switch self {
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
