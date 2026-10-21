import Foundation

// MARK: - 应用环境配置（仅用于控制日志级别，App 数据完全来自本地导入，不再有网络环境配置）
enum AppEnvironment {
    case development
    case production

    nonisolated(unsafe) static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    // MARK: - 日志级别
    var logLevel: LogLevel {
        switch self {
        case .development:
            return .verbose
        case .production:
            return .warning
        }
    }

    // MARK: - 是否启用详细日志
    var enableVerboseLogging: Bool {
        switch self {
        case .development:
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

extension AppEnvironment {
    static var currentLogLevel: LogLevel {
        #if DEBUG
        return .verbose
        #else
        return .info
        #endif
    }
}
