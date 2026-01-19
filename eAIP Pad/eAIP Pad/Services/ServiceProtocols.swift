import Foundation
import Combine

// MARK: - 服务协议定义
// 这些协议为依赖注入提供抽象层，提高代码的可测试性和可维护性

// MARK: - 网络服务协议
protocol NetworkServiceProtocol {
    // 认证相关
    func appleLogin(idToken: String) async throws -> AuthResponse
    func refreshAccessToken() async throws
    
    // 订阅相关
    func verifyJWS(transactionJWS: String, appleUserId: String, environment: String?) async throws -> VerifyJWSResponse
    func syncSubscriptions(transactionJWSList: [String], appleUserId: String, environment: String?) async throws -> SyncSubscriptionResponse
    func getSubscriptionStatus(appleUserId: String) async throws -> SubscriptionStatusResponse
    
    // AIRAC 相关
    func getCurrentAIRAC() async throws -> AIRACVersion
    
    // Token 管理
    func setTokens(accessToken: String, refreshToken: String)
    func clearTokens()
    func getCurrentAccessToken() -> String?
    func getCurrentRefreshToken() -> String?
    func cancelAllRequests()
}

// MARK: - 认证服务协议
protocol AuthenticationServiceProtocol: ObservableObject {
    var authenticationState: AuthenticationState { get }
    var currentUser: AuthenticatedUser? { get }
    var isAuthenticated: Bool { get }
    var errorMessage: String? { get }
    
    func signInWithApple() async
    func signOut()
}

// MARK: - 订阅服务协议
protocol SubscriptionServiceProtocol: ObservableObject {
    var subscriptionStatus: AppSubscriptionStatus { get }
    var monthlyProduct: Product? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    var hasValidSubscription: Bool { get }
    var hasUsedTrial: Bool { get }
    var subscriptionDescription: String { get }
    
    func loadProducts() async
    func purchaseMonthlySubscription() async -> Bool
    func syncSubscriptionStatus() async
    func querySubscriptionStatus() async
    func restorePurchases() async
}

// MARK: - Keychain 服务协议
protocol KeychainServiceProtocol {
    func save(key: String, value: String) throws
    func save(key: String, data: Data) throws
    func load(key: String) throws -> String
    func loadData(key: String) throws -> Data
    func delete(key: String) throws
    func update(key: String, value: String) throws
    func update(key: String, data: Data) throws
    func exists(key: String) -> Bool
    func clearAll() throws
}

// MARK: - 日志服务协议
protocol LoggerServiceProtocol {
    func log(type: LogType, module: String, message: String)
    func debug(module: String, message: String)
    func info(module: String, message: String)
    func warning(module: String, message: String)
    func error(module: String, message: String)
    func exportAsString() -> String
    func exportAsFile() -> URL?
    func clearLogs()
}

// MARK: - Token 管理器协议
protocol TokenManagerProtocol {
    var currentAccessToken: String? { get }
    var currentRefreshToken: String? { get }
    
    func setTokens(accessToken: String, refreshToken: String)
    func updateAccessToken(_ newAccessToken: String, refreshToken newRefreshToken: String?)
    func clearTokens()
    func loadStoredTokens() -> (accessToken: String?, refreshToken: String?)
    func startTokenRefreshTimer(onRefresh: @escaping () async -> Void)
    func stopTokenRefreshTimer()
}
