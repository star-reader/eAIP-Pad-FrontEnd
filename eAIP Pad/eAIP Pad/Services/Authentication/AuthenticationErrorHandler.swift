import Foundation

// MARK: - 认证错误处理器
struct AuthenticationErrorHandler {
    
    /// 获取友好的错误信息（Apple 登录错误）
    static func friendlyErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" {
            switch nsError.code {
            case 1000:
                return "登录已取消"
            case 1001:
                return "登录请求无效，请重试"
            case 1002:
                return "登录请求未被处理"
            case 1003:
                return "登录失败，请稍后重试"
            case 1004:
                return "当前设备不支持 Apple 登录"
            default:
                return "登录失败，请重试"
            }
        }

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "网络连接失败，请检查网络设置"
            case NSURLErrorTimedOut:
                return "网络请求超时，请重试"
            case NSURLErrorCannotConnectToHost:
                return "无法连接到服务器"
            default:
                return "网络错误，请检查网络连接"
            }
        }

        return "发生未知错误，请稍后重试"
    }
    
    /// 获取友好的后端错误信息
    static func friendlyBackendErrorMessage(from error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "网络连接失败，请检查网络设置"
            case NSURLErrorTimedOut:
                return "服务器响应超时，请稍后重试"
            case NSURLErrorCannotConnectToHost:
                return "无法连接到服务器，请检查网络"
            default:
                return "网络错误：\(error.localizedDescription)"
            }
        }

        let errorDescription = error.localizedDescription

        if errorDescription.contains("Apple 用户不存在") || errorDescription.contains("Apple ID") {
            return errorDescription
        }

        if errorDescription.contains("401") {
            return "身份验证失败，请重新登录"
        } else if errorDescription.contains("403") {
            return "访问被拒绝，请联系客服"
        } else if errorDescription.contains("404") {
            return "Apple 账号未注册，请先在后台注册"
        } else if errorDescription.contains("500") || errorDescription.contains("502")
            || errorDescription.contains("503")
        {
            return "服务器繁忙，请稍后重试"
        }

        return "登录失败：\(errorDescription)"
    }
}
