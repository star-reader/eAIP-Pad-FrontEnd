import SwiftUI
import SwiftData

// MARK: - 细则导航项
struct RegulationNavigation: Identifiable, Hashable {
    let id = UUID()
    let chartID: String
    let displayName: String
}

// MARK: - 细则视图（AD细则）
struct RegulationsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var airports: [AirportResponse] = []
    @State private var errorMessage: String?
    @State private var selectedRegulation: RegulationNavigation?
    @State private var isLoadingRegulation = false
    
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
            VStack(spacing: 0) {
                // 搜索栏
                SearchBar(text: $searchText, placeholder: "搜索机场...")
                    .padding()
                
                // 机场列表
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
                } else if filteredAirports.isEmpty {
                    ContentUnavailableView(
                        "暂无机场数据",
                        systemImage: "airplane.circle",
                        description: Text("没有找到相关机场")
                    )
                    .foregroundColor(.primaryBlue)
                } else {
                    List(filteredAirports, id: \.icao) { airport in
                        Button {
                            Task {
                                await openFirstRegulation(for: airport)
                            }
                        } label: {
                            AirportRegulationRowView(airport: airport)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .overlay {
                if isLoadingRegulation {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("加载细则...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .navigationTitle("机场细则")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PinboardToolbarButton()
                }
            }
            .navigationDestination(item: $selectedRegulation) { regulation in
                PDFReaderView(
                    chartID: regulation.chartID,
                    displayName: regulation.displayName,
                    documentType: .ad
                )
            }
        }
        .task {
            await loadAirports()
        }
    }
    
    // MARK: - 加载机场数据
    private func loadAirports() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取当前 AIRAC 版本
            guard let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "Regulations", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }
            
            // 1. 先尝试从缓存加载
            if let cachedAirports = PDFCacheService.shared.loadCachedData(
                [AirportResponse].self,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.airports
            ) {
                await MainActor.run {
                    self.airports = cachedAirports
                }
                isLoading = false
                return
            }
            
            // 2. 缓存未命中，从网络获取
            let response = try await NetworkService.shared.getAirports()
            
            // 3. 保存到缓存
            try? PDFCacheService.shared.cacheData(
                response,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.airports
            )
            
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
    
    // MARK: - 打开第一个细则
    private func openFirstRegulation(for airport: AirportResponse) async {
        isLoadingRegulation = true
        
        do {
            let regulations = try await NetworkService.shared.getAIPDocumentsByICAO(icao: airport.icao)
            
            await MainActor.run {
                if let firstRegulation = regulations.first {
                    // 打开第一个细则
                    selectedRegulation = RegulationNavigation(
                        chartID: "ad_\(firstRegulation.id)",
                        displayName: "\(airport.icao) - \(firstRegulation.nameCn)"
                    )
                } else {
                    // 没有细则，显示错误
                    errorMessage = "\(airport.icao) 暂无AD细则"
                }
                isLoadingRegulation = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "加载AD细则失败: \(error.localizedDescription)"
                isLoadingRegulation = false
            }
        }
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
                    .fill(.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(airport.icao)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("AD细则")
                        .font(.caption2)
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
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 机场细则详情视图
struct AirportRegulationsView: View {
    @Environment(\.modelContext) private var modelContext
    let airport: AirportResponse
    @State private var regulations: [AIPDocumentResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("加载AD细则...")
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
                            await loadRegulations()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if regulations.isEmpty {
                ContentUnavailableView(
                    "暂无AD细则",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("该机场暂无AD细则文档")
                )
                .foregroundColor(.primaryBlue)
            } else {
                List(regulations, id: \.id) { regulation in
                    NavigationLink {
                        PDFReaderView(
                            chartID: "ad_\(regulation.id)",
                            displayName: regulation.nameCn,
                            documentType: .ad
                        )
                    } label: {
                        RegulationDocumentRowView(regulation: regulation)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("\(airport.icao) AD细则")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadRegulations()
        }
    }
    
    private func loadRegulations() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取当前 AIRAC 版本
            guard let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "Regulations", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }
            
            // 使用机场 ICAO 作为缓存键
            let cacheKey = "ad_\(airport.icao)"
            
            // 1. 先尝试从缓存加载
            if let cachedRegulations = PDFCacheService.shared.loadCachedData(
                [AIPDocumentResponse].self,
                airacVersion: currentAIRAC,
                dataType: cacheKey
            ) {
                await MainActor.run {
                    self.regulations = cachedRegulations
                }
                isLoading = false
                return
            }
            // 2. 缓存未命中，从网络获取
            let response = try await NetworkService.shared.getAIPDocumentsByICAO(icao: airport.icao)
            
            // 3. 保存到缓存
            try? PDFCacheService.shared.cacheData(
                response,
                airacVersion: currentAIRAC,
                dataType: cacheKey
            )
            
            await MainActor.run {
                self.regulations = response
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载AD细则失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
}

// MARK: - 细则文档行视图
struct RegulationDocumentRowView: View {
    let regulation: AIPDocumentResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(regulation.nameCn)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            
            Text(regulation.name)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack {
                Text(regulation.category)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2), in: Capsule())
                    .foregroundColor(.blue)
                
                Text("AIRAC \(regulation.airacVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if (regulation.isModified ?? false) || (regulation.hasUpdate ?? false) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 搜索栏
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    RegulationsView()
}