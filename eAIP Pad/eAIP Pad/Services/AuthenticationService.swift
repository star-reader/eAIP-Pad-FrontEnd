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
    var appleUserId: String?  // Apple 用户 ID（用于订阅验证）
    
    // Token 自动刷新定时器
    private var tokenRefreshTimer: Timer?
    private let tokenRefreshInterval: TimeInterval = 3600 // 1小时 = 3600秒
    
    private override init() {
        super.init()
        LoggerService.shared.info(module: "AuthenticationService", message: "认证服务初始化")
        checkStoredCredentials()
        setupAppLifecycleObservers()
    }
    
    deinit {
        // deinit 不能是 async，但我们可以在主线程上停止定时器
        if Thread.isMainThread {
            tokenRefreshTimer?.invalidate()
            tokenRefreshTimer = nil
        } else {
            DispatchQueue.main.sync {
                self.tokenRefreshTimer?.invalidate()
                self.tokenRefreshTimer = nil
            }
        }
        removeAppLifecycleObservers()
    }
    
    // MARK: - 检查存储的凭据
    private func checkStoredCredentials() {
        LoggerService.shared.info(module: "AuthenticationService", message: "检查存储的凭据")
        // 从 Keychain 或 UserDefaults 检查存储的 token
        let storedAccessToken = UserDefaults.standard.string(forKey: "access_token")
        let storedRefreshToken = UserDefaults.standard.string(forKey: "refresh_token")
        self.appleUserId = UserDefaults.standard.string(forKey: "apple_user_id")
        
        guard let storedAccessToken = storedAccessToken else {
            LoggerService.shared.info(module: "AuthenticationService", message: "未找到存储的凭据")
            return
        }
        
        self.accessToken = storedAccessToken
        self.refreshToken = storedRefreshToken
        
        // 立即设置为已认证状态，避免闪现登录页面
        self.authenticationState = .authenticated
        self.currentUser = AuthenticatedUser(accessToken: storedAccessToken)
        LoggerService.shared.info(module: "AuthenticationService", message: "找到存储的凭据，设置为已认证状态， useid为\(String(describing: appleUserId))")
        
        // 设置网络服务的 token
        NetworkService.shared.setTokens(accessToken: storedAccessToken, refreshToken: storedRefreshToken ?? "")
        
        // 如果有 refresh_token，启动时直接尝试刷新 token（因为 access_token 可能已过期）
        // 如果没有 refresh_token，验证现有的 access_token 是否有效
        Task {
            if storedRefreshToken != nil {
                // 有 refresh_token，直接尝试刷新
                LoggerService.shared.info(module: "AuthenticationService", message: "有 refresh_token，尝试刷新")
                await refreshTokenIfNeeded()
            } else {
                // 没有 refresh_token，验证现有的 access_token
                LoggerService.shared.info(module: "AuthenticationService", message: "无 refresh_token，验证现有 token")
                await validateStoredTokens()
            }
        }
    }
    
    // MARK: - 刷新 Token（如果需要）
    private func refreshTokenIfNeeded() async {
        guard let refreshToken = refreshToken else {
            // 没有 refresh_token，验证现有的 access_token
            await validateStoredTokens()
            return
        }
        
        // 设置网络服务的 token（用于刷新请求）
        NetworkService.shared.setTokens(accessToken: accessToken ?? "", refreshToken: refreshToken)
        
        do {
            // 尝试刷新 access token
            try await NetworkService.shared.refreshAccessToken()
            
            // 刷新成功，获取新的 token
            if let newAccessToken = NetworkService.shared.getCurrentAccessToken() {
                let newRefreshToken = NetworkService.shared.getCurrentRefreshToken()
                
                await MainActor.run {
                    self.accessToken = newAccessToken
                    if let newRefreshToken = newRefreshToken {
                        self.refreshToken = newRefreshToken
                        UserDefaults.standard.set(newRefreshToken, forKey: "refresh_token")
                    }
                    UserDefaults.standard.set(newAccessToken, forKey: "access_token")
                    self.authenticationState = .authenticated
                    self.currentUser = AuthenticatedUser(accessToken: newAccessToken)
                    
                    // 启动自动刷新定时器
                    self.startTokenRefreshTimer()
                }
                LoggerService.shared.info(module: "AuthenticationService", message: "Token 刷新成功")
                return
            }
        } catch {
            // 刷新失败，尝试验证现有的 access_token（可能还有效）
            LoggerService.shared.warning(module: "AuthenticationService", message: "Token 刷新失败，尝试验证现有 token: \(error.localizedDescription)")
            await validateStoredTokens()
        }
    }
    
    // MARK: - 验证存储的 tokens
    private func validateStoredTokens() async {
        LoggerService.shared.info(module: "AuthenticationService", message: "开始验证存储的 token")
        guard let accessToken = accessToken else {
            await MainActor.run {
                self.authenticationState = .notAuthenticated
            }
            LoggerService.shared.warning(module: "AuthenticationService", message: "无 access_token，设置为未认证")
            return
        }
        
        // 设置网络服务的 token
        NetworkService.shared.setTokens(accessToken: accessToken, refreshToken: refreshToken ?? "")
        
        do {
            // 通过调用需要认证的 API 来验证 token 是否有效
            // 使用 getCurrentAIRAC 作为验证端点，因为它是只读的且相对轻量
            _ = try await NetworkService.shared.getCurrentAIRAC()
            
            // Token 有效，确认认证状态
            await MainActor.run {
                self.authenticationState = .authenticated
                self.currentUser = AuthenticatedUser(accessToken: accessToken)
                
                // 如果有 refresh_token，启动自动刷新定时器
                if self.refreshToken != nil {
                    self.startTokenRefreshTimer()
                }
            }
            LoggerService.shared.info(module: "AuthenticationService", message: "Token 验证成功")
        } catch {
            // Token 无效（401）或网络错误，尝试刷新 token
            if refreshToken != nil {
                do {
                    // 尝试刷新 access token
                    try await NetworkService.shared.refreshAccessToken()
                    
                    // 刷新成功，获取新的 token
                    if let newAccessToken = NetworkService.shared.getCurrentAccessToken() {
                        // 更新 refresh token（如果刷新时返回了新的）
                        let newRefreshToken = NetworkService.shared.getCurrentRefreshToken()
                        await MainActor.run {
                            self.accessToken = newAccessToken
                            if let newRefreshToken = newRefreshToken {
                                self.refreshToken = newRefreshToken
                                UserDefaults.standard.set(newRefreshToken, forKey: "refresh_token")
                            }
                            UserDefaults.standard.set(newAccessToken, forKey: "access_token")
                            self.authenticationState = .authenticated
                            self.currentUser = AuthenticatedUser(accessToken: newAccessToken)
                            
                            // 启动自动刷新定时器
                            self.startTokenRefreshTimer()
                        }
                        LoggerService.shared.info(module: "AuthenticationService", message: "Token 验证失败后刷新成功")
                        return
                    }
                } catch {
                    // 刷新也失败，清除凭据
                    LoggerService.shared.error(module: "AuthenticationService", message: "Token 刷新失败: \(error.localizedDescription)")
                }
            }
            
            // Token 无效且无法刷新，清除存储的凭据
            await MainActor.run {
                self.clearStoredCredentials()
                self.authenticationState = .notAuthenticated
            }
            LoggerService.shared.warning(module: "AuthenticationService", message: "Token 无效且无法刷新，已清除凭据")
        }
    }
    
    // MARK: - Apple Sign In
    func signInWithApple() async {
        LoggerService.shared.info(module: "AuthenticationService", message: "开始 Apple 登录")
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
        LoggerService.shared.info(module: "AuthenticationService", message: "处理 Apple 登录成功回调")
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            await MainActor.run {
                self.authenticationState = .error("无法获取身份令牌")
            }
            LoggerService.shared.error(module: "AuthenticationService", message: "无法获取 Apple 身份令牌")
            return
        }
        
        // 获取 Apple 用户 ID（唯一标识符）
        let appleUserId = credential.user
        LoggerService.shared.info(module: "AuthenticationService", message: "获取到 Apple 用户 ID")
        
        do {
            // 调用后端 Apple 登录接口
            let response = try await NetworkService.shared.appleLogin(idToken: tokenString)
            LoggerService.shared.info(module: "AuthenticationService", message: "后端登录接口调用成功")
            
            await MainActor.run {
                // 存储 tokens
                self.accessToken = response.accessToken
                self.refreshToken = response.refreshToken
                self.isNewUser = response.isNewUser
                self.appleUserId = appleUserId  // 存储 Apple 用户 ID
                
                // 保存到本地存储
                UserDefaults.standard.set(response.accessToken, forKey: "access_token")
                UserDefaults.standard.set(response.refreshToken, forKey: "refresh_token")
                UserDefaults.standard.set(response.isNewUser, forKey: "is_new_user")
                UserDefaults.standard.set(appleUserId, forKey: "apple_user_id")  // 存储 Apple 用户 ID
                
                // 强制同步到磁盘
                UserDefaults.standard.synchronize()
                LoggerService.shared.info(module: "AuthenticationService", message: "已保存登录凭据到本地存储")
                
                // 设置网络服务的 token
                NetworkService.shared.setTokens(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken
                )
                
                // 创建用户对象
                self.currentUser = AuthenticatedUser(
                    accessToken: response.accessToken,
                    isNewUser: response.isNewUser
                )
                
                self.authenticationState = .authenticated
                
                // 启动自动刷新定时器
                self.startTokenRefreshTimer()
            }
            LoggerService.shared.info(module: "AuthenticationService", message: "Apple 登录成功，用户认证完成")
        } catch {
            await MainActor.run {
                let errorMessage = self.friendlyBackendErrorMessage(from: error)
                self.authenticationState = .error(errorMessage)
            }
            LoggerService.shared.error(module: "AuthenticationService", message: "Apple 登录失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 登出
    func signOut() {
        LoggerService.shared.info(module: "AuthenticationService", message: "用户登出")
        stopTokenRefreshTimer()
        clearStoredCredentials()
        NetworkService.shared.clearTokens()
        
        currentUser = nil
        authenticationState = .notAuthenticated
    }
    
    // MARK: - 清除存储的凭据
    private func clearStoredCredentials() {
        accessToken = nil
        refreshToken = nil
        appleUserId = nil
        
        UserDefaults.standard.removeObject(forKey: "access_token")
        UserDefaults.standard.removeObject(forKey: "refresh_token")
        UserDefaults.standard.removeObject(forKey: "is_new_user")
        UserDefaults.standard.removeObject(forKey: "apple_user_id")
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
    
    // MARK: - Token 自动刷新定时器
    @MainActor
    private func startTokenRefreshTimer() {
        stopTokenRefreshTimer() // 先停止现有的定时器
        
        guard refreshToken != nil else {
            return
        }
        
        // 在主线程上创建定时器
        tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: tokenRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performTokenRefresh()
            }
        }
        
        // 将定时器添加到 RunLoop
        if let timer = tokenRefreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    // 非 MainActor 版本的启动方法，用于在异步上下文中调用
    private func startTokenRefreshTimerAsync() async {
        await MainActor.run {
            startTokenRefreshTimer()
        }
    }
    
    @MainActor
    private func stopTokenRefreshTimer() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
    }
    
    @MainActor
    private func performTokenRefresh() async {
        guard let refreshToken = refreshToken else {
            stopTokenRefreshTimer()
            return
        }
        
        // 确保已登录状态
        guard authenticationState == .authenticated else {
            stopTokenRefreshTimer()
            return
        }
        
        LoggerService.shared.info(module: "AuthenticationService", message: "开始自动刷新 access_token")
        
        // 设置网络服务的 token
        NetworkService.shared.setTokens(accessToken: accessToken ?? "", refreshToken: refreshToken)
        
        do {
            // 尝试刷新 access token
            try await NetworkService.shared.refreshAccessToken()
            
            // 刷新成功，获取新的 token
            if let newAccessToken = NetworkService.shared.getCurrentAccessToken() {
                let newRefreshToken = NetworkService.shared.getCurrentRefreshToken()
                
                self.accessToken = newAccessToken
                if let newRefreshToken = newRefreshToken {
                    self.refreshToken = newRefreshToken
                    UserDefaults.standard.set(newRefreshToken, forKey: "refresh_token")
                }
                UserDefaults.standard.set(newAccessToken, forKey: "access_token")
                self.currentUser = AuthenticatedUser(accessToken: newAccessToken)
                
                LoggerService.shared.info(module: "AuthenticationService", message: "Token 自动刷新成功")
            }
        } catch {
            LoggerService.shared.warning(module: "AuthenticationService", message: "Token 自动刷新失败: \(error.localizedDescription)")
            // 刷新失败，但不改变认证状态（可能只是临时网络问题）
            // 下次定时器触发时会再次尝试
        }
    }
    
    // MARK: - App 生命周期监听
    private func setupAppLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }
    
    private func removeAppLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.removeObserver(self)
        #endif
    }
    
    #if canImport(UIKit)
    @objc private func appDidEnterBackground() {
        // App 进入后台时，定时器会自动暂停（Timer 的特性）
        // 但为了节省资源，我们可以显式处理
        LoggerService.shared.info(module: "AuthenticationService", message: "App 进入后台")
    }
    
    @objc private func appWillEnterForeground() {
        // App 回到前台时，重新验证 token 并刷新（如果需要）
        LoggerService.shared.info(module: "AuthenticationService", message: "App 回到前台")
        
        guard authenticationState == .authenticated else {
            return
        }
        
        Task {
            // 如果有 refresh_token，尝试刷新（因为可能已经过期）
            if refreshToken != nil {
                LoggerService.shared.info(module: "AuthenticationService", message: "App 回到前台，开始刷新 token")
                await refreshTokenIfNeeded()
            } else {
                // 没有 refresh_token，验证现有 token
                LoggerService.shared.info(module: "AuthenticationService", message: "App 回到前台，开始验证 token")
                await validateStoredTokens()
            }
        }
    }
    #endif
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
                return "网络错误：\(error.localizedDescription)"
            }
        }
        
        // 尝试解析 NetworkError
        let errorDescription = error.localizedDescription
        
        // 如果包含后端返回的具体错误信息，直接展示
        if errorDescription.contains("Apple 用户不存在") || errorDescription.contains("Apple ID") {
            return errorDescription
        }
        
        // HTTP 状态码错误
        if errorDescription.contains("401") {
            return "身份验证失败，请重新登录"
        } else if errorDescription.contains("403") {
            return "访问被拒绝，请联系客服"
        } else if errorDescription.contains("404") {
            return "Apple 账号未注册，请先在后台注册"
        } else if errorDescription.contains("500") || errorDescription.contains("502") || errorDescription.contains("503") {
            return "服务器繁忙，请稍后重试"
        }
        
        // 返回完整的错误描述，帮助调试
        return "登录失败：\(errorDescription)"
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
    let authenticatedAt: Date
    
    init(accessToken: String, isNewUser: Bool = false) {
        self.accessToken = accessToken
        self.isNewUser = isNewUser
        self.authenticatedAt = Date()
    }
}
