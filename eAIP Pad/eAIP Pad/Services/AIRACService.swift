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
        LoggerService.shared.log(type: .info, module: "AIRACService", message: "checkAndUpdateAIRAC started")
        isUpdating = true
        updateProgress = 0.0
        updateMessage = "检查AIRAC版本..."
        errorMessage = nil
        
        do {
            // 获取当前AIRAC版本
            let airacResponse = try await NetworkService.shared.getCurrentAIRAC()
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "successfully got airac response: \(airacResponse)")
            updateProgress = 0.2
            updateMessage = "获取版本信息..."
            
            // 检查本地是否已有该版本
            let descriptor = FetchDescriptor<AIRACVersion>(
                predicate: #Predicate<AIRACVersion> { version in
                    version.version == airacResponse.version
                }
            )
            let existingVersions = try modelContext.fetch(descriptor)
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "existingVersions: \(existingVersions)")
            if existingVersions.isEmpty {
                // 创建新版本记录
                let newVersion = AIRACVersion(
                    version: airacResponse.version,
                    effectiveDate: ISO8601DateFormatter().date(from: airacResponse.effectiveDate) ?? Date(),
                    isCurrent: airacResponse.isCurrent
                )
                modelContext.insert(newVersion)
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "newVersion: \(newVersion)")
                // 将其他版本标记为非当前版本
                let allVersionsDescriptor = FetchDescriptor<AIRACVersion>()
                let allVersions = try modelContext.fetch(allVersionsDescriptor)
                for version in allVersions {
                    if version.version != airacResponse.version {
                        version.isCurrent = false
                    }
                }
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "allVersions: \(allVersions)")
                updateProgress = 0.4
                updateMessage = "下载航图数据..."
                
                // 下载新版本的航图数据
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "start to download charts for version: \(airacResponse.version)")
                await downloadChartsForVersion(airacResponse.version, modelContext: modelContext)
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "charts downloaded successfully")
                try modelContext.save()
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "saved successfully")
                updateProgress = 1.0
                updateMessage = "更新完成"
                
                // 清理旧版本数据和缓存
                await cleanupOldVersions(modelContext: modelContext)
                PDFCacheService.shared.clearOldVersionCaches(modelContext: modelContext)
                PDFCacheService.shared.clearOldVersionDataCaches(modelContext: modelContext)
            } else {
                updateProgress = 1.0
                updateMessage = "已是最新版本"
            }
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "checkAndUpdateAIRAC completed")
        } catch {
            errorMessage = "更新失败: \(error.localizedDescription)"
            LoggerService.shared.log(type: .error, module: "AIRACService", message: "update failed: \(error.localizedDescription)")
        }
        
        // 延迟一秒后重置状态
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isUpdating = false
        LoggerService.shared.log(type: .info, module: "AIRACService", message: "isUpdating set to false")
    }
    
    // MARK: - 下载指定版本的航图数据
    private func downloadChartsForVersion(_ version: String, modelContext: ModelContext) async {
        do {
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "downloadChartsForVersion started: \(version)")
            updateMessage = "下载机场数据..."
            updateProgress = 0.5
            
            // 下载机场列表
            let airports = try await NetworkService.shared.getAirports()
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "airports: \(airports)")
            var totalCharts = 0
            var downloadedCharts = 0
            
            // 统计总航图数量
            for airport in airports {
                let charts = try await NetworkService.shared.getAirportCharts(icao: airport.icao)
                totalCharts += charts.count
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "charts: \(charts)")
            }
            
            updateMessage = "下载航图数据..."
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "start to download charts for airports")
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
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "charts: \(charts)")
                for chart in charts {
                    // 保存航图信息
                    let chartDescriptor = FetchDescriptor<LocalChart>(
                        predicate: #Predicate<LocalChart> { chartModel in
                            chartModel.documentID == chart.documentId
                        }
                    )
                    let existingCharts = try? modelContext.fetch(chartDescriptor)
                    LoggerService.shared.log(type: .info, module: "AIRACService", message: "existingCharts: \(String(describing: existingCharts))")
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
                        chartModel.isOpened = chart.isOpened ?? false
                        
                        modelContext.insert(chartModel)
                    }
                    
                    downloadedCharts += 1
                    
                    // 更新进度
                    updateProgress = 0.5 + (Double(downloadedCharts) / Double(totalCharts)) * 0.4
                    updateMessage = "下载航图数据... (\(downloadedCharts)/\(totalCharts))"
                    LoggerService.shared.log(type: .info, module: "AIRACService", message: "updateProgress: \(updateProgress)")
                    LoggerService.shared.log(type: .info, module: "AIRACService", message: "updateMessage: \(updateMessage)")
                }
                
                // 每处理完一个机场就保存一次，避免内存占用过大
                if airportIndex % 10 == 0 {
                    try? modelContext.save()
                    LoggerService.shared.log(type: .info, module: "AIRACService", message: "saved successfully")
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
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "saved successfully")
        } catch {
            errorMessage = "下载航图数据失败: \(error.localizedDescription)"
            LoggerService.shared.log(type: .error, module: "AIRACService", message: "downloadChartsForVersion failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 清理旧版本数据
    @MainActor
    func cleanupOldVersions(modelContext: ModelContext) async {
        do {
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "cleanupOldVersions started")
            updateMessage = "清理旧版本数据..."
            
            // 获取所有版本，保留最新的3个版本
            let allVersionsDescriptor = FetchDescriptor<AIRACVersion>(
                sortBy: [SortDescriptor(\.effectiveDate, order: .reverse)]
            )
            let allVersions = try modelContext.fetch(allVersionsDescriptor)
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "allVersions: \(allVersions)")
            if allVersions.count > 3 {
                let versionsToDelete = Array(allVersions.dropFirst(3))
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "versionsToDelete: \(versionsToDelete)")
                for version in versionsToDelete {
                    // 删除相关的航图数据
                    let versionString = version.version
                    let chartsDescriptor = FetchDescriptor<LocalChart>(
                        predicate: #Predicate<LocalChart> { chart in
                            chart.airacVersion == versionString
                        }
                    )
                    let chartsToDelete = try modelContext.fetch(chartsDescriptor)
                    LoggerService.shared.log(type: .info, module: "AIRACService", message: "chartsToDelete: \(chartsToDelete)")
                    for chart in chartsToDelete {
                        modelContext.delete(chart)
                    }
                    LoggerService.shared.log(type: .info, module: "AIRACService", message: "version deleted: \(version)")
                    // 删除版本记录
                    modelContext.delete(version)
                }
                LoggerService.shared.log(type: .info, module: "AIRACService", message: "saved successfully")
                try modelContext.save()
            }
            
            // 清理文件缓存
            await cleanupFileCache()

        } catch {
            LoggerService.shared.error(module: "AIRACService", message: "清理旧版本数据失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 清理文件缓存
    private func cleanupFileCache() async {
        LoggerService.shared.log(type: .info, module: "AIRACService", message: "cleanupFileCache started")
        let fileManager = FileManager.default
        LoggerService.shared.log(type: .info, module: "AIRACService", message: "fileManager: \(fileManager)")
        do {
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let cachePath = documentsPath.appendingPathComponent("PDFCache")
            LoggerService.shared.log(type: .info, module: "AIRACService", message: "cachePath: \(cachePath)")
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
            LoggerService.shared.info(module: "AIRACService", message: "文件缓存清理完成")
        } catch {
            LoggerService.shared.error(module: "AIRACService", message: "清理文件缓存失败: \(error.localizedDescription)")
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
            LoggerService.shared.error(module: "AIRACService", message: "获取缓存大小失败: \(error.localizedDescription)")
        }
        
        return "0 B"
    }
    
    // MARK: - 强制清理所有缓存
    @MainActor
    func clearAllCache(modelContext: ModelContext) async {
        LoggerService.shared.info(module: "AIRACService", message: "开始清理所有缓存")
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
            
            // 清理文件缓存、PDF 缓存和数据缓存
            await clearFileCache()
            PDFCacheService.shared.clearAllCache()
            PDFCacheService.shared.clearDataCache()
            
            updateMessage = "缓存清理完成"
            LoggerService.shared.info(module: "AIRACService", message: "所有缓存清理完成")
            
        } catch {
            errorMessage = "清理缓存失败: \(error.localizedDescription)"
            LoggerService.shared.error(module: "AIRACService", message: "清理缓存失败: \(error.localizedDescription)")
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isUpdating = false
    }
    
    // MARK: - 清理所有文件缓存
    private func clearFileCache() async {
        LoggerService.shared.info(module: "AIRACService", message: "开始清理所有文件缓存")
        let fileManager = FileManager.default
        
        do {
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let cachePath = documentsPath.appendingPathComponent("PDFCache")
            
            if fileManager.fileExists(atPath: cachePath.path) {
                try fileManager.removeItem(at: cachePath)
                LoggerService.shared.info(module: "AIRACService", message: "已删除 PDFCache 目录")
            }
            
            // 重新创建缓存目录
            try fileManager.createDirectory(at: cachePath, withIntermediateDirectories: true)
            LoggerService.shared.info(module: "AIRACService", message: "已重新创建 PDFCache 目录")
            
        } catch {
            LoggerService.shared.error(module: "AIRACService", message: "清理文件缓存失败: \(error.localizedDescription)")
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
