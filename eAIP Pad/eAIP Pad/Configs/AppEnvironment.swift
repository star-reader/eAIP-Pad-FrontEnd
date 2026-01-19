import Foundation

// MARK: - 应用环境配置
enum AppEnvironment {
    case development
    case staging
    case production
    
    // MARK: - 当前环境
    nonisolated(unsafe) static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
    
    // MARK: - API 基础 URL
    var baseURL: String {
        switch self {
        case .development:
            return "https://dev-api.usagi-jin.top"
        case .staging:
            return "https://staging-api.usagi-jin.top"
        case .production:
            return "https://api.usagi-jin.top"
        }
    }
    
    // MARK: - API 版本
    var apiVersion: String {
        return "/eaip/v1"
    }
    
    // MARK: - 完整 API URL
    var baseAPIURL: String {
        return baseURL + apiVersion
    }
    
    // MARK: - 请求超时时间
    var requestTimeout: TimeInterval {
        switch self {
        case .development:
            return 30.0
        case .staging:
            return 30.0
        case .production:
            return 30.0
        }
    }
    
    // MARK: - 最大重试次数
    var maxRetryCount: Int {
        switch self {
        case .development:
            return 3
        case .staging:
            return 3
        case .production:
            return 3
        }
    }
    
    // MARK: - 重试延迟（秒）
    func retryDelay(for attempt: Int) -> TimeInterval {
        // 指数退避策略：2^attempt 秒
        return pow(2.0, Double(attempt))
    }
    
    // MARK: - 日志级别
    var logLevel: LogLevel {
        switch self {
        case .development:
            return .verbose
        case .staging:
            return .info
        case .production:
            return .warning
        }
    }
    
    // MARK: - 是否启用详细日志
    var enableVerboseLogging: Bool {
        switch self {
        case .development:
            return true
        case .staging:
            return true
        case .production:
            return false
        }
    }
}

// MARK: - 日志级别
enum LogLevel: Int, Comparable {
    case verbose = 0
    case info = 1
    case warning = 2
    case error = 3
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// 注意：NetworkConfig 将在 NetworkService.swift 中被更新以使用 AppEnvironment
