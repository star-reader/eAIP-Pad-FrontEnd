import AuthenticationServices
import Combine
import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

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
    private let tokenRefreshInterval: TimeInterval = 3600

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
        // 从 Keychain 检查存储的 token
        let storedAccessToken = try? KeychainService.shared.load(key: KeychainService.Keys.accessToken)
        let storedRefreshToken = try? KeychainService.shared.load(key: KeychainService.Keys.refreshToken)
        self.appleUserId = try? KeychainService.shared.load(key: KeychainService.Keys.appleUserId)

        guard let storedAccessToken = storedAccessToken else {
            LoggerService.shared.info(module: "AuthenticationService", message: "未找到存储的凭据")
            return
        }

        self.accessToken = storedAccessToken
        self.refreshToken = storedRefreshToken

        // 立即设置为已认证状态，避免闪现登录页面
        self.authenticationState = .authenticated
        self.currentUser = AuthenticatedUser(accessToken: storedAccessToken)
        // 使用脱敏后的信息记录日志
        let maskedUserId = appleUserId?.maskedAppleUserId ?? "未知"
        LoggerService.shared.info(
            module: "AuthenticationService",
            message: "找到存储的凭据，设置为已认证状态，userId: \(maskedUserId)")
        NetworkService.shared.setTokens(
            accessToken: storedAccessToken, refreshToken: storedRefreshToken ?? "")

        // 如果有 refresh_token，启动时直接尝试刷新 token（因为 access_token 可能已过期）
        // 如果没有 refresh_token，验证现有的 access_token 是否有效
        Task {
            if storedRefreshToken != nil {
                // 有 refresh_token，直接尝试刷新
                LoggerService.shared.info(
                    module: "AuthenticationService", message: "有 refresh_token，尝试刷新")
                await refreshTokenIfNeeded()
            } else {
                // 没有 refresh_token，验证现有的 access_token
                LoggerService.shared.info(
                    module: "AuthenticationService", message: "无 refresh_token，验证现有 token")
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
                        try? KeychainService.shared.save(key: KeychainService.Keys.refreshToken, value: newRefreshToken)
                    }
                    try? KeychainService.shared.save(key: KeychainService.Keys.accessToken, value: newAccessToken)
                    self.authenticationState = .authenticated
                    self.currentUser = AuthenticatedUser(accessToken: newAccessToken)

                    // 启动自动刷新定时器
                    self.startTokenRefreshTimer()
                }
                LoggerService.shared.info(module: "AuthenticationService", message: "Token 刷新成功")
                return
            }
        } catch {
            // 刷新失败，尝试验证现有的 access_token
            LoggerService.shared.warning(
                module: "AuthenticationService",
                message: "Token 刷新失败，尝试验证现有 token: \(error.localizedDescription)")
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
            LoggerService.shared.warning(
                module: "AuthenticationService", message: "无 access_token，设置为未认证")
            return
        }

        // 设置网络服务的 token
        NetworkService.shared.setTokens(accessToken: accessToken, refreshToken: refreshToken ?? "")

        do {
            // 通过调用需要认证的 API 来验证 token 是否有效
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
                        // 更新 refresh token
                        let newRefreshToken = NetworkService.shared.getCurrentRefreshToken()
                        await MainActor.run {
                            self.accessToken = newAccessToken
                            if let newRefreshToken = newRefreshToken {
                                self.refreshToken = newRefreshToken
                                try? KeychainService.shared.save(key: KeychainService.Keys.refreshToken, value: newRefreshToken)
                            }
                            try? KeychainService.shared.save(key: KeychainService.Keys.accessToken, value: newAccessToken)
                            self.authenticationState = .authenticated
                            self.currentUser = AuthenticatedUser(accessToken: newAccessToken)
                            self.startTokenRefreshTimer()
                        }
                        LoggerService.shared.info(
                            module: "AuthenticationService", message: "Token 验证失败后刷新成功")
                        return
                    }
                } catch {
                    // 刷新也失败，清除凭据
                    LoggerService.shared.error(
                        module: "AuthenticationService",
                        message: "Token 刷新失败: \(error.localizedDescription)")
                }
            }

            // Token 无效且无法刷新，清除存储的凭据
            await MainActor.run {
                self.clearStoredCredentials()
                self.authenticationState = .notAuthenticated
            }
            LoggerService.shared.warning(
                module: "AuthenticationService", message: "Token 无效且无法刷新，已清除凭据")
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
            let tokenString = String(data: identityToken, encoding: .utf8)
        else {
            await MainActor.run {
                self.authenticationState = .error("无法获取身份令牌")
            }
            LoggerService.shared.error(module: "AuthenticationService", message: "无法获取 Apple 身份令牌")
            return
        }

        // 获取 Apple 用户 ID（唯一标识符）
        let appleUserId = credential.user
        LoggerService.shared.info(module: "AuthenticationService", message: "获取到 Apple 用户 ID: \(appleUserId.maskedAppleUserId)")

        do {
            // 调用后端 Apple 登录接口
            let response = try await NetworkService.shared.appleLogin(idToken: tokenString)
            LoggerService.shared.info(module: "AuthenticationService", message: "后端登录接口调用成功")

            await MainActor.run {
                // 存储 tokens
                self.accessToken = response.accessToken
                self.refreshToken = response.refreshToken
                self.isNewUser = response.isNewUser
                self.appleUserId = appleUserId

                // 保存到 Keychain（安全存储）
                try? KeychainService.shared.save(key: KeychainService.Keys.accessToken, value: response.accessToken)
                try? KeychainService.shared.save(key: KeychainService.Keys.refreshToken, value: response.refreshToken)
                try? KeychainService.shared.save(key: KeychainService.Keys.appleUserId, value: appleUserId)
                
                // 非敏感信息可以存储在 UserDefaults
                UserDefaults.standard.set(response.isNewUser, forKey: "is_new_user")
                
                LoggerService.shared.info(module: "AuthenticationService", message: "已保存登录凭据到 Keychain")

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
                let errorMessage = AuthenticationErrorHandler.friendlyBackendErrorMessage(from: error)
                self.authenticationState = .error(errorMessage)
            }
            LoggerService.shared.error(
                module: "AuthenticationService",
                message: "Apple 登录失败: \(error.localizedDescription)")
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

        // 从 Keychain 删除敏感信息
        try? KeychainService.shared.delete(key: KeychainService.Keys.accessToken)
        try? KeychainService.shared.delete(key: KeychainService.Keys.refreshToken)
        try? KeychainService.shared.delete(key: KeychainService.Keys.appleUserId)
        
        // 从 UserDefaults 删除非敏感信息
        UserDefaults.standard.removeObject(forKey: "is_new_user")
        
        LoggerService.shared.info(module: "AuthenticationService", message: "已清除所有存储的凭据")
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
        stopTokenRefreshTimer()  // 先停止现有的定时器

        guard refreshToken != nil else {
            return
        }

        // 在主线程上创建定时器
        tokenRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: tokenRefreshInterval, repeats: true
        ) { [weak self] _ in
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
            LoggerService.shared.warning(
                module: "AuthenticationService",
                message: "Token 自动刷新失败: \(error.localizedDescription)")
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
            LoggerService.shared.info(module: "AuthenticationService", message: "App 进入后台")
        }

        @objc private func appWillEnterForeground() {
            LoggerService.shared.info(module: "AuthenticationService", message: "App 回到前台")

            guard authenticationState == .authenticated else {
                return
            }

            Task {
                if refreshToken != nil {
                    LoggerService.shared.info(
                        module: "AuthenticationService", message: "App 回到前台，开始刷新 token")
                    await refreshTokenIfNeeded()
                } else {
                    LoggerService.shared.info(
                        module: "AuthenticationService", message: "App 回到前台，开始验证 token")
                    await validateStoredTokens()
                }
            }
        }
    #endif
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthenticationService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            Task {
                await handleAppleSignInSuccess(credential: appleIDCredential)
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
        Task {
            await MainActor.run {
                let errorMessage = AuthenticationErrorHandler.friendlyErrorMessage(from: error)
                self.authenticationState = .error(errorMessage)
            }
        }
    }
}

extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first
            else {
                fatalError("无法获取窗口")
            }
            return window
        #else
            fatalError("UIKit 不可用")
        #endif
    }
}
