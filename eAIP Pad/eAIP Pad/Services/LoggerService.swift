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
    let isEncrypted: Bool
    
    init(type: LogType, module: String, message: String, isEncrypted: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.module = module
        self.message = message
        self.isEncrypted = isEncrypted
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
    
    private let rsaPublicKeyString = SharedKey.getRSAPublicKey()
    
    private var rsaPublicKey: SecKey?
    
    private init() {
        setupRSAPublicKey()
        log(type: .info, module: "LoggerService", message: "日志服务已初始化")
    }
    
    // MARK: - RSA Setup
    private func setupRSAPublicKey() {
        let cleanedKey = rsaPublicKeyString
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let keyData = Data(base64Encoded: cleanedKey) else {
            osLog.error("无法解码 RSA 公钥")
            return
        }
        
        // 创建公钥
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                osLog.error("创建 RSA 公钥失败: \(error.localizedDescription)")
            }
            return
        }
        
        self.rsaPublicKey = publicKey
        osLog.info("RSA 公钥配置成功")
    }
    
    private func encryptMessage(_ message: String) -> String? {
        guard let publicKey = rsaPublicKey else {
            osLog.warning("RSA 公钥未配置，无法加密消息")
            return nil
        }
        
        guard let messageData = message.data(using: .utf8) else {
            osLog.error("无法将消息转换为 Data")
            return nil
        }
        
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            messageData as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                osLog.error("RSA 加密失败: \(error.localizedDescription)")
            }
            return nil
        }
        // 返回base64
        return encryptedData.base64EncodedString()
    }
    
    // MARK: - Public Methods
    
    /// 记录日志
    /// - Parameters:
    ///   - type: 日志类型 (info, warning, error)
    ///   - module: 模块名称
    ///   - message: 日志消息
    ///   - encrypt: 是否加密消息，默认为 false
    func log(type: LogType, module: String, message: String, encrypt: Bool = false) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var finalMessage = message
            
            // 如果需要加密
            if encrypt {
                if let encryptedBase64 = self.encryptMessage(message) {
                    finalMessage = encryptedBase64
                } else {
                    finalMessage = "[加密失败] \(message)"
                }
            }
            
            let entry = LogEntry(
                type: type,
                module: module,
                message: finalMessage,
                isEncrypted: encrypt
            )
            
            self.logs.append(entry)
            
            if self.logs.count > self.maxLogCount {
                self.logs.removeFirst(self.logs.count - self.maxLogCount)
            }
            
            switch type {
            case .info:
                self.osLog.info("[\(module)] \(finalMessage)")
            case .warning:
                self.osLog.warning("[\(module)] \(finalMessage)")
            case .error:
                self.osLog.error("[\(module)] \(finalMessage)")
            }
        }
    }
    
    /// 便捷方法：记录 info 日志
    func info(module: String, message: String, encrypt: Bool = false) {
        log(type: .info, module: module, message: message, encrypt: encrypt)
    }
    
    /// 便捷方法：记录 warning 日志
    func warning(module: String, message: String, encrypt: Bool = false) {
        log(type: .warning, module: module, message: message, encrypt: encrypt)
    }
    
    /// 便捷方法：记录 error 日志
    func error(module: String, message: String, encrypt: Bool = false) {
        log(type: .error, module: module, message: message, encrypt: encrypt)
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
                
                let logString = self.exportAsString()
                
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

