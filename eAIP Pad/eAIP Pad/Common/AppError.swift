import Foundation

// MARK: - 统一错误类型
enum AppError: LocalizedError, Equatable {
    // 网络错误
    case network(AppNetworkError)
    case networkTimeout
    case noInternetConnection
    case serverError(Int)
    
    // 认证错误
    case authenticationFailed(String)
    case unauthorized
    case tokenExpired
    case appleSignInFailed(String)
    
    // 订阅错误
    case subscriptionNotFound
    case subscriptionExpired
    case purchaseFailed(String)
    case restoreFailed(String)
    
    // 数据错误
    case dataNotFound
    case invalidData
    case databaseError(String)
    case cachingFailed(String)
    
    // AIRAC 错误
    case airacUpdateFailed(String)
    case airacVersionNotFound
    
    // PDF 错误
    case pdfLoadFailed(String)
    case pdfNotFound
    case pdfCacheFailed(String)
    
    // 通用错误
    case unknown(Error)
    case customError(String)
    
    var errorDescription: String? {
        switch self {
        // 网络错误
        case .network(let networkError):
            return networkError.localizedDescription
        case .networkTimeout:
            return "网络请求超时，请检查网络连接后重试"
        case .noInternetConnection:
            return "网络连接失败，请检查网络设置"
        case .serverError(let code):
            return "服务器错误 (\(code))，请稍后重试"
            
        // 认证错误
        case .authenticationFailed(let message):
            return "登录失败：\(message)"
        case .unauthorized:
            return "身份验证失败，请重新登录"
        case .tokenExpired:
            return "登录已过期，请重新登录"
        case .appleSignInFailed(let message):
            return "Apple 登录失败：\(message)"
            
        // 订阅错误
        case .subscriptionNotFound:
            return "未找到订阅信息"
        case .subscriptionExpired:
            return "订阅已过期，请续订"
        case .purchaseFailed(let message):
            return "购买失败：\(message)"
        case .restoreFailed(let message):
            return "恢复购买失败：\(message)"
            
        // 数据错误
        case .dataNotFound:
            return "未找到数据"
        case .invalidData:
            return "数据格式错误"
        case .databaseError(let message):
            return "数据库错误：\(message)"
        case .cachingFailed(let message):
            return "缓存失败：\(message)"
            
        // AIRAC 错误
        case .airacUpdateFailed(let message):
            return "AIRAC 更新失败：\(message)"
        case .airacVersionNotFound:
            return "未找到 AIRAC 版本信息"
            
        // PDF 错误
        case .pdfLoadFailed(let message):
            return "PDF 加载失败：\(message)"
        case .pdfNotFound:
            return "未找到 PDF 文件"
        case .pdfCacheFailed(let message):
            return "PDF 缓存失败：\(message)"
            
        // 通用错误
        case .unknown(let error):
            return "未知错误：\(error.localizedDescription)"
        case .customError(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkTimeout, .noInternetConnection:
            return "请检查网络连接后重试"
        case .unauthorized, .tokenExpired:
            return "请重新登录"
        case .subscriptionExpired:
            return "请前往订阅页面续订"
        case .serverError:
            return "服务器繁忙，请稍后重试"
        default:
            return nil
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkTimeout, .noInternetConnection, .serverError:
            return true
        case .network(let networkError):
            switch networkError {
            case .timeout, .noConnection:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        return lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - 应用网络错误枚举
enum AppNetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case decodingError(Error)
    case encodingError(Error)
    case serverError(Int)
    case unauthorized
    case forbidden
    case notFound
    case timeout
    case noConnection
    case noRefreshToken
    case requestCancelled
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .invalidResponse:
            return "无效的服务器响应"
        case .noData:
            return "服务器未返回数据"
        case .decodingError(let error):
            return "数据解析失败：\(error.localizedDescription)"
        case .encodingError(let error):
            return "数据编码失败：\(error.localizedDescription)"
        case .serverError(let code):
            return "服务器错误 (\(code))"
        case .unauthorized:
            return "未授权，请登录"
        case .forbidden:
            return "访问被拒绝"
        case .notFound:
            return "请求的资源不存在"
        case .timeout:
            return "请求超时"
        case .noConnection:
            return "网络连接失败"
        case .noRefreshToken:
            return "缺少刷新令牌"
        case .requestCancelled:
            return "请求已取消"
        case .unknown(let error):
            return "网络错误：\(error.localizedDescription)"
        }
    }
}

// MARK: - 错误转换扩展
extension AppError {
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        
        if let appNetworkError = error as? AppNetworkError {
            return .network(appNetworkError)
        }
        
        let nsError = error as NSError
        
        // 网络错误判断
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return .noInternetConnection
            case NSURLErrorTimedOut:
                return .networkTimeout
            case NSURLErrorCannotConnectToHost:
                return .network(.noConnection)
            default:
                return .network(.unknown(error))
            }
        }
        
        return .unknown(error)
    }
}
