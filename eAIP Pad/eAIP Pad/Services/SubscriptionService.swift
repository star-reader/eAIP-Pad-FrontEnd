import Foundation
import SwiftUI
import SwiftData
import StoreKit
import Combine

typealias AppStoreTransaction = StoreKit.Transaction

// 自定义订阅状态枚举，避免与StoreKit冲突
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
}

// MARK: - 订阅服务
@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    // 产品ID - 修正为正确的订阅ID
    private let monthlyProductID = "com.usagijin.eaip.monthly"
    
    // 订阅状态
    @Published var subscriptionStatus: AppSubscriptionStatus = .inactive
    @Published var isTrialActive = false
    @Published var subscriptionEndDate: Date?
    @Published var trialEndDate: Date?
    @Published var daysLeft: Int = 0
    
    // StoreKit 产品
    @Published var monthlyProduct: Product?
    @Published var availableProducts: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // StoreKit 2 订阅状态
    @Published var currentSubscription: Product.SubscriptionInfo.Status?
    
    // 计算属性
    var hasValidSubscription: Bool {
        return subscriptionStatus.isValid || isTrialActive
    }
    
    var subscriptionDescription: String {
        if isTrialActive {
            if daysLeft > 0 {
                return "试用期 - 剩余 \(daysLeft) 天"
            } else {
                return "试用期"
            }
        } else {
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
    
    private var updateListenerTask: Task<Void, Error>?
    
    private init() {
        // 启动时监听交易更新
        updateListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - 加载产品
    func loadProducts() async {
        print("🔄 开始加载产品: \(monthlyProductID)")
        do {
            let products = try await Product.products(for: [monthlyProductID])
            self.availableProducts = products
            self.monthlyProduct = products.first
            
            if let product = products.first {
                print("✅ 成功加载产品: \(product.displayName) - \(product.displayPrice)")
                print("   产品ID: \(product.id)")
                print("   产品类型: \(product.type)")
                self.errorMessage = nil // 清除之前的错误
            } else {
                print("⚠️ 未找到产品: \(monthlyProductID)")
                print("   返回的产品列表为空")
                self.errorMessage = "未找到订阅产品，请检查App Store配置"
            }
        } catch {
            print("❌ 加载产品失败: \(error.localizedDescription)")
            print("   错误详情: \(error)")
            if let storeKitError = error as? StoreKitError {
                print("   StoreKit错误: \(storeKitError)")
            }
            self.errorMessage = "加载产品失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 购买月度订阅
    func purchaseMonthlySubscription() async -> Bool {
        // 如果产品未加载，先尝试加载
        if monthlyProduct == nil {
            print("⚠️ 产品未加载，尝试重新加载...")
            await loadProducts()
            
            // 再次检查产品是否已加载
            guard monthlyProduct != nil else {
                let errorMsg = self.errorMessage ?? "产品不可用，请稍后重试"
                self.errorMessage = errorMsg
                print("❌ 产品加载失败: \(errorMsg)")
                return false
            }
            
            print("✅ 产品加载成功，继续购买流程")
        }
        
        guard let product = monthlyProduct else {
            self.errorMessage = "产品不可用，请稍后重试"
            return false
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            // 购买产品
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // 验证交易
                let transaction = try checkVerified(verification)
                print("✅ 购买成功: \(transaction.productID)")
                
                // 将收据发送到后端验证（如果后端需要）
                await syncPurchaseWithBackend(transaction: transaction)
                
                // 完成交易
                await transaction.finish()
                
                // 更新订阅状态
                await updateSubscriptionStatus()
                
                self.isLoading = false
                return true
                
            case .userCancelled:
                print("ℹ️ 用户取消购买")
                self.errorMessage = "已取消购买"
                self.isLoading = false
                return false
                
            case .pending:
                print("⏳ 购买待处理（需要家长同意）")
                self.errorMessage = "购买正在等待批准，请稍候"
                self.isLoading = false
                return false
                
            @unknown default:
                print("⚠️ 未知的购买结果")
                self.isLoading = false
                return false
            }
        } catch StoreKitError.userCancelled {
            print("ℹ️ 用户取消购买")
            self.errorMessage = "已取消购买"
            self.isLoading = false
            return false
        } catch {
            print("❌ 购买失败: \(error.localizedDescription)")
            
            // 提供更友好的错误信息
            if error.localizedDescription.contains("network") || error.localizedDescription.contains("Network") {
                self.errorMessage = "网络连接失败，请检查网络后重试"
            } else if error.localizedDescription.contains("No active account") || error.localizedDescription.contains("not signed in") {
                self.errorMessage = "请先在设置中登录 Apple ID"
            } else {
                self.errorMessage = "购买失败，请稍后重试"
            }
            self.isLoading = false
            return false
        }
    }
    
    // MARK: - 恢复购买
    func restorePurchases() async {
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            // StoreKit 2: 同步购买记录
            try await AppStore.sync()
            print("✅ 购买记录已同步")
            
            // 更新订阅状态
            await updateSubscriptionStatus()
            
            // 检查是否有活跃订阅
            if subscriptionStatus.isValid {
                self.errorMessage = nil
            } else {
                self.errorMessage = "未找到可恢复的订阅"
            }
        } catch {
            print("❌ 恢复购买失败: \(error.localizedDescription)")
            
            if error.localizedDescription.contains("No active account") || error.localizedDescription.contains("not signed in") {
                self.errorMessage = "请先在设置中登录 Apple ID"
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("Network") {
                self.errorMessage = "网络连接失败，请检查网络后重试"
            } else {
                self.errorMessage = "未找到可恢复的购买记录"
            }
        }
        
        self.isLoading = false
    }
    
    // MARK: - 开始试用（后端）
    func startTrial() async -> Bool {
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            // 确保用户已登录
            guard AuthenticationService.shared.currentUser != nil else {
                self.errorMessage = "用户未登录"
                self.isLoading = false
                return false
            }
            
            // 调用后端开始试用
            let response = try await NetworkService.shared.startTrial()
            print("✅ 试用开始成功: \(response)")
            
            // 更新本地订阅状态
            await updateSubscriptionStatusFromBackend()
            
            self.isLoading = false
            return true
        } catch {
            print("❌ 开始试用失败: \(error)")
            
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("❌ 缺少键: \(key.stringValue), 上下文: \(context.debugDescription)")
                    self.errorMessage = "服务器响应格式错误"
                case .typeMismatch(let type, let context):
                    print("❌ 类型不匹配: \(type), 上下文: \(context.debugDescription)")
                    self.errorMessage = "服务器响应格式错误"
                case .valueNotFound(let type, let context):
                    print("❌ 值未找到: \(type), 上下文: \(context.debugDescription)")
                    self.errorMessage = "服务器响应格式错误"
                case .dataCorrupted(let context):
                    print("❌ 数据损坏: \(context.debugDescription)")
                    self.errorMessage = "服务器响应数据损坏"
                @unknown default:
                    self.errorMessage = "未知的解析错误"
                }
            } else {
                self.errorMessage = "开始试用失败: \(error.localizedDescription)"
            }
            
            self.isLoading = false
            return false
        }
    }
    
    // MARK: - 更新订阅状态
    func updateSubscriptionStatus() async {
        // 1. 首先检查 StoreKit 的订阅状态
        await checkStoreKitSubscription()
        
        // 2. 然后从后端同步状态
        await updateSubscriptionStatusFromBackend()
    }
    
    // MARK: - 检查 StoreKit 订阅状态
    private func checkStoreKitSubscription() async {
        guard let product = monthlyProduct else {
            print("⚠️ 产品未加载")
            return
        }
        
        do {
            // 获取当前订阅状态
            let statuses = try await product.subscription?.status ?? []
            
            // 查找活跃的订阅
            for status in statuses {
                switch status.state {
                case .subscribed:
                    print("✅ 订阅活跃")
                    let transaction = try checkVerified(status.transaction)
                    
                    // 获取续费信息
                    if let _ = try? checkVerified(status.renewalInfo) {
                        self.currentSubscription = status
                        
                        // 计算到期日期
                        if let expirationDate = transaction.expirationDate {
                            self.subscriptionEndDate = expirationDate
                            let calendar = Calendar.current
                            let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
                            self.daysLeft = max(0, components.day ?? 0)
                        }
                        
                        // 如果后端状态不是 active，同步到后端
                        if self.subscriptionStatus != .active {
                            await syncPurchaseWithBackend(transaction: transaction)
                        }
                    }
                    return
                    
                case .expired, .revoked:
                    print("ℹ️ 订阅已过期或被撤销")
                    self.currentSubscription = nil
                    
                case .inBillingRetryPeriod:
                    print("⚠️ 订阅在账单重试期")
                    // 仍然允许访问
                    self.currentSubscription = status
                    
                case .inGracePeriod:
                    print("ℹ️ 订阅在宽限期")
                    // 仍然允许访问
                    self.currentSubscription = status
                    
                default:
                    print("⚠️ 未知订阅状态")
                }
            }
        } catch {
            print("❌ 检查订阅状态失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 从后端更新订阅状态
    private func updateSubscriptionStatusFromBackend() async {
        do {
            let response = try await NetworkService.shared.getSubscriptionStatus()
            
            // 解析订阅状态
            if let status = AppSubscriptionStatus(rawValue: response.status) {
                self.subscriptionStatus = status
            }
            
            // 解析试用状态
            self.isTrialActive = response.isTrial
            
            // 解析到期时间
            if let subscriptionEndString = response.subscriptionEnd {
                let dateFormatter = ISO8601DateFormatter()
                if let endDate = dateFormatter.date(from: subscriptionEndString) {
                    self.subscriptionEndDate = endDate
                    
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.day], from: Date(), to: endDate)
                    self.daysLeft = max(0, components.day ?? 0)
                }
            }
            
            // 如果后端返回了剩余天数，直接使用
            if let daysLeftFromServer = response.daysLeft {
                self.daysLeft = daysLeftFromServer
            }
            
            print("✅ 后端订阅状态: \(subscriptionStatus.rawValue), 试用: \(isTrialActive), 剩余天数: \(daysLeft)")
        } catch {
            print("❌ 从后端更新订阅状态失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 将购买同步到后端
    private func syncPurchaseWithBackend(transaction: AppStoreTransaction) async {
        do {
            print("🔄 同步购买到后端: \(transaction.productID)")
            
            // 获取环境信息（Production 或 Sandbox）
            let environment: String
            #if DEBUG
            environment = "Sandbox"
            #else
            environment = "Production"
            #endif
            
            // 格式化日期为 ISO 8601（不带小数秒，匹配后端格式）
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            
            let purchaseDate = dateFormatter.string(from: transaction.purchaseDate)
            let expiresDate = transaction.expirationDate.map { dateFormatter.string(from: $0) }
            
            // 获取 originalTransactionId（用于订阅，通常是第一次购买的交易ID）
            // StoreKit 2 中，originalID 是 UInt64 类型，如果是首次购买，originalID 和 id 相同
            let originalTransactionId = String(transaction.originalID)
            
            // 构造验证请求
            let verificationRequest = SubscriptionVerificationRequest(
                transactionId: String(transaction.id),
                originalTransactionId: originalTransactionId,
                productId: transaction.productID,
                purchaseDate: purchaseDate,
                expiresDate: expiresDate,
                environment: environment
            )
            
            // 调用后端验证接口
            let response = try await NetworkService.shared.verifySubscription(request: verificationRequest)
            print("✅ 订阅验证成功: status=\(response.status), daysLeft=\(response.daysLeft ?? 0)")
            
            // 更新本地状态
            if let status = AppSubscriptionStatus(rawValue: response.status) {
                self.subscriptionStatus = status
            }
            self.isTrialActive = response.isTrial
            
            // 更新到期日期
            if let subscriptionEndString = response.subscriptionEnd {
                let dateFormatter = ISO8601DateFormatter()
                if let endDate = dateFormatter.date(from: subscriptionEndString) {
                    self.subscriptionEndDate = endDate
                    
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.day], from: Date(), to: endDate)
                    self.daysLeft = max(0, components.day ?? 0)
                }
            }
            
            // 如果后端返回了剩余天数，直接使用
            if let daysLeftFromServer = response.daysLeft {
                self.daysLeft = daysLeftFromServer
            }
            
        } catch {
            print("❌ 同步购买到后端失败: \(error.localizedDescription)")
            // 即使验证失败，也尝试从后端获取最新状态
            await updateSubscriptionStatusFromBackend()
        }
    }
    
    // MARK: - 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            guard let self = self else { return }
            // 监听交易更新
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try self.verifyTransaction(result)
                    print("🔔 收到交易更新: \(transaction.productID)")
                    
                    // 同步到后端
                    await self.syncPurchaseWithBackend(transaction: transaction)
                    
                    // 更新订阅状态
                    await self.updateSubscriptionStatus()
                    
                    // 完成交易
                    await transaction.finish()
                } catch {
                    print("❌ 处理交易更新失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - 验证交易
    @MainActor
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            print("❌ 交易未验证: \(error)")
            throw error
        case .verified(let verifiedTransaction):
            return verifiedTransaction
        }
    }
    
    // 非 MainActor 版本的验证方法
    nonisolated private func verifyTransaction<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            print("❌ 交易未验证: \(error)")
            throw error
        case .verified(let verifiedTransaction):
            return verifiedTransaction
        }
    }
    
    // MARK: - 管理订阅（跳转到系统设置）
    func manageSubscription() async {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            do {
                try await AppStore.showManageSubscriptions(in: windowScene)
            } catch {
                print("❌ 打开订阅管理失败: \(error.localizedDescription)")
            }
        }
    }
}
