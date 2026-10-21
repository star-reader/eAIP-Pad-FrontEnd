import SwiftData
import SwiftUI

struct EnrouteView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var airacService = AIRACService.shared
    @Environment(\.isAIRACPageActive) private var isPageActive
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @StateObject private var page = AIRACPageLoader(initialValue: [ChartResponse]())
    private var enrouteCharts: [ChartResponse] { page.value }
    private var isLoading: Bool { page.isLoading }
    private var errorMessage: String? { page.errorMessage }
    @State private var selectedChartType: EnrouteChartType = .enroute

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
        AIRACNavigationContainer {
            LoadingStateView(
                isLoading: isLoading,
                errorMessage: errorMessage,
                loadingMessage: "加载航路图数据...",
                retryAction: { await loadEnrouteCharts() }
            ) {
                VStack(spacing: 0) {
                    Picker("航路图类型", selection: $selectedChartType) {
                        ForEach(EnrouteChartType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if filteredCharts.isEmpty {
                        EmptyStateView(
                            title: "暂无\(selectedChartType.displayName)",
                            systemImage: "map",
                            description: "该分类暂无航路图数据"
                        )
                    } else {
                        List(filteredCharts, id: \.id) { chart in
                            Group {
                                if let binding = selectedChartBinding {
                                    Button {
                                        binding.wrappedValue = chart
                                    } label: {
                                        EnrouteChartRowView(chart: chart)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink {
                                        PDFReaderView(
                                            chartID: "enroute_\(chart.id)",
                                            displayName: chart.nameCn,
                                            documentType: .enroute,
                                            airacVersion: chart.airacVersion
                                        )
                                    } label: {
                                        EnrouteChartRowView(chart: chart)
                                    }
                                }
                            }
                            .compactListRow()
                        }
                        .listStyle(.insetGrouped)
                        .refreshable { await loadEnrouteCharts() }
                    }
                }
            }
            .airacNavigationTitle("航路图")
            .toolbar {
                if isPageActive {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        PinboardToolbarButton()
                    }
                }
            }
        }
        .airacPageTask(key: "\(airacService.dataRevision)") {
            await loadEnrouteCharts(force: false)
        }
    }
    
    private func loadEnrouteCharts(force: Bool = true) async {
        await page.load(key: "\(airacService.dataRevision)", force: force, errorPrefix: "加载航路图数据失败：") { [modelContext] in
            let loaded = try await AIRACPackageStore.loadCharts(modelContext: modelContext, documentType: "enroute")
            return loaded.map { $0.toChartResponse() }
        }
    }
}

// MARK: - 航路图行视图
struct EnrouteChartRowView: View {
    let chart: ChartResponse
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var airacService = AIRACService.shared
    @Query private var pinnedCharts: [PinnedChart]

    private var chartID: String {
        "enroute_\(chart.id)"
    }

    private var isPinned: Bool {
        pinnedCharts.contains { $0.chartID == chartID }
    }

    var body: some View {
        HStack(spacing: 12) {
            AppSymbolView(systemImage: AppSymbols.enroute)

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
                PinSymbolView(isPinned: isPinned)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "取消收藏" : "收藏航图")
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
