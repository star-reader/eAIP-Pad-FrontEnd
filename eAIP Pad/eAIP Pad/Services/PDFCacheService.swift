import Foundation
import SwiftData
import PDFKit

// MARK: - PDF 缓存管理服务
class PDFCacheService {
    static let shared = PDFCacheService()
    
    private let fileManager = FileManager.default
    private var cacheDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cachePath = documentsPath.appendingPathComponent("PDFCache")
        
        // 确保缓存目录存在
        if !fileManager.fileExists(atPath: cachePath.path) {
            try? fileManager.createDirectory(at: cachePath, withIntermediateDirectories: true)
        }
        
        return cachePath
    }
    
    private init() {}
    
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
        print("✅ PDF 已缓存: \(documentType)_\(id) (AIRAC: \(airacVersion))")
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
            print("获取当前 AIRAC 版本失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 清理旧版本缓存
    /// 清理指定 AIRAC 版本的所有缓存
    func clearCacheForVersion(_ version: String) {
        let versionDirectory = cacheDirectory.appendingPathComponent(version)
        
        guard fileManager.fileExists(atPath: versionDirectory.path) else {
            return
        }
        
        do {
            try fileManager.removeItem(at: versionDirectory)
            print("✅ 已清理 AIRAC \(version) 的缓存")
        } catch {
            print("清理缓存失败: \(error)")
        }
    }
    
    // MARK: - 清理非当前版本的缓存
    /// 清理所有非当前 AIRAC 版本的缓存
    func clearOldVersionCaches(modelContext: ModelContext) {
        guard let currentVersion = getCurrentAIRACVersion(modelContext: modelContext) else {
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
                    print("✅ 已清理旧版本缓存: \(versionName)")
                }
            }
        } catch {
            print("清理旧版本缓存失败: \(error)")
        }
    }
    
    // MARK: - 清理所有缓存
    /// 清理所有 PDF 缓存
    func clearAllCache() {
        do {
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.removeItem(at: cacheDirectory)
                // 重新创建缓存目录
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                print("✅ 已清理所有 PDF 缓存")
            }
        } catch {
            print("清理所有缓存失败: \(error)")
        }
    }
    
    // MARK: - 获取缓存大小
    /// 获取所有缓存的总大小
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let cacheContents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: []
            )
            
            for fileURL in cacheContents {
                totalSize += calculateDirectorySize(url: fileURL)
            }
        } catch {
            print("计算缓存大小失败: \(error)")
        }
        
        return totalSize
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
            print("计算文件大小失败: \(error)")
        }
        
        return totalSize
    }
    
    /// 格式化缓存大小显示
    func getFormattedCacheSize() -> String {
        let size = getCacheSize()
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
            print("获取缓存统计失败: \(error)")
        }
        
        return statistics
    }
}

