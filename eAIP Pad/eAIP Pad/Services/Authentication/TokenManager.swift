import Foundation

// MARK: - Token 管理器
class TokenManager {
    
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenRefreshTimer: Timer?
    private let tokenRefreshInterval: TimeInterval = 3600
    
    var currentAccessToken: String? { accessToken }
    var currentRefreshToken: String? { refreshToken }
    
    /// 设置 tokens
    func setTokens(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        
        do {
            try KeychainService.shared.save(key: KeychainService.Keys.accessToken, value: accessToken)
            try KeychainService.shared.save(key: KeychainService.Keys.refreshToken, value: refreshToken)
        } catch {
            LoggerService.shared.error(module: "TokenManager", 
                message: "保存 tokens 到 Keychain 失败: \(error.localizedDescription)")
        }
        
        NetworkService.shared.setTokens(accessToken: accessToken, refreshToken: refreshToken)
    }
    
    /// 更新 access token
    func updateAccessToken(_ newAccessToken: String, refreshToken newRefreshToken: String?) {
        self.accessToken = newAccessToken
        
        do {
            try KeychainService.shared.save(key: KeychainService.Keys.accessToken, value: newAccessToken)
            
            if let newRefreshToken = newRefreshToken {
                self.refreshToken = newRefreshToken
                try KeychainService.shared.save(key: KeychainService.Keys.refreshToken, value: newRefreshToken)
            }
        } catch {
            LoggerService.shared.error(module: "TokenManager", 
                message: "更新 tokens 到 Keychain 失败: \(error.localizedDescription)")
        }
    }
    
    /// 清除 tokens
    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        
        do {
            try KeychainService.shared.delete(key: KeychainService.Keys.accessToken)
        } catch {
            LoggerService.shared.debug(module: "TokenManager", 
                message: "删除 access token 失败: \(error.localizedDescription)")
        }
        
        do {
            try KeychainService.shared.delete(key: KeychainService.Keys.refreshToken)
        } catch {
            LoggerService.shared.debug(module: "TokenManager", 
                message: "删除 refresh token 失败: \(error.localizedDescription)")
        }
        
        NetworkService.shared.clearTokens()
    }
    
    /// 从 Keychain 加载 tokens
    func loadStoredTokens() -> (accessToken: String?, refreshToken: String?) {
        var storedAccessToken: String?
        var storedRefreshToken: String?
        
        do {
            storedAccessToken = try KeychainService.shared.load(key: KeychainService.Keys.accessToken)
        } catch {
            LoggerService.shared.debug(module: "TokenManager", 
                message: "加载 access token 失败: \(error.localizedDescription)")
        }
        
        do {
            storedRefreshToken = try KeychainService.shared.load(key: KeychainService.Keys.refreshToken)
        } catch {
            LoggerService.shared.debug(module: "TokenManager", 
                message: "加载 refresh token 失败: \(error.localizedDescription)")
        }
        
        self.accessToken = storedAccessToken
        self.refreshToken = storedRefreshToken
        
        return (storedAccessToken, storedRefreshToken)
    }
    
    /// 启动自动刷新定时器
    @MainActor
    func startTokenRefreshTimer(onRefresh: @escaping () async -> Void) {
        stopTokenRefreshTimer()
        
        guard refreshToken != nil else {
            return
        }
        
        tokenRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: tokenRefreshInterval, repeats: true
        ) { _ in
            Task { @MainActor in
                await onRefresh()
            }
        }
        
        if let timer = tokenRefreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    /// 停止自动刷新定时器
    @MainActor
    func stopTokenRefreshTimer() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
    }
}
