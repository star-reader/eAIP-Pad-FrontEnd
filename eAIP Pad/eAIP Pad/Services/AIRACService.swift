import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - AIRAC 版本管理服务
class AIRACService: ObservableObject {
    static let shared = AIRACService()
    
    @Published var isUpdating = false
    @Published var updateProgress: Double = 0.0
    @Published var updateMessage = ""
    var errorMessage: String?
    
    private init() {}
    
    // MARK: - 检查并更新AIRAC版本
    @MainActor
    func checkAndUpdateAIRAC(modelContext: ModelContext) async {
        isUpdating = true
        updateProgress = 0.0
        updateMessage = "检查AIRAC版本..."
        errorMessage = nil
        
        do {
            // 获取当前AIRAC版本
            let airacResponse = try await NetworkService.shared.getCurrentAIRAC()
            updateProgress = 0.2
            updateMessage = "获取版本信息..."
            
            // 检查本地是否已有该版本
            let descriptor = FetchDescriptor<AIRACVersion>(
                predicate: #Predicate<AIRACVersion> { version in
                    version.version == airacResponse.version
                }
            )
            let existingVersions = try modelContext.fetch(descriptor)
            
            if existingVersions.isEmpty {
                // 创建新版本记录
                let newVersion = AIRACVersion(
                    version: airacResponse.version,
                    effectiveDate: ISO8601DateFormatter().date(from: airacResponse.effectiveDate) ?? Date(),
                    isCurrent: airacResponse.isCurrent
                )
                modelContext.insert(newVersion)
                
                // 将其他版本标记为非当前版本
                let allVersionsDescriptor = FetchDescriptor<AIRACVersion>()
                let allVersions = try modelContext.fetch(allVersionsDescriptor)
                for version in allVersions {
                    if version.version != airacResponse.version {
                        version.isCurrent = false
                    }
                }
                
                updateProgress = 0.4
                updateMessage = "下载航图数据..."
                
                // 下载新版本的航图数据
                await downloadChartsForVersion(airacResponse.version, modelContext: modelContext)
                
                try modelContext.save()
                
                updateProgress = 1.0
                updateMessage = "更新完成"
                
                // 清理旧版本数据
                await cleanupOldVersions(modelContext: modelContext)
            } else {
                updateProgress = 1.0
                updateMessage = "已是最新版本"
            }
            
        } catch {
            errorMessage = "更新失败: \(error.localizedDescription)"
        }
        
        // 延迟一秒后重置状态
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isUpdating = false
    }
    
    // MARK: - 下载指定版本的航图数据
    private func downloadChartsForVersion(_ version: String, modelContext: ModelContext) async {
        do {
            updateMessage = "下载机场数据..."
            updateProgress = 0.5
            
            // 下载机场列表
            let airports = try await NetworkService.shared.getAirports()
            
            var totalCharts = 0
            var downloadedCharts = 0
            
            // 统计总航图数量
            for airport in airports {
                let charts = try await NetworkService.shared.getAirportCharts(icao: airport.icao)
                totalCharts += charts.count
            }
            
            updateMessage = "下载航图数据..."
            
            // 下载并保存航图数据
            for (airportIndex, airport) in airports.enumerated() {
                // 保存机场信息
                let airportDescriptor = FetchDescriptor<Airport>(
                    predicate: #Predicate<Airport> { airportModel in
                        airportModel.icao == airport.icao
                    }
                )
                let existingAirports = try? modelContext.fetch(airportDescriptor)
                
                if existingAirports?.isEmpty ?? true {
                    let airportModel = Airport(
                        icao: airport.icao,
                        nameEn: airport.nameEn,
                        nameCn: airport.nameCn,
                        hasTerminalCharts: airport.hasTerminalCharts
                    )
                    modelContext.insert(airportModel)
                }
                
                // 下载航图数据
                let charts = try await NetworkService.shared.getAirportCharts(icao: airport.icao)
                
                for chart in charts {
                    // 保存航图信息
                    let chartDescriptor = FetchDescriptor<LocalChart>(
                        predicate: #Predicate<LocalChart> { chartModel in
                            chartModel.documentID == chart.documentId
                        }
                    )
                    let existingCharts = try? modelContext.fetch(chartDescriptor)
                    
                    if existingCharts?.isEmpty ?? true {
                        let chartModel = LocalChart(
                            chartID: "chart_\(chart.id)",
                            documentID: chart.documentId,
                            nameEn: chart.nameEn,
                            nameCn: chart.nameCn,
                            chartType: chart.chartType,
                            airacVersion: chart.airacVersion,
                            documentType: "chart"
                        )
                        chartModel.icao = chart.icao
                        chartModel.parentID = chart.parentId
                        chartModel.pdfPath = chart.pdfPath
                        chartModel.htmlPath = chart.htmlPath
                        chartModel.htmlEnPath = chart.htmlEnPath
                        chartModel.isModified = chart.isModified
                        chartModel.isOpened = chart.isOpened
                        
                        modelContext.insert(chartModel)
                    }
                    
                    downloadedCharts += 1
                    
                    // 更新进度
                    updateProgress = 0.5 + (Double(downloadedCharts) / Double(totalCharts)) * 0.4
                    updateMessage = "下载航图数据... (\(downloadedCharts)/\(totalCharts))"
                }
                
                // 每处理完一个机场就保存一次，避免内存占用过大
                if airportIndex % 10 == 0 {
                    try? modelContext.save()
                }
            }
            
            // 更新版本统计信息
            let versionDescriptor = FetchDescriptor<AIRACVersion>(
                predicate: #Predicate<AIRACVersion> { versionModel in
                    versionModel.version == version
                }
            )
            if let currentVersion = try? modelContext.fetch(versionDescriptor).first {
                currentVersion.totalCharts = totalCharts
                currentVersion.downloadedCharts = downloadedCharts
            }
            
            updateProgress = 0.9
            updateMessage = "保存数据..."
            
            try modelContext.save()
            
        } catch {
            errorMessage = "下载航图数据失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 清理旧版本数据
    @MainActor
    func cleanupOldVersions(modelContext: ModelContext) async {
        do {
            updateMessage = "清理旧版本数据..."
            
            // 获取所有版本，保留最新的3个版本
            let allVersionsDescriptor = FetchDescriptor<AIRACVersion>(
                sortBy: [SortDescriptor(\.effectiveDate, order: .reverse)]
            )
            let allVersions = try modelContext.fetch(allVersionsDescriptor)
            
            if allVersions.count > 3 {
                let versionsToDelete = Array(allVersions.dropFirst(3))
                
                for version in versionsToDelete {
                    // 删除相关的航图数据
                    let versionString = version.version
                    let chartsDescriptor = FetchDescriptor<LocalChart>(
                        predicate: #Predicate<LocalChart> { chart in
                            chart.airacVersion == versionString
                        }
                    )
                    let chartsToDelete = try modelContext.fetch(chartsDescriptor)
                    
                    for chart in chartsToDelete {
                        modelContext.delete(chart)
                    }
                    
                    // 删除版本记录
                    modelContext.delete(version)
                }
                
                try modelContext.save()
            }
            
            // 清理文件缓存
            await cleanupFileCache()
            
        } catch {
            print("清理旧版本数据失败: \(error)")
        }
    }
    
    // MARK: - 清理文件缓存
    private func cleanupFileCache() async {

        let fileManager = FileManager.default
        
        do {
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let cachePath = documentsPath.appendingPathComponent("PDFCache")
            
            if fileManager.fileExists(atPath: cachePath.path) {
                let cacheContents = try fileManager.contentsOfDirectory(at: cachePath, includingPropertiesForKeys: [.creationDateKey])
                
                // 删除超过30天的缓存文件
                let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
                
                for fileURL in cacheContents {
                    if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < thirtyDaysAgo {
                        try fileManager.removeItem(at: fileURL)
                    }
                }
            }
        } catch {
            print("清理文件缓存失败: \(error)")
        }
    }
    
    // MARK: - 获取缓存大小
    func getCacheSize() -> String {
        let fileManager = FileManager.default
        
        do {
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let cachePath = documentsPath.appendingPathComponent("PDFCache")
            
            if fileManager.fileExists(atPath: cachePath.path) {
                let cacheContents = try fileManager.contentsOfDirectory(at: cachePath, includingPropertiesForKeys: [.fileSizeKey])
                
                let totalSize = cacheContents.reduce(0) { total, fileURL in
                    let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return total + fileSize
                }
                
                return ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
            }
        } catch {
            print("获取缓存大小失败: \(error)")
        }
        
        return "0 B"
    }
    
    // MARK: - 强制清理所有缓存
    @MainActor
    func clearAllCache(modelContext: ModelContext) async {
        isUpdating = true
        updateMessage = "清理缓存..."
        
        do {
            // 删除所有非当前版本的数据
            let allVersionsDescriptor = FetchDescriptor<AIRACVersion>()
            let allVersions = try modelContext.fetch(allVersionsDescriptor)
            let nonCurrentVersions = allVersions.filter { !$0.isCurrent }
            
            for version in nonCurrentVersions {
                // 删除相关航图数据
                let versionString = version.version
                let chartsDescriptor = FetchDescriptor<LocalChart>(
                    predicate: #Predicate<LocalChart> { chart in
                        chart.airacVersion == versionString
                    }
                )
                let chartsToDelete = try modelContext.fetch(chartsDescriptor)
                
                for chart in chartsToDelete {
                    modelContext.delete(chart)
                }
                
                modelContext.delete(version)
            }
            
            try modelContext.save()
            
            // 清理文件缓存
            await clearFileCache()
            
            updateMessage = "缓存清理完成"
            
        } catch {
            errorMessage = "清理缓存失败: \(error.localizedDescription)"
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isUpdating = false
    }
    
    // MARK: - 清理所有文件缓存
    private func clearFileCache() async {
        let fileManager = FileManager.default
        
        do {
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let cachePath = documentsPath.appendingPathComponent("PDFCache")
            
            if fileManager.fileExists(atPath: cachePath.path) {
                try fileManager.removeItem(at: cachePath)
            }
            
            // 重新创建缓存目录
            try fileManager.createDirectory(at: cachePath, withIntermediateDirectories: true)
            
        } catch {
            print("清理文件缓存失败: \(error)")
        }
    }
}

// MARK: - AIRAC 更新视图
struct AIRACUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var airacService = AIRACService.shared
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 更新图标
                Image(systemName: airacService.isUpdating ? "arrow.clockwise" : "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(airacService.isUpdating ? .orange : .green)
                    .rotationEffect(.degrees(airacService.isUpdating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: airacService.isUpdating)
                
                VStack(spacing: 8) {
                    Text(airacService.isUpdating ? "正在更新..." : "更新完成")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(airacService.updateMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // 进度条
                if airacService.isUpdating {
                    VStack(spacing: 8) {
                        ProgressView(value: airacService.updateProgress)
                            .progressViewStyle(.linear)
                        
                        Text("\(Int(airacService.updateProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 错误信息
                if let errorMessage = airacService.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                
                Spacer()
                
                // 操作按钮
                if !airacService.isUpdating {
                    VStack(spacing: 12) {
                        if airacService.errorMessage != nil {
                            Button("重试") {
                                Task {
                                    await airacService.checkAndUpdateAIRAC(modelContext: modelContext)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        Button("完成") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .navigationTitle("AIRAC 更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !airacService.isUpdating {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("关闭") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(airacService.isUpdating)
        .task {
            await airacService.checkAndUpdateAIRAC(modelContext: modelContext)
        }
    }
}

#Preview {
    AIRACUpdateView()
        .modelContainer(for: AIRACVersion.self, inMemory: true)
}
