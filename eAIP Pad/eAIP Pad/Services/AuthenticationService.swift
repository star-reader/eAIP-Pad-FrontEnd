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
            
            // 验证 token 是否仍然有效
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
                self.authenticationState = .error("登录失败: \(error.localizedDescription)")
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
                // 解析错误类型
                let errorMessage: String
                if let authError = error as? ASAuthorizationError {
                    switch authError.code {
                    case .canceled:
                        errorMessage = "用户取消了登录"
                        print("⚠️ 用户取消 Apple 登录")
                    case .failed:
                        errorMessage = "认证失败，请重试"
                        print("❌ Apple 登录失败")
                    case .invalidResponse:
                        errorMessage = "收到无效响应"
                        print("❌ Apple 登录响应无效")
                    case .notHandled:
                        errorMessage = "请求未被处理"
                        print("❌ Apple 登录请求未处理")
                    case .unknown:
                        errorMessage = "发生未知错误"
                        print("❌ Apple 登录发生未知错误")
                    case .notInteractive:
                        errorMessage = "无法显示登录界面"
                        print("❌ Apple 登录无法显示界面")
                    @unknown default:
                        errorMessage = "登录过程出错"
                        print("❌ Apple 登录发生未知错误类型")
                    }
                } else {
                    errorMessage = "Apple 登录失败: \(error.localizedDescription)"
                    print("❌ Apple 登录错误: \(error)")
                }
                
                self.authenticationState = .error(errorMessage)
                
                // 在开发环境下，自动设置为已登录（用于测试）
                #if DEBUG
                if authError.code == .canceled || authError.code == .failed {
                    print("🔧 开发模式：5秒后自动跳过登录...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.simulateLogin()
                    }
                }
                #endif
            }
        }
    }
    
    #if DEBUG
    // 开发模式：模拟登录（仅用于测试）
    private func simulateLogin() {
        print("🔧 开发模式：模拟登录成功")
        self.accessToken = "dev_access_token_\(UUID().uuidString)"
        self.refreshToken = "dev_refresh_token"
        self.isNewUser = false
        self.authenticationState = .authenticated
        self.currentUser = AuthenticatedUser(
            accessToken: self.accessToken!,
            isNewUser: false,
            subscriptionStatus: "trial"
        )
        
        // 保存到 UserDefaults
        UserDefaults.standard.set(self.accessToken, forKey: "access_token")
        UserDefaults.standard.set(self.refreshToken, forKey: "refresh_token")
    }
    #endif
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
