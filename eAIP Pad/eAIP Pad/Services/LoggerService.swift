import Foundation
import SwiftUI
import OSLog

// MARK: - Log Types
enum LogType: String, Codable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

// MARK: - Log Entry
struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: LogType
    let module: String
    let message: String
    
    init(type: LogType, module: String, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.module = module
        self.message = message
    }
    
    func formatted() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timeString = dateFormatter.string(from: timestamp)
        
        return "\(timeString) - \(type.rawValue), 模块[\(module)] \(message)"
    }
}

// MARK: - Logger Service
@Observable
class LoggerService {
    static let shared = LoggerService()
    private var logs: [LogEntry] = []
    private let maxLogCount = 10000 // 最大日志条目数
    private let queue = DispatchQueue(label: "logger.queue", qos: .utility)
    private let osLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "eAIP-Pad", category: "LoggerService")
    
    private init() {
        log(type: .info, module: "LoggerService", message: "日志服务已初始化")
    }
    
    // MARK: - Public Methods
    
    /// 记录日志
    /// - Parameters:
    ///   - type: 日志类型 (info, warning, error)
    ///   - module: 模块名称
    ///   - message: 日志消息
    func log(type: LogType, module: String, message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let entry = LogEntry(
                type: type,
                module: module,
                message: message
            )
            
            self.logs.append(entry)
            
            if self.logs.count > self.maxLogCount {
                self.logs.removeFirst(self.logs.count - self.maxLogCount)
            }
            
            switch type {
            case .info:
                self.osLog.info("[\(module)] \(message)")
            case .warning:
                self.osLog.warning("[\(module)] \(message)")
            case .error:
                self.osLog.error("[\(module)] \(message)")
            }
        }
    }
    
    /// 便捷方法：记录 info 日志
    func info(module: String, message: String) {
        log(type: .info, module: module, message: message)
    }
    
    /// 便捷方法：记录 warning 日志
    func warning(module: String, message: String) {
        log(type: .warning, module: module, message: message)
    }
    
    /// 便捷方法：记录 error 日志
    func error(module: String, message: String) {
        log(type: .error, module: module, message: message)
    }
    
    /// 导出日志为字符串
    /// - Returns: 所有日志的字符串表示
    func exportAsString() -> String {
        var result = ""
        result += "=== eAIP Pad 日志 ===\n"
        result += "导出时间: \(Date().formatted(date: .long, time: .complete))\n"
        result += "日志条目数: \(logs.count)\n"
        result += "======================================\n\n"
        
        queue.sync {
            for entry in logs {
                result += entry.formatted() + "\n"
            }
        }
        
        return result
    }
    
    /// 导出日志为文件（可以附加到邮件）
    /// - Returns: 日志文件的 URL，如果失败返回 nil
    func exportAsFile() -> URL? {
        let logString = exportAsString()
        
        // 创建临时文件
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "eAIP_Pad_Log_\(dateString).txt"
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try logString.write(to: fileURL, atomically: true, encoding: .utf8)
            osLog.info("日志文件已导出: \(fileURL.path)")
            return fileURL
        } catch {
            osLog.error("导出日志文件失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 导出日志为文件（异步版本，用于 async/await 上下文）
    /// - Returns: 日志文件的 URL
    /// - Throws: 如果导出失败则抛出错误
    public func exportLogsAsFile() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "LoggerService", code: -1, userInfo: [NSLocalizedDescriptionKey: "LoggerService 实例不存在"]))
                    return
                }
                
                // 直接在 queue 中访问 logs，避免调用 exportAsString() 导致的嵌套 queue.sync
                var logString = ""
                logString += "=== eAIP Pad 日志 ===\n"
                logString += "导出时间: \(Date().formatted(date: .long, time: .complete))\n"
                logString += "日志条目数: \(self.logs.count)\n"
                logString += "======================================\n\n"
                
                for entry in self.logs {
                    logString += entry.formatted() + "\n"
                }
                
                // 创建临时文件
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                let dateString = dateFormatter.string(from: Date())
                let fileName = "eAIP_Pad_Log_\(dateString).txt"
                
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try logString.write(to: fileURL, atomically: true, encoding: .utf8)
                    self.osLog.info("日志文件已异步导出: \(fileURL.path)")
                    continuation.resume(returning: fileURL)
                } catch {
                    self.osLog.error("异步导出日志文件失败: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// 导出日志为 Data（可用于分享）
    /// - Returns: 日志文件的 Data
    func exportAsData() -> Data? {
        let logString = exportAsString()
        return logString.data(using: .utf8)
    }
    
    /// 获取日志条目数量
    func getLogCount() -> Int {
        return queue.sync {
            return logs.count
        }
    }
    
    /// 获取最近的 N 条日志
    /// - Parameter count: 要获取的日志数量
    /// - Returns: 日志条目数组
    func getRecentLogs(count: Int) -> [LogEntry] {
        return queue.sync {
            let startIndex = max(0, logs.count - count)
            return Array(logs[startIndex..<logs.count])
        }
    }
    
    /// 获取所有日志
    /// - Returns: 所有日志条目
    func getAllLogs() -> [LogEntry] {
        return queue.sync {
            return logs
        }
    }
    
    /// 清除所有日志
    func clearLogs() {
        queue.async { [weak self] in
            self?.logs.removeAll()
            self?.osLog.info("所有日志已清除")
        }
    }
    
    /// 按类型筛选日志
    /// - Parameter type: 日志类型
    /// - Returns: 筛选后的日志条目
    func filterLogs(by type: LogType) -> [LogEntry] {
        return queue.sync {
            return logs.filter { $0.type == type }
        }
    }
    
    /// 按模块筛选日志
    /// - Parameter module: 模块名称
    /// - Returns: 筛选后的日志条目
    func filterLogs(by module: String) -> [LogEntry] {
        return queue.sync {
            return logs.filter { $0.module == module }
        }
    }
}

/*
 LoggerService.shared.log(type: .info, module: "Authentication", message: "用户登录成功")
 LoggerService.shared.info(module: "App", message: "应用启动")
 let logString = LoggerService.shared.exportAsString()
 
 if let fileURL = LoggerService.shared.exportAsFile() {
     // 使用 MFMailComposeViewController 或 UIActivityViewController 分享
     let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
     present(activityVC, animated: true)
 }
 let allLogs = LoggerService.shared.getAllLogs()
 let recentLogs = LoggerService.shared.getRecentLogs(count: 100)
 let errorLogs = LoggerService.shared.filterLogs(by: .error)
 */
