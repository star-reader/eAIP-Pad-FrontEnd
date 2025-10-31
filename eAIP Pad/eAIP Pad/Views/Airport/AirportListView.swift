import SwiftUI
import SwiftData
import Foundation

// MARK: - 机场列表视图
struct AirportListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectedAirportBinding) private var selectedAirportBinding
    @Query private var localAirports: [Airport]
    @State private var searchText = ""
    @State private var airports: [AirportResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
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
                    ProgressView("加载机场数据...")
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
                        if let binding = selectedAirportBinding {
                            // iPad 模式：点击设置选中的机场
                            Button {
                                binding.wrappedValue = airport
                            } label: {
                                AirportRowView(airport: airport)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())  // 扩展点击区域到整行
                        } else {
                            // iPhone 模式：使用 NavigationLink
                            NavigationLink {
                                AirportDetailView(airport: airport)
                            } label: {
                                AirportRowView(airport: airport)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "搜索机场 ICAO 或名称")
                }
            }
            .navigationTitle("机场")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        PinboardToolbarButton()
                        
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
        }
        .task {
            await loadAirports()
        }
    }
    
    private func loadAirports() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取当前 AIRAC 版本
            guard let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "AirportList", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }
            
            // 1. 先尝试从缓存加载
            if let cachedAirports = PDFCacheService.shared.loadCachedData(
                [AirportResponse].self,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.airports
            ) {
                await MainActor.run {
                    self.airports = cachedAirports
                    syncAirportsToLocal(cachedAirports)
                }
                isLoading = false
                return
            }
            
            // 2. 缓存未命中，从网络获取
            let response = try await NetworkService.shared.getAirports(search: searchText.isEmpty ? nil : searchText)
            
            // 3. 保存到缓存（只有非搜索状态才缓存完整列表）
            if searchText.isEmpty {
                try? PDFCacheService.shared.cacheData(
                    response,
                    airacVersion: currentAIRAC,
                    dataType: PDFCacheService.DataType.airports
                )
            }
            
            await MainActor.run {
                self.airports = response
                
                // 同步到本地 SwiftData
                syncAirportsToLocal(response)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载机场数据失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    private func syncAirportsToLocal(_ airports: [AirportResponse]) {
        for airportResponse in airports {
            // 检查是否已存在
            let existingAirports = try? modelContext.fetch(
                FetchDescriptor<Airport>(
                    predicate: #Predicate { $0.icao == airportResponse.icao }
                )
            )
            
            if existingAirports?.isEmpty ?? true {
                let airport = Airport(
                    icao: airportResponse.icao,
                    nameEn: airportResponse.nameEn,
                    nameCn: airportResponse.nameCn,
                    hasTerminalCharts: airportResponse.hasTerminalCharts,
                    isModified: airportResponse.isModified ?? false
                )
                modelContext.insert(airport)
            }
        }
        
        try? modelContext.save()
    }
}

// MARK: - 机场行视图
struct AirportRowView: View {
    let airport: AirportResponse
    
    var body: some View {
        HStack {
            // 机场图标
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "airplane")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(airport.icao)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    // 更新提示 - 橙色小圆点
                    if airport.isModified == true {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                    }
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
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AirportListView()
    }
    .modelContainer(for: Airport.self, inMemory: true)
}
