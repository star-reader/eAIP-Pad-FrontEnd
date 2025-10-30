import Foundation
import SwiftUI
import SwiftData

#if canImport(StoreKit)
import StoreKit
typealias AppStoreTransaction = StoreKit.Transaction
#else
// 如果StoreKit不可用，创建一个占位符类型
struct AppStoreTransaction {
    let productID: String
    static func finish() async {}
}
#endif

// MARK: - 订阅服务
@Observable
class SubscriptionService {
    static let shared = SubscriptionService()
    
    // 产品ID
    private let monthlyProductID = "com.eaip.monthly"
    
    // 订阅状态
    var subscriptionStatus: SubscriptionStatus = .inactive
    var isTrialActive = false
    var subscriptionEndDate: Date?
    var trialEndDate: Date?
    var daysLeft: Int = 0
    
    // StoreKit 产品
    var monthlyProduct: Product?
    var isLoading = false
    var errorMessage: String?
    
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
    @MainActor
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let products = try await Product.products(for: [monthlyProductID])
            monthlyProduct = products.first
        } catch {
            errorMessage = "加载产品信息失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - 购买订阅
    @MainActor
    func purchaseMonthlySubscription() async {
        guard let product = monthlyProduct else {
            errorMessage = "产品信息未加载"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                
                // 验证收据
                await verifyReceiptWithBackend(transaction)
                
                // 完成交易
                await transaction.finish()
                
                // 更新订阅状态
                await updateSubscriptionStatus()
                
            case .userCancelled:
                errorMessage = "用户取消购买"
                
            case .pending:
                errorMessage = "购买待处理"
                
            @unknown default:
                errorMessage = "未知购买结果"
            }
        } catch {
            errorMessage = "购买失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - 恢复购买
    @MainActor
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            errorMessage = "恢复购买失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - 更新订阅状态
    @MainActor
    func updateSubscriptionStatus() async {
        // 检查当前订阅状态
        #if canImport(StoreKit)
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                if transaction.productID == monthlyProductID {
                    // 有活跃订阅
                    subscriptionStatus = .active
                    
                    // 从后端获取详细状态
                    await fetchSubscriptionStatusFromBackend()
                    return
                }
            } catch {
                print("验证交易失败: \(error)")
            }
        }
        #endif
        
        // 没有活跃订阅，检查试用状态
        await fetchSubscriptionStatusFromBackend()
    }
    
    // MARK: - 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            #if canImport(StoreKit)
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
            #endif
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
    #if canImport(StoreKit)
    private func verifyReceiptWithBackend(_ transaction: StoreKit.Transaction) async {
        do {
            // 获取收据数据
            guard let receiptData = await getReceiptData() else {
                print("无法获取收据数据")
                return
            }
            
            // 发送到后端验证
            let _ = try await NetworkService.shared.verifyIAP(receipt: receiptData)
            
        } catch {
            print("后端收据验证失败: \(error)")
        }
    }
    #endif
    
    // MARK: - 从后端获取订阅状态
    private func fetchSubscriptionStatusFromBackend() async {
        do {
            let response = try await NetworkService.shared.getSubscriptionStatus()
            
            await MainActor.run {
                self.subscriptionStatus = SubscriptionStatus(rawValue: response.status) ?? .inactive
                self.isTrialActive = response.isTrial
                self.daysLeft = response.daysLeft ?? 0
                
                // 解析日期
                if let trialEndString = response.trialEnd {
                    self.trialEndDate = ISO8601DateFormatter().date(from: trialEndString)
                }
                
                if let subscriptionEndString = response.subscriptionEnd {
                    self.subscriptionEndDate = ISO8601DateFormatter().date(from: subscriptionEndString)
                }
            }
        } catch {
            print("获取订阅状态失败: \(error)")
            await MainActor.run {
                self.subscriptionStatus = .inactive
            }
        }
    }
    
    // MARK: - 获取收据数据
    private func getReceiptData() async -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else {
            return nil
        }
        
        return receiptData.base64EncodedString()
    }
    
    // MARK: - 格式化价格
    func formattedPrice(for product: Product) -> String {
        return product.displayPrice
    }
    
    // MARK: - 检查是否有有效订阅
    var hasValidSubscription: Bool {
        return subscriptionStatus.isValid
    }
    
    // MARK: - 获取订阅描述
    var subscriptionDescription: String {
        switch subscriptionStatus {
        case .trial:
            if let trialEndDate = trialEndDate {
                return "试用期至 \(trialEndDate.formatted(.dateTime.month().day()))"
            } else {
                return "试用期"
            }
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

// MARK: - 订阅视图
struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionService = SubscriptionService.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 头部
                    VStack(spacing: 16) {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.orange)
                        
                        Text("eAIP Pad Pro")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("专业航图阅读体验")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    // 功能特性
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(
                            icon: "doc.text.fill",
                            title: "完整航图库",
                            description: "访问所有中国eAIP航图和文档"
                        )
                        
                        FeatureRow(
                            icon: "pencil.tip.crop.circle.fill",
                            title: "专业标注",
                            description: "Apple Pencil支持，标注永久保存"
                        )
                        
                        FeatureRow(
                            icon: "pin.fill",
                            title: "快速访问",
                            description: "收藏常用航图，一键打开"
                        )
                        
                        FeatureRow(
                            icon: "arrow.clockwise",
                            title: "自动更新",
                            description: "AIRAC版本自动同步更新"
                        )
                        
                        FeatureRow(
                            icon: "moon.fill",
                            title: "夜间模式",
                            description: "护眼深色主题，专业飞行体验"
                        )
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    
                    // 当前状态
                    if subscriptionService.hasValidSubscription {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("已订阅")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            Text(subscriptionService.subscriptionDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        // 订阅选项
                        VStack(spacing: 16) {
                            if let product = subscriptionService.monthlyProduct {
                                SubscriptionOptionCard(
                                    title: "月度订阅",
                                    price: subscriptionService.formattedPrice(for: product),
                                    description: "首月免费，随时取消",
                                    isRecommended: true
                                ) {
                                    Task {
                                        await subscriptionService.purchaseMonthlySubscription()
                                    }
                                }
                            }
                        }
                    }
                    
                    // 错误信息
                    if let errorMessage = subscriptionService.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    
                    // 恢复购买
                    Button("恢复购买") {
                        Task {
                            await subscriptionService.restorePurchases()
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    
                    // 法律信息
                    VStack(spacing: 8) {
                        Text("订阅将自动续费，可随时在设置中取消")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        HStack {
                            Button("服务条款") {
                                // TODO: 打开服务条款
                            }
                            
                            Text("·")
                                .foregroundColor(.secondary)
                            
                            Button("隐私政策") {
                                // TODO: 打开隐私政策
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle("订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .disabled(subscriptionService.isLoading)
        .overlay {
            if subscriptionService.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }
}

// MARK: - 功能特性行
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - 订阅选项卡片
struct SubscriptionOptionCard: View {
    let title: String
    let price: String
    let description: String
    let isRecommended: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                if isRecommended {
                    Text("推荐")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.orange, in: Capsule())
                }
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(price)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                isRecommended ? .orange.opacity(0.1) : .clear,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isRecommended ? .orange : .secondary.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SubscriptionView()
}
