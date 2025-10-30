import SwiftUI
import SwiftData

// MARK: - 细则视图
struct RegulationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var localCharts: [LocalChart]
    @State private var airports: [AirportResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    
    // 过滤后的机场列表
    private var filteredAirports: [AirportResponse] {
        if searchText.isEmpty {
            return airports
        } else {
            return airports.filter { airport in
                airport.icao.localizedCaseInsensitiveContains(searchText) ||
                airport.nameEn.localizedCaseInsensitiveContains(searchText) ||
                airport.nameCn.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("加载机场细则...")
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
                                await loadAirports()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredAirports, id: \.icao) { airport in
                        NavigationLink {
                            AirportRegulationView(airport: airport)
                        } label: {
                            AirportRegulationRowView(airport: airport)
                        }
                    }
                    .searchable(text: $searchText, prompt: "搜索机场细则")
                    .refreshable {
                        await loadAirports()
                    }
                }
            }
            .navigationTitle("机场细则")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await loadAirports()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            await loadAirports()
        }
    }
    
    private func loadAirports() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await NetworkService.shared.getAirports()
            await MainActor.run {
                self.airports = response
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载机场数据失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
}

// MARK: - 机场细则行视图
struct AirportRegulationRowView: View {
    let airport: AirportResponse
    
    var body: some View {
        HStack {
            // 机场图标
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "doc.text")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(airport.icao)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("细则")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                        .foregroundColor(.blue)
                }
                
                Text(airport.nameCn)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text(airport.nameEn)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 机场细则详情视图
struct AirportRegulationView: View {
    let airport: AirportResponse
    @Environment(\.modelContext) private var modelContext
    @Query private var pinnedCharts: [PinnedChart]
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private var regulationChartID: String {
        "regulation_\(airport.icao)"
    }
    
    private var isPinned: Bool {
        pinnedCharts.contains { $0.chartID == regulationChartID }
    }
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("加载细则文档...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        openRegulationPDF()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 机场细则信息卡片
                VStack(spacing: 16) {
                    // 机场信息
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(airport.icao)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                
                                Text(airport.nameCn)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(airport.nameEn)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(spacing: 8) {
                                Button {
                                    togglePin()
                                } label: {
                                    Image(systemName: isPinned ? "pin.fill" : "pin")
                                        .foregroundColor(isPinned ? .orange : .secondary)
                                        .font(.title2)
                                }
                                
                                Text(isPinned ? "已收藏" : "收藏")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                    // 打开PDF按钮
                    Button {
                        openRegulationPDF()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("查看机场细则")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.orange, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                    }
                    
                    // 说明文字
                    VStack(alignment: .leading, spacing: 8) {
                        Text("机场细则包含:")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• 机场运行规则和限制")
                            Text("• 地面服务信息")
                            Text("• 特殊程序和注意事项")
                            Text("• 联系方式和频率")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                    Spacer()
                }
                .padding()
            }
        }
        .navigationTitle("\(airport.icao) 细则")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func openRegulationPDF() {
        // TODO: 实现机场细则PDF打开逻辑
        // 这里应该导航到PDFReaderView
        print("打开 \(airport.icao) 机场细则PDF")
    }
    
    private func togglePin() {
        if isPinned {
            // 移除收藏
            if let pinToRemove = pinnedCharts.first(where: { $0.chartID == regulationChartID }) {
                modelContext.delete(pinToRemove)
            }
        } else {
            // 添加收藏
            let newPin = PinnedChart(
                chartID: regulationChartID,
                displayName: "\(airport.icao) 细则",
                icao: airport.icao,
                type: "REGULATION",
                documentType: "aip",
                airacVersion: "2510" // TODO: 获取实际AIRAC版本
            )
            modelContext.insert(newPin)
        }
        
        try? modelContext.save()
    }
}

#Preview("Regulations List") {
    NavigationStack {
        RegulationsView()
    }
    .modelContainer(for: LocalChart.self, inMemory: true)
}

#Preview("Airport Regulation") {
    NavigationStack {
        AirportRegulationView(airport: AirportResponse(
            icao: "ZBAA",
            nameEn: "Beijing Capital International Airport",
            nameCn: "北京首都国际机场",
            hasTerminalCharts: true,
            createdAt: "2024-01-01T00:00:00Z"
        ))
    }
    .modelContainer(for: PinnedChart.self, inMemory: true)
}
