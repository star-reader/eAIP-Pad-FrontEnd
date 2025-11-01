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
    
    // 产品ID - 只支持自动续费订阅
    private let monthlyProductID = "com.usagijin.eaip.monthly" // 自动续费订阅
    
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
            let productIDs = [monthlyProductID]
            let products = try await Product.products(for: productIDs)
            self.availableProducts = products
            
            // 找到自动续费订阅产品
            self.monthlyProduct = products.first { $0.id == monthlyProductID }
            
            if let product = self.monthlyProduct {
                print("✅ 成功加载产品: \(product.displayName) - \(product.displayPrice)")
                print("   产品ID: \(product.id)")
                print("   产品类型: \(product.type)")
                
                // 检查是否有试用期优惠
                if let subscription = product.subscription, let introOffer = subscription.introductoryOffer {
                    print("   ✅ 包含试用期优惠: \(introOffer)")
                }
            } else {
                print("⚠️ 未找到产品")
                print("   返回的产品列表为空")
                self.errorMessage = "未找到订阅产品，请检查App Store配置"
            }
            
            if self.monthlyProduct != nil {
                self.errorMessage = nil // 清除之前的错误
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
    
    // MARK: - 购买月度订阅（包含试用期）
    func purchaseMonthlySubscription() async -> Bool {
        // 获取自动续费订阅产品
        guard let product = monthlyProduct else {
            // 如果产品未加载，先尝试加载
            print("⚠️ 产品未加载，尝试重新加载...")
            await loadProducts()
            
            guard let loadedProduct = monthlyProduct else {
                let errorMsg = self.errorMessage ?? "产品不可用，请稍后重试"
                self.errorMessage = errorMsg
                print("❌ 产品加载失败: \(errorMsg)")
                return false
            }
            
            print("✅ 产品加载成功，继续购买流程: \(loadedProduct.id)")
            return await performPurchase(product: loadedProduct)
        }
        
        return await performPurchase(product: product)
    }
    
    // MARK: - 执行购买
    private func performPurchase(product: Product) async -> Bool {
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
                
                // 验证收据到后端（Apple 要求必须验证收据）
                await verifyTransactionReceipt(transaction: transaction)
                
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
    
    // MARK: - 开始试用（通过 StoreKit 购买，试用期是 Subscription 的一部分）
    func startTrial() async -> Bool {
        // 试用期必须通过 StoreKit 的自动续费订阅来实现
        // Apple 要求试用期必须是 Subscription 的一部分，不能绕过 StoreKit
        // 直接调用购买方法，StoreKit 会自动处理试用期
        print("🔄 开始试用（通过 StoreKit 订阅）...")
        return await purchaseMonthlySubscription()
    }
    
    // MARK: - 更新订阅状态（App 启动时调用，必须验证收据）
    func updateSubscriptionStatus() async {
        // 1. 首先验证收据（Apple 要求必须验证收据，不能只依赖本地数据库）
        await verifyReceiptsOnLaunch()
        
        // 2. 然后检查 StoreKit 的订阅状态（用于更新本地 UI）
        await checkStoreKitSubscription()
        
        // 3. 最后从后端同步状态（作为备用验证）
        await updateSubscriptionStatusFromBackend()
    }
    
    // MARK: - 验证收据（App 启动时调用）
    private func verifyReceiptsOnLaunch() async {
        // Apple 要求必须验证收据，不能完全依赖自己的数据库
        // 获取所有当前订阅的交易并发送到后端验证
        
        guard AuthenticationService.shared.authenticationState == .authenticated else {
            print("⚠️ 用户未登录，跳过收据验证")
            return
        }
        
        print("🔄 开始验证收据（App 启动时）...")
        
        // StoreKit 2: 获取所有当前订阅的交易
        var allTransactions: [AppStoreTransaction] = []
        
        // 遍历所有当前订阅（currentEntitlements 只返回活跃的订阅交易）
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                // currentEntitlements 只返回订阅交易，所以直接收集
                allTransactions.append(transaction)
                print("📦 找到订阅交易: \(transaction.productID), ID: \(transaction.id)")
            } catch {
                print("⚠️ 交易验证失败: \(error)")
            }
        }
        
        if allTransactions.isEmpty {
            print("ℹ️ 未找到订阅交易，可能未订阅")
            // 如果没有订阅，也要通知后端（清除可能存在的过期订阅）
            await verifyNoSubscription()
            return
        }
        
        // 获取最新的订阅交易（通常是最近购买的）
        guard let latestTransaction = allTransactions.max(by: { $0.purchaseDate < $1.purchaseDate }) else {
            print("⚠️ 无法确定最新交易")
            return
        }
        
        print("✅ 找到最新订阅交易: \(latestTransaction.productID)")
        
        // 验证收据：发送交易签名到后端
        await verifyTransactionReceipt(transaction: latestTransaction)
    }
    
    // MARK: - 验证交易收据（发送签名到后端）
    private func verifyTransactionReceipt(transaction: AppStoreTransaction) async {
        do {
            // StoreKit 2: 获取交易的 JWS 签名（这是收据的一部分）
            // 注意：StoreKit 2 的交易已经验证过，但我们仍需要发送到后端进行额外验证
            
            // 获取环境信息
            let environment: String
            #if DEBUG
            environment = "Sandbox"
            #else
            environment = "Production"
            #endif
            
            // 格式化日期
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            
            let purchaseDate = dateFormatter.string(from: transaction.purchaseDate)
            let expiresDate = transaction.expirationDate.map { dateFormatter.string(from: $0) }
            
            // 构造验证请求（包含交易ID和相关信息）
            let verificationRequest = SubscriptionVerificationRequest(
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID),
                productId: transaction.productID,
                purchaseDate: purchaseDate,
                expiresDate: expiresDate,
                environment: environment
            )
            
            print("🔄 发送收据验证到后端: \(transaction.productID)")
            
            // 调用后端验证接口
            let response = try await NetworkService.shared.verifySubscription(request: verificationRequest)
            print("✅ 收据验证成功: status=\(response.status), daysLeft=\(response.daysLeft ?? 0)")
            
            // 更新本地状态（以服务器验证结果为准）
            if let status = AppSubscriptionStatus(rawValue: response.status) {
                self.subscriptionStatus = status
            }
            self.isTrialActive = response.isTrial
            
            // 更新到期日期
            if let subscriptionEndString = response.subscriptionEnd {
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
            print("❌ 验证交易收据失败: \(error.localizedDescription)")
            // 验证失败时，尝试从后端获取最新状态（作为备用）
            await updateSubscriptionStatusFromBackend()
        }
    }
    
    // MARK: - 验证无订阅状态
    private func verifyNoSubscription() async {
        // 当没有订阅时，也要通知后端清除可能存在的过期订阅状态
        do {
            // 调用后端获取状态（这会清除过期订阅）
            let response = try await NetworkService.shared.getSubscriptionStatus()
            
            // 更新本地状态
            if let status = AppSubscriptionStatus(rawValue: response.status) {
                self.subscriptionStatus = status
            }
            self.isTrialActive = response.isTrial
            
            print("✅ 无订阅状态已同步: \(subscriptionStatus.rawValue)")
        } catch {
            print("⚠️ 同步无订阅状态失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 检查 StoreKit 订阅状态
    private func checkStoreKitSubscription() async {
        // 检查自动续费订阅状态
        if let product = monthlyProduct {
            await checkProductSubscription(product: product)
        }
    }
    
    // MARK: - 检查单个产品的订阅状态
    private func checkProductSubscription(product: Product) async {
        do {
            // 获取当前订阅状态（仅对自动续费订阅有效）
            if let subscription = product.subscription {
                let statuses = try await subscription.status
                
                // 查找活跃的订阅
                for status in statuses {
                    switch status.state {
                    case .subscribed:
                        print("✅ 订阅活跃: \(product.id)")
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
                            
                            // 验证收据到后端（Apple 要求必须验证）
                            await verifyTransactionReceipt(transaction: transaction)
                        }
                        return
                        
                    case .expired, .revoked:
                        print("ℹ️ 订阅已过期或被撤销: \(product.id)")
                        self.currentSubscription = nil
                        
                    case .inBillingRetryPeriod:
                        print("⚠️ 订阅在账单重试期: \(product.id)")
                        // 仍然允许访问
                        self.currentSubscription = status
                        
                    case .inGracePeriod:
                        print("ℹ️ 订阅在宽限期: \(product.id)")
                        // 仍然允许访问
                        self.currentSubscription = status
                        
                    default:
                        print("⚠️ 未知订阅状态: \(product.id)")
                    }
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
    
    // MARK: - 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            guard let self = self else { return }
            // 监听交易更新
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try self.verifyTransaction(result)
                    print("🔔 收到交易更新: \(transaction.productID)")
                    
                    // 验证收据到后端（Apple 要求必须验证收据）
                    await self.verifyTransactionReceipt(transaction: transaction)
                    
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
