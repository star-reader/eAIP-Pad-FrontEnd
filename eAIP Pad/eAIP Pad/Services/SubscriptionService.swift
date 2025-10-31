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
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    // 产品ID
    private let monthlyProductID = "com.eaip.pad.monthly"
    
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
        do {
            let products = try await Product.products(for: [monthlyProductID])
            await MainActor.run {
                self.availableProducts = products
                self.monthlyProduct = products.first
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载产品失败: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - 购买月度订阅
    func purchaseMonthlySubscription() async -> Bool {
        guard let product = monthlyProduct else {
            await MainActor.run {
                self.errorMessage = "产品不可用"
            }
            return false
        }
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                
                // 完成交易
                await transaction.finish()
                
                // 更新订阅状态
                await updateSubscriptionStatus()
                
                await MainActor.run {
                    self.isLoading = false
                }
                return true
                
            case .userCancelled:
                await MainActor.run {
                    self.errorMessage = "已取消"
                    self.isLoading = false
                }
                return false
                
            case .pending:
                await MainActor.run {
                    self.errorMessage = "购买正在处理中，请稍候"
                    self.isLoading = false
                }
                return false
                
            @unknown default:
                await MainActor.run {
                    self.isLoading = false
                }
                return false
            }
        } catch {
            await MainActor.run {
                // 提供更友好的错误信息
                if error.localizedDescription.contains("cancelled") || error.localizedDescription.contains("cancel") {
                    self.errorMessage = "已取消"
                } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("Network") {
                    self.errorMessage = "网络连接失败，请检查网络后重试"
                } else if error.localizedDescription.contains("No active account") {
                    self.errorMessage = "请先在设置中登录Apple ID"
                } else {
                    self.errorMessage = "发生错误，请稍后重试"
                }
                self.isLoading = false
            }
            return false
        }
    }
    
    // MARK: - 恢复购买
    func restorePurchases() async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            await MainActor.run {
                // 提供更友好的错误信息
                if error.localizedDescription.contains("No active account") {
                    self.errorMessage = "请先在设置中登录Apple ID"
                } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("Network") {
                    self.errorMessage = "网络连接失败，请检查网络后重试"
                } else {
                    self.errorMessage = "未找到可恢复的购买记录"
                }
            }
        }
        
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    // MARK: - 开始试用
    func startTrial() async -> Bool {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            // 确保用户已登录
            guard AuthenticationService.shared.currentUser != nil else {
                await MainActor.run {
                    self.errorMessage = "用户未登录"
                    self.isLoading = false
                }
                return false
            }
            
            // 调用后端开始试用（使用空字符串作为 userId，后端会从 token 中提取）
            let response = try await NetworkService.shared.startTrial(userId: "")
            print("✅ 试用开始成功: \(response)")
            
            // 更新订阅状态
            await updateSubscriptionStatus()
            
            await MainActor.run {
                self.isLoading = false
            }
            
            return true
        } catch let error as DecodingError {
            print("❌ JSON 解析错误: \(error)")
            switch error {
            case .keyNotFound(let key, let context):
                print("缺少键: \(key.stringValue), context: \(context)")
            case .typeMismatch(let type, let context):
                print("类型不匹配: \(type), context: \(context)")
            case .valueNotFound(let type, let context):
                print("值未找到: \(type), context: \(context)")
            case .dataCorrupted(let context):
                print("数据损坏: \(context)")
            @unknown default:
                print("未知解析错误")
            }
            
            // 即使解析失败，也更新订阅状态（因为后端可能已经成功）
            await updateSubscriptionStatus()
            
            await MainActor.run {
                self.isLoading = false
            }
            
            // 如果后端已经成功，返回 true
            if subscriptionStatus == .trial {
                return true
            }
            
            await MainActor.run {
                self.errorMessage = "响应格式错误，但试用可能已开启，请刷新查看"
            }
            return false
        } catch {
            print("❌ 开启试用失败: \(error)")
            await MainActor.run {
                if error.localizedDescription.contains("network") || error.localizedDescription.contains("Network") {
                    self.errorMessage = "网络连接失败，请检查网络后重试"
                } else {
                    self.errorMessage = "开启试用失败: \(error.localizedDescription)"
                }
                self.isLoading = false
            }
            return false
        }
    }
    
    // MARK: - 更新订阅状态
    @MainActor
    func updateSubscriptionStatus() async {
        print("🔄 开始更新订阅状态...")
        
        // 首先从后端获取最新状态（包括试用期状态）
        await fetchSubscriptionStatusFromBackend()
        
        // 如果后端显示没有订阅，再检查本地 StoreKit 交易
        if subscriptionStatus == .inactive {
            print("📱 后端显示未订阅，检查本地 StoreKit 交易...")
            
            for await result in Transaction.currentEntitlements {
                do {
                    let transaction = try checkVerified(result)
                    
                    if transaction.productID == monthlyProductID {
                        print("✅ 发现本地活跃订阅")
                        subscriptionStatus = .active
                        return
                    }
                } catch {
                    print("⚠️ 验证交易失败: \(error)")
                }
            }
        }
        
        print("📊 最终订阅状态: \(subscriptionStatus)")
    }
    
    // MARK: - 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    
                    // 验证收据
                    await self.verifyReceiptWithBackend(transaction)
                    
                    // 更新订阅状态
                    await self.updateSubscriptionStatus()
                    
                    // 完成交易
                    await transaction.finish()
                } catch {
                    print("处理交易更新失败: \(error)")
                }
            }
        }
    }
    
    // MARK: - 验证交易
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - 后端收据验证
    private func verifyReceiptWithBackend(_ transaction: StoreKit.Transaction) async {
        // TODO: 实现后端收据验证
        print("验证收据: \(transaction.productID)")
    }
    
    // MARK: - 从后端获取订阅状态
    private func fetchSubscriptionStatusFromBackend() async {
        do {
            let response = try await NetworkService.shared.getSubscriptionStatus()
            
            print("🌐 后端订阅状态响应: status=\(response.status), isTrial=\(response.isTrial), daysLeft=\(response.daysLeft ?? 0)")
            
            await MainActor.run {
                // 根据后端响应设置状态
                if response.isTrial || response.status == "trial" || response.status == "trial_started" {
                    self.subscriptionStatus = .trial
                } else {
                    self.subscriptionStatus = AppSubscriptionStatus(rawValue: response.status) ?? .inactive
                }
                
                self.isTrialActive = response.isTrial
                self.daysLeft = response.daysLeft ?? 0
                
                print("📱 设置本地状态: subscriptionStatus=\(self.subscriptionStatus), isTrialActive=\(self.isTrialActive)")
                
                // 解析日期
                if let trialEndString = response.trialEnd {
                    self.trialEndDate = ISO8601DateFormatter().date(from: trialEndString)
                }
                
                if let subscriptionEndString = response.subscriptionEnd {
                    self.subscriptionEndDate = ISO8601DateFormatter().date(from: subscriptionEndString)
                }
            }
        } catch {
            print("⚠️ 获取后端订阅状态失败: \(error.localizedDescription)")
            await MainActor.run {
                self.subscriptionStatus = .inactive
            }
        }
    }
    
    // MARK: - 格式化价格
    func formattedPrice(for product: Product) -> String {
        return product.displayPrice
    }
    
    // MARK: - 订阅状态检查
    var hasValidSubscription: Bool {
        return subscriptionStatus.isValid
    }
    
    // MARK: - 获取收据数据
    func getReceiptData() async -> Data? {
        do {
            let verificationResult = try await AppTransaction.shared
            let appTransaction = try checkVerified(verificationResult)
            return Data(appTransaction.originalAppVersion.utf8)
        } catch {
            print("获取收据数据失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 订阅描述
    var subscriptionDescription: String {
        switch subscriptionStatus {
        case .trial:
            return "试用期 - 剩余 \(daysLeft) 天"
        case .active:
            if let subscriptionEndDate = subscriptionEndDate {
                return "订阅至 \(subscriptionEndDate.formatted(.dateTime.month().day()))"
            } else {
                return "已订阅"
            }
        case .expired:
            return "订阅已过期"
        case .inactive:
            return "未订阅"
        }
    }
}

// MARK: - StoreKit 错误
enum StoreError: Error {
    case failedVerification
    case unknownError
    
    var localizedDescription: String {
        switch self {
        case .failedVerification:
            return "交易验证失败"
        case .unknownError:
            return "未知错误"
        }
    }
}