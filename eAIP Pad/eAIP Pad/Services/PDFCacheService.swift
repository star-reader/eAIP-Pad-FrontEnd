import Foundation
import SwiftData
import PDFKit

// MARK: - PDF 缓存管理服务
class PDFCacheService {
    static let shared = PDFCacheService()
    
    private let fileManager = FileManager.default
    
    // PDF 缓存目录
    private var cacheDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cachePath = documentsPath.appendingPathComponent("PDFCache")
        
        // 确保缓存目录存在
        if !fileManager.fileExists(atPath: cachePath.path) {
            try? fileManager.createDirectory(at: cachePath, withIntermediateDirectories: true)
        }
        
        return cachePath
    }
    
    // 数据缓存目录（用于缓存机场列表、航路图列表等 JSON 数据）
    private var dataCacheDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cachePath = documentsPath.appendingPathComponent("DataCache")
        
        // 确保缓存目录存在
        if !fileManager.fileExists(atPath: cachePath.path) {
            try? fileManager.createDirectory(at: cachePath, withIntermediateDirectories: true)
        }
        
        return cachePath
    }
    
    private init() {
        LoggerService.shared.info(module: "PDFCacheService", message: "PDF 缓存服务初始化")
    }
    
    // MARK: - 生成缓存文件路径
    /// 生成缓存文件路径，格式：PDFCache/{airacVersion}/{documentType}_{id}.pdf
    private func cacheFilePath(airacVersion: String, documentType: String, id: String) -> URL {
        let versionDirectory = cacheDirectory.appendingPathComponent(airacVersion)
        
        // 确保 AIRAC 版本目录存在
        if !fileManager.fileExists(atPath: versionDirectory.path) {
            try? fileManager.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
        }
        
        let fileName = "\(documentType)_\(id).pdf"
        return versionDirectory.appendingPathComponent(fileName)
    }
    
    // MARK: - 检查缓存是否存在
    /// 检查指定 PDF 是否已缓存
    func isCached(airacVersion: String, documentType: String, id: String) -> Bool {
        let filePath = cacheFilePath(airacVersion: airacVersion, documentType: documentType, id: id)
        return fileManager.fileExists(atPath: filePath.path)
    }
    
    // MARK: - 从缓存加载 PDF
    /// 从缓存加载 PDF 文档
    func loadFromCache(airacVersion: String, documentType: String, id: String) -> PDFDocument? {
        let filePath = cacheFilePath(airacVersion: airacVersion, documentType: documentType, id: id)
        
        guard fileManager.fileExists(atPath: filePath.path) else {
            return nil
        }
        
        return PDFDocument(url: filePath)
    }
    
    // MARK: - 保存 PDF 到缓存
    /// 保存 PDF 数据到缓存
    func saveToCache(pdfData: Data, airacVersion: String, documentType: String, id: String) throws {
        let filePath = cacheFilePath(airacVersion: airacVersion, documentType: documentType, id: id)
        try pdfData.write(to: filePath)
        LoggerService.shared.info(module: "PDFCacheService", message: "保存 PDF 到缓存: \(documentType)_\(id)")
    }
    
    // MARK: - 获取当前 AIRAC 版本
    /// 从数据库获取当前 AIRAC 版本
    func getCurrentAIRACVersion(modelContext: ModelContext) -> String? {
        do {
            let descriptor = FetchDescriptor<AIRACVersion>(
                predicate: #Predicate<AIRACVersion> { $0.isCurrent == true }
            )
            let currentVersion = try modelContext.fetch(descriptor).first
            return currentVersion?.version
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "获取当前 AIRAC 版本失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - 清理旧版本缓存
    /// 清理指定 AIRAC 版本的所有缓存
    func clearCacheForVersion(_ version: String) {
        LoggerService.shared.info(module: "PDFCacheService", message: "清理版本缓存: \(version)")
        let versionDirectory = cacheDirectory.appendingPathComponent(version)
        
        guard fileManager.fileExists(atPath: versionDirectory.path) else {
            LoggerService.shared.info(module: "PDFCacheService", message: "版本目录不存在: \(version)")
            return
        }
        
        do {
            try fileManager.removeItem(at: versionDirectory)
            LoggerService.shared.info(module: "PDFCacheService", message: "成功清理版本缓存: \(version)")
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "清理缓存失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 清理非当前版本的缓存
    /// 清理所有非当前 AIRAC 版本的缓存
    func clearOldVersionCaches(modelContext: ModelContext) {
        LoggerService.shared.info(module: "PDFCacheService", message: "开始清理旧版本缓存")
        guard let currentVersion = getCurrentAIRACVersion(modelContext: modelContext) else {
            LoggerService.shared.warning(module: "PDFCacheService", message: "无法获取当前版本，跳过清理")
            return
        }
        
        do {
            let cacheContents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )
            
            for versionDir in cacheContents where versionDir.hasDirectoryPath {
                let versionName = versionDir.lastPathComponent
                
                // 如果不是当前版本，则删除
                if versionName != currentVersion {
                    try fileManager.removeItem(at: versionDir)
                    LoggerService.shared.info(module: "PDFCacheService", message: "已清理旧版本缓存: \(versionName)")
                }
            }
            LoggerService.shared.info(module: "PDFCacheService", message: "旧版本缓存清理完成")
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "清理旧版本缓存失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 清理所有缓存
    /// 清理所有 PDF 缓存
    func clearAllCache() {
        LoggerService.shared.info(module: "PDFCacheService", message: "开始清理所有 PDF 缓存")
        do {
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.removeItem(at: cacheDirectory)
                // 重新创建缓存目录
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                LoggerService.shared.info(module: "PDFCacheService", message: "所有 PDF 缓存清理完成")
            }
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "清理所有缓存失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 获取缓存大小
    /// 获取所有缓存的总大小
    func getCacheSize() -> Int64 {
        return calculateDirectorySize(url: cacheDirectory)
    }
    
    /// 递归计算目录大小
    private func calculateDirectorySize(url: URL) -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            
            if resourceValues.isDirectory == true {
                // 如果是目录，递归计算子文件
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                    options: []
                )
                
                for fileURL in contents {
                    totalSize += calculateDirectorySize(url: fileURL)
                }
            } else {
                // 如果是文件，累加大小
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "计算文件大小失败: \(error.localizedDescription)")
        }
        
        return totalSize
    }
    
    /// 格式化缓存大小显示
    func getFormattedCacheSize() -> String {
        let size = getCacheSize()
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// 获取 PDF 缓存 + 数据缓存 的总大小
    func getTotalCacheSize() -> Int64 {
        let pdfSize = calculateDirectorySize(url: cacheDirectory)
        let dataSize = calculateDirectorySize(url: dataCacheDirectory)
        return pdfSize + dataSize
    }

    /// 获取总缓存（PDF+数据）格式化显示
    func getFormattedTotalCacheSize() -> String {
        let size = getTotalCacheSize()
        if size == 0 {
            return "0 KB"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    // MARK: - 获取缓存统计信息
    /// 获取各版本的缓存统计
    func getCacheStatistics() -> [String: Int] {
        var statistics: [String: Int] = [:]
        
        do {
            let cacheContents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )
            
            for versionDir in cacheContents where versionDir.hasDirectoryPath {
                let versionName = versionDir.lastPathComponent
                let versionContents = try fileManager.contentsOfDirectory(
                    at: versionDir,
                    includingPropertiesForKeys: nil
                )
                statistics[versionName] = versionContents.count
            }
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "获取缓存统计失败: \(error.localizedDescription)")
        }
        
        return statistics
    }
    
    // MARK: - 数据缓存（机场列表、航路图列表等）
    
    /// 生成数据缓存文件路径
    private func dataCacheFilePath(airacVersion: String, dataType: String) -> URL {
        let versionDirectory = dataCacheDirectory.appendingPathComponent(airacVersion)
        
        // 确保 AIRAC 版本目录存在
        if !fileManager.fileExists(atPath: versionDirectory.path) {
            try? fileManager.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
        }
        
        let fileName = "\(dataType).json"
        return versionDirectory.appendingPathComponent(fileName)
    }
    
    /// 缓存 Codable 数据（如机场列表、航路图列表）
    func cacheData<T: Codable>(_ data: T, airacVersion: String, dataType: String) throws {
        let filePath = dataCacheFilePath(airacVersion: airacVersion, dataType: dataType)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: filePath)
    }
    
    /// 从缓存加载 Codable 数据
    func loadCachedData<T: Codable>(_ type: T.Type, airacVersion: String, dataType: String) -> T? {
        let filePath = dataCacheFilePath(airacVersion: airacVersion, dataType: dataType)
        
        guard fileManager.fileExists(atPath: filePath.path) else {
            return nil
        }
        
        do {
            let jsonData = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: jsonData)
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "加载缓存数据失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 检查数据缓存是否存在
    func isDataCached(airacVersion: String, dataType: String) -> Bool {
        let filePath = dataCacheFilePath(airacVersion: airacVersion, dataType: dataType)
        return fileManager.fileExists(atPath: filePath.path)
    }
    
    /// 清理数据缓存
    func clearDataCache() {
        LoggerService.shared.info(module: "PDFCacheService", message: "开始清理数据缓存")
        do {
            if fileManager.fileExists(atPath: dataCacheDirectory.path) {
                try fileManager.removeItem(at: dataCacheDirectory)
                // 重新创建缓存目录
                LoggerService.shared.info(module: "PDFCacheService", message: "数据缓存清理完成")
            }
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "清理数据缓存失败: \(error.localizedDescription)")
        }
    }
    
    /// 清理指定版本的数据缓存
    func clearDataCacheForVersion(_ version: String) {
        LoggerService.shared.info(module: "PDFCacheService", message: "清理版本数据缓存: \(version)")
        let versionDirectory = dataCacheDirectory.appendingPathComponent(version)
        
        guard fileManager.fileExists(atPath: versionDirectory.path) else {
            LoggerService.shared.info(module: "PDFCacheService", message: "版本数据缓存目录不存在: \(version)")
            return
        }
        
        do {
            try fileManager.removeItem(at: versionDirectory)
            LoggerService.shared.info(module: "PDFCacheService", message: "已清理 AIRAC \(version) 的数据缓存")
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "清理数据缓存失败: \(error.localizedDescription)")
        }
    }
    
    /// 清理旧版本数据缓存
    func clearOldVersionDataCaches(modelContext: ModelContext) {
        LoggerService.shared.info(module: "PDFCacheService", message: "开始清理旧版本数据缓存")
        guard let currentVersion = getCurrentAIRACVersion(modelContext: modelContext) else {
            LoggerService.shared.warning(module: "PDFCacheService", message: "无法获取当前版本，跳过数据缓存清理")
            return
        }
        
        do {
            let cacheContents = try fileManager.contentsOfDirectory(
                at: dataCacheDirectory,
                includingPropertiesForKeys: nil
            )
            
            for versionDir in cacheContents where versionDir.hasDirectoryPath {
                let versionName = versionDir.lastPathComponent
                
                // 如果不是当前版本，则删除
                if versionName != currentVersion {
                    try fileManager.removeItem(at: versionDir)
                    LoggerService.shared.info(module: "PDFCacheService", message: "已清理旧版本数据缓存: \(versionName)")
                }
            }
            LoggerService.shared.info(module: "PDFCacheService", message: "旧版本数据缓存清理完成")
        } catch {
            LoggerService.shared.error(module: "PDFCacheService", message: "清理旧版本数据缓存失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - 数据类型枚举
extension PDFCacheService {
    enum DataType {
        static let airports = "airports"           // 机场列表
        static let enrouteCharts = "enroute"      // 航路图列表
        static let aipDocuments = "aip"           // AIP 文档列表
        static let supDocuments = "sup"           // SUP 文档列表
        static let amdtDocuments = "amdt"         // AMDT 文档列表
        static let notamDocuments = "notam"       // NOTAM 文档列表
    }
}

