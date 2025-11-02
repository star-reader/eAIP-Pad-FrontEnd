import Foundation
import SwiftUI
import SwiftData
import StoreKit
import Combine

// 自定义订阅状态枚举
enum AppSubscriptionStatus: String, CaseIterable {
    case inactive = "inactive"
    case trial = "trial"
    case active = "active"
    case expired = "expired"
    
    var isValid: Bool {
        return self == .trial || self == .active
    }
    
    var displayName: String {
        switch self {
        case .trial: return "试用期"
        case .active: return "已订阅"
        case .expired: return "已过期"
        case .inactive: return "未订阅"
        }
    }
    
    init(from string: String?) {
        guard let string = string else {
            self = .inactive
            return
        }
        self = AppSubscriptionStatus(rawValue: string.lowercased()) ?? .inactive
    }
}

// MARK: - 订阅服务
@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    // 产品ID
    private let monthlyProductID = "com.usagijin.eaip.monthly"
    
    // 订阅状态
    @Published var subscriptionStatus: AppSubscriptionStatus = .inactive
    @Published var subscriptionEndDate: Date?
    @Published var daysLeft: Int = 0
    
    // StoreKit 产品
    @Published var monthlyProduct: Product?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var updateListenerTask: Task<Void, Error>?
    private let networkService = NetworkService.shared
    private let authService = AuthenticationService.shared
    
    private init() {
        // 启动时开始监听交易更新
        updateListenerTask = listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - 加载产品
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let products = try await Product.products(for: [monthlyProductID])
            monthlyProduct = products.first
            
            if monthlyProduct == nil {
                print("⚠️ 未找到产品: \(monthlyProductID)")
            }
        } catch {
            errorMessage = "加载产品失败: \(error.localizedDescription)"
            print("❌ 加载产品失败: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - 购买订阅
    func purchaseMonthlySubscription() async -> Bool {
        guard let product = monthlyProduct else {
            errorMessage = "产品未加载，请稍后再试"
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    // 交易验证成功，从 verificationResult 获取 JWS 字符串
                    let transactionJWS = verificationResult.jwsRepresentation
                    // 发送到服务器验证
                    let success = await verifyTransactionWithServer(transactionJWS: transactionJWS, transaction: transaction)
                    if success {
                        await transaction.finish()
                        // 更新订阅状态
                        await updateSubscriptionStatus()
                        isLoading = false
                        return true
                    } else {
                        await transaction.finish()
                        isLoading = false
                        return false
                    }
                case .unverified(_, let error):
                    errorMessage = "交易验证失败: \(error.localizedDescription)"
                    print("❌ 交易验证失败: \(error)")
                    isLoading = false
                    return false
                }
            case .userCancelled:
                errorMessage = "用户取消了购买"
                isLoading = false
                return false
            case .pending:
                errorMessage = "购买正在处理中，请稍候"
                isLoading = false
                return false
            @unknown default:
                errorMessage = "未知的购买结果"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "购买失败: \(error.localizedDescription)"
            print("❌ 购买失败: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - 验证交易（发送到服务器）
    private func verifyTransactionWithServer(transactionJWS: String, transaction: StoreKit.Transaction) async -> Bool {
        guard let appleUserId = authService.appleUserId else {
            errorMessage = "无法获取 Apple 用户 ID"
            return false
        }
        
        // 从 JWS 中提取环境信息
        let environment = extractEnvironment(from: transactionJWS)
        
        do {
            let response = try await networkService.verifyJWS(
                transactionJWS: transactionJWS,
                appleUserId: appleUserId,
                environment: environment
            )
            
            // 更新订阅状态
            updateStatus(from: response)
            
            if response.status == "success" {
                print("✅ 订阅验证成功")
                return true
            } else {
                errorMessage = response.message ?? "订阅验证失败"
                return false
            }
        } catch {
            errorMessage = "服务器验证失败: \(error.localizedDescription)"
            print("❌ 服务器验证失败: \(error)")
            return false
        }
    }
    
    // MARK: - 从 Transaction 获取 JWS 字符串
    nonisolated private func getJWSString(from transaction: StoreKit.Transaction) -> String {
        // transaction.jsonRepresentation 返回的是 JWS 令牌的 Data（字节表示）
        let jsonData = transaction.jsonRepresentation
        // 将 Data 转换为字符串
        return String(data: jsonData, encoding: .utf8) ?? ""
    }
    
    // MARK: - 从 JWS 中提取环境信息
    private func extractEnvironment(from jws: String) -> String? {
        // JWS 格式: header.payload.signature
        let parts = jws.split(separator: ".")
        guard parts.count >= 2 else {
            // 如果无法解析，返回基于编译配置的默认值
            #if DEBUG
            return "Sandbox"
            #else
            return "Production"
            #endif
        }
        
        // 解码 payload (base64url)
        let payloadString = String(parts[1])
        let base64 = payloadString.base64URLDecoded
        
        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let environment = payload["environment"] as? String else {
            // 如果无法解析，返回基于编译配置的默认值
            #if DEBUG
            return "Sandbox"
            #else
            return "Production"
            #endif
        }
        
        return normalizeEnvironment(environment)
    }
    
    // MARK: - 标准化环境字符串
    private func normalizeEnvironment(_ environment: String) -> String {
        switch environment.lowercased() {
        case "production":
            return "Production"
        case "sandbox":
            return "Sandbox"
        case "xcode":  // Xcode 测试环境通常对应 Sandbox
            return "Sandbox"
        default:
            return environment.capitalized
        }
    }
    
    // MARK: - 同步订阅状态（App 启动时调用）
    func syncSubscriptionStatus() async {
        guard let appleUserId = authService.appleUserId else {
            print("⚠️ 无法获取 Apple 用户 ID，跳过同步")
            return
        }
        
        isLoading = true
        
        do {
            // 获取当前有效的交易
            var jwsList: [String] = []
            for await result in Transaction.currentEntitlements {
                switch result {
                case .verified(let transaction):
                    // 从 transaction.jsonRepresentation 获取 JWS 字符串
                    let jws = getJWSString(from: transaction)
                    jwsList.append(jws)
                case .unverified:
                    continue
                }
            }
            
            if jwsList.isEmpty {
                // 没有本地交易，直接查询服务器状态
                await querySubscriptionStatus()
            } else {
                // 批量同步交易
                let environment = extractEnvironment(from: jwsList.first ?? "")
                let response = try await networkService.syncSubscriptions(
                    transactionJWSList: jwsList,
                    appleUserId: appleUserId,
                    environment: environment
                )
                
                updateStatus(from: response)
                
                if response.status == "success" {
                    print("✅ 订阅同步成功，状态: \(subscriptionStatus.rawValue)")
                } else {
                    print("⚠️ 订阅同步失败: \(response.message ?? "未知错误")")
                    // 同步失败时，尝试查询状态
                    await querySubscriptionStatus()
                }
            }
        } catch {
            print("❌ 同步订阅失败: \(error)")
            // 同步失败时，尝试查询状态
            await querySubscriptionStatus()
        }
        
        isLoading = false
    }
    
    // MARK: - 查询订阅状态
    func querySubscriptionStatus() async {
        guard let appleUserId = authService.appleUserId else {
            return
        }
        
        do {
            let response = try await networkService.getSubscriptionStatus(appleUserId: appleUserId)
            updateStatus(from: response)
            print("✅ 查询订阅状态成功，状态: \(subscriptionStatus.rawValue)")
        } catch {
            print("❌ 查询订阅状态失败: \(error)")
        }
    }
    
    // MARK: - 更新订阅状态（从响应）
    private func updateStatus(from response: VerifyJWSResponse) {
        subscriptionStatus = AppSubscriptionStatus(from: response.subscriptionStatus)
        
        if let endDateString = response.subscriptionEndDate {
            let formatter = ISO8601DateFormatter()
            subscriptionEndDate = formatter.date(from: endDateString)
            updateDaysLeft()
        }
    }
    
    private func updateStatus(from response: SyncSubscriptionResponse) {
        subscriptionStatus = AppSubscriptionStatus(from: response.subscriptionStatus)
        
        if let endDateString = response.subscriptionEndDate {
            let formatter = ISO8601DateFormatter()
            subscriptionEndDate = formatter.date(from: endDateString)
            updateDaysLeft()
        }
    }
    
    private func updateStatus(from response: SubscriptionStatusResponse) {
        subscriptionStatus = AppSubscriptionStatus(from: response.status)
        
        if let endDateString = response.subscriptionEndDate {
            let formatter = ISO8601DateFormatter()
            subscriptionEndDate = formatter.date(from: endDateString)
        }
        
        if let days = response.daysLeft {
            daysLeft = days
        } else {
            updateDaysLeft()
        }
    }
    
    // MARK: - 更新剩余天数
    private func updateDaysLeft() {
        guard let endDate = subscriptionEndDate else {
            daysLeft = 0
            return
        }
        
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        daysLeft = max(0, days)
    }
    
    // MARK: - 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            guard let self = self else { return }
            
            for await result in Transaction.updates {
                let transaction: StoreKit.Transaction
                switch result {
                case .verified(let verifiedTransaction):
                    transaction = verifiedTransaction
                case .unverified(_, let error):
                    print("❌ 交易验证失败: \(error)")
                    continue
                }
                
                // 验证并更新状态
                let transactionJWS = self.getJWSString(from: transaction)
                let success = await self.verifyTransactionWithServer(transactionJWS: transactionJWS, transaction: transaction)
                if success {
                    // 完成交易
                    await transaction.finish()
                    
                    // 更新订阅状态
                    await self.updateSubscriptionStatus()
                }
            }
        }
    }
    
    // MARK: - 更新订阅状态（从服务器）
    private func updateSubscriptionStatus() async {
        await querySubscriptionStatus()
    }
    
    // MARK: - 恢复购买
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            // 同步订阅状态
            await syncSubscriptionStatus()
            print("✅ 恢复购买成功")
        } catch {
            errorMessage = "恢复购买失败: \(error.localizedDescription)"
            print("❌ 恢复购买失败: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - 计算属性
    var hasValidSubscription: Bool {
        return subscriptionStatus.isValid
    }
    
    var subscriptionDescription: String {
        switch subscriptionStatus {
        case .active:
            if daysLeft > 0 {
                return "已订阅 - 剩余 \(daysLeft) 天"
            } else {
                return "已订阅"
            }
        case .trial:
            if daysLeft > 0 {
                return "试用期 - 剩余 \(daysLeft) 天"
            } else {
                return "试用期"
            }
        case .expired:
            return "订阅已过期"
        case .inactive:
            return "未订阅"
        }
    }
}

// MARK: - String 扩展（Base64URL 解码）
extension String {
    var base64URLDecoded: String {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // 添加填充
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        
        return base64
    }
}