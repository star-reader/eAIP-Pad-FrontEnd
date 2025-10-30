import Foundation
import SwiftUI
import SwiftData
import AuthenticationServices
import Combine

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 认证状态枚举
enum AuthenticationState: Equatable {
    case notAuthenticated    // 未登录
    case authenticating     // 登录中
    case authenticated      // 已登录
    case error(String)      // 登录错误
}

// MARK: - 认证管理服务
class AuthenticationService: NSObject, ObservableObject {
    static let shared = AuthenticationService()
    
    // 认证状态
    @Published var authenticationState: AuthenticationState = .notAuthenticated
    @Published var currentUser: AuthenticatedUser?
    
    // 用户信息
    var accessToken: String?
    var refreshToken: String?
    var isNewUser = false
    
    private override init() {
        super.init()
        checkStoredCredentials()
    }
    
    // MARK: - 检查存储的凭据
    private func checkStoredCredentials() {
        // 从 Keychain 或 UserDefaults 检查存储的 token
        if let storedAccessToken = UserDefaults.standard.string(forKey: "access_token"),
           let storedRefreshToken = UserDefaults.standard.string(forKey: "refresh_token") {
            self.accessToken = storedAccessToken
            self.refreshToken = storedRefreshToken
            
            // 立即设置为已认证状态，避免闪现登录页面
            self.authenticationState = .authenticated
            self.currentUser = AuthenticatedUser(accessToken: storedAccessToken)
            
            // 后台验证 token 是否仍然有效
            Task {
                await validateStoredTokens()
            }
        }
    }
    
    // MARK: - 验证存储的 tokens
    private func validateStoredTokens() async {
        guard let accessToken = accessToken else {
            await MainActor.run {
                self.authenticationState = .notAuthenticated
            }
            return
        }
        
        // 设置网络服务的 token
        NetworkService.shared.setTokens(accessToken: accessToken, refreshToken: refreshToken ?? "")
        
        do {
            // 尝试获取订阅状态来验证 token
            let _ = try await NetworkService.shared.getSubscriptionStatus()
            
            await MainActor.run {
                self.authenticationState = .authenticated
                self.currentUser = AuthenticatedUser(accessToken: accessToken)
            }
        } catch {
            // Token 无效，清除存储的凭据
            await MainActor.run {
                self.clearStoredCredentials()
                self.authenticationState = .notAuthenticated
            }
        }
    }
    
    // MARK: - Apple Sign In
    func signInWithApple() async {
        await MainActor.run {
            self.authenticationState = .authenticating
        }
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    // MARK: - 处理 Apple 登录成功
    private func handleAppleSignInSuccess(credential: ASAuthorizationAppleIDCredential) async {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            await MainActor.run {
                self.authenticationState = .error("无法获取身份令牌")
            }
            return
        }
        
        do {
            // 调用后端 Apple 登录接口
            let response = try await NetworkService.shared.appleLogin(idToken: tokenString)
            
            await MainActor.run {
                // 存储 tokens
                self.accessToken = response.accessToken
                self.refreshToken = response.refreshToken
                self.isNewUser = response.isNewUser
                
                // 保存到本地存储
                UserDefaults.standard.set(response.accessToken, forKey: "access_token")
                UserDefaults.standard.set(response.refreshToken, forKey: "refresh_token")
                UserDefaults.standard.set(response.isNewUser, forKey: "is_new_user")
                
                // 设置网络服务的 token
                NetworkService.shared.setTokens(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken
                )
                
                // 创建用户对象
                self.currentUser = AuthenticatedUser(
                    accessToken: response.accessToken,
                    isNewUser: response.isNewUser,
                    subscriptionStatus: response.subscription
                )
                
                self.authenticationState = .authenticated
            }
        } catch {
            await MainActor.run {
                let errorMessage = self.friendlyBackendErrorMessage(from: error)
                self.authenticationState = .error(errorMessage)
            }
        }
    }
    
    // MARK: - 登出
    func signOut() {
        clearStoredCredentials()
        NetworkService.shared.clearTokens()
        
        currentUser = nil
        authenticationState = .notAuthenticated
    }
    
    // MARK: - 清除存储的凭据
    private func clearStoredCredentials() {
        accessToken = nil
        refreshToken = nil
        
        UserDefaults.standard.removeObject(forKey: "access_token")
        UserDefaults.standard.removeObject(forKey: "refresh_token")
        UserDefaults.standard.removeObject(forKey: "is_new_user")
    }
    
    // MARK: - 检查是否已登录
    var isAuthenticated: Bool {
        return authenticationState == .authenticated && currentUser != nil
    }
    
    // MARK: - 获取错误信息
    var errorMessage: String? {
        if case .error(let message) = authenticationState {
            return message
        }
        return nil
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthenticationService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            Task {
                await handleAppleSignInSuccess(credential: appleIDCredential)
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task {
            await MainActor.run {
                let errorMessage = self.friendlyErrorMessage(from: error)
                self.authenticationState = .error(errorMessage)
            }
        }
    }
    
    // MARK: - 友好的错误提示（Apple 登录）
    private func friendlyErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        
        // 检查是否是 AuthenticationServices 的错误
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
        
        // 网络相关错误
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
        
        // 其他错误
        return "发生未知错误，请稍后重试"
    }
    
    // MARK: - 友好的错误提示（后端登录）
    private func friendlyBackendErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        
        // 网络相关错误
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "网络连接失败，请检查网络设置"
            case NSURLErrorTimedOut:
                return "服务器响应超时，请稍后重试"
            case NSURLErrorCannotConnectToHost:
                return "无法连接到服务器，请检查网络"
            default:
                return "网络错误，请检查网络连接"
            }
        }
        
        // HTTP 状态码错误（如果有的话）
        let errorDescription = error.localizedDescription
        if errorDescription.contains("401") {
            return "身份验证失败，请重新登录"
        } else if errorDescription.contains("403") {
            return "访问被拒绝，请联系客服"
        } else if errorDescription.contains("404") {
            return "服务不可用，请稍后重试"
        } else if errorDescription.contains("500") || errorDescription.contains("502") || errorDescription.contains("503") {
            return "服务器繁忙，请稍后重试"
        }
        
        // 默认错误
        return "登录失败，请检查网络或稍后重试"
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("无法获取窗口")
        }
        return window
        #else
        fatalError("UIKit 不可用")
        #endif
    }
}

// MARK: - 认证用户模型
struct AuthenticatedUser {
    let accessToken: String
    let isNewUser: Bool
    let subscriptionStatus: String
    let authenticatedAt: Date
    
    init(accessToken: String, isNewUser: Bool = false, subscriptionStatus: String = "inactive") {
        self.accessToken = accessToken
        self.isNewUser = isNewUser
        self.subscriptionStatus = subscriptionStatus
        self.authenticatedAt = Date()
    }
}
