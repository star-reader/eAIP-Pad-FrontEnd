import Combine
import Foundation
import StoreKit
import SwiftData
import SwiftUI

// MARK: - 订阅服务（重构版）
@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    private let monthlyProductID = "com.usagijin.eaip.monthly"

    @Published var subscriptionStatus: AppSubscriptionStatus = .inactive
    @Published var subscriptionStartDate: Date?
    @Published var subscriptionEndDate: Date?
    @Published var trialStartDate: Date?
    @Published var daysLeft: Int = 0
    @Published var monthlyProduct: Product?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasLoadedOnce = false

    private var updateListenerTask: Task<Void, Error>?
    private let networkService = NetworkService.shared
    private let authService = AuthenticationService.shared
    private let statusManager = SubscriptionStatusManager()

    /// 指数退避重试参数
    private static let verifyMaxRetries = 3
    private static func verifyRetryDelay(attempt: Int) -> UInt64 {
        // 1s, 2s, 4s
        return UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
    }

    private init() {
        LoggerService.shared.info(module: "SubscriptionService", message: "订阅服务初始化")
        // Transaction.updates 监听器必须尽早启动，以免 App 启动时到来的 Transaction 被丢失
        updateListenerTask = listenForTransactions()
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - 加载产品
    func loadProducts() async {
        LoggerService.shared.info(module: "SubscriptionService", message: "开始加载产品")
        isLoading = true
        errorMessage = nil

        do {
            let products = try await Product.products(for: [monthlyProductID])
            monthlyProduct = products.first

            if monthlyProduct == nil {
                LoggerService.shared.warning(
                    module: "SubscriptionService", message: "未找到产品: \(monthlyProductID)")
            } else {
                LoggerService.shared.info(module: "SubscriptionService", message: "产品加载成功")
            }
        } catch {
            errorMessage = "加载产品失败: \(error.localizedDescription)"
            LoggerService.shared.error(
                module: "SubscriptionService", message: "加载产品失败: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - 购买订阅
    func purchaseMonthlySubscription() async -> Bool {
        if monthlyProduct == nil {
            await loadProducts()
        }

        guard let product = monthlyProduct else {
            errorMessage = "产品未加载，请稍后再试"
            LoggerService.shared.warning(module: "SubscriptionService", message: "购买失败：产品未加载")
            return false
        }

        LoggerService.shared.info(module: "SubscriptionService", message: "开始购买月度订阅")
        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    LoggerService.shared.info(
                        module: "SubscriptionService", 
                        message: "交易验证成功，产品: \(transaction.productID), 交易ID: \(transaction.id)")
                    let transactionJWS = verificationResult.jwsRepresentation
                    LoggerService.shared.debug(
                        module: "SubscriptionService", message: "交易 JWS: \(transactionJWS)")
                    
                    // 必须先成功向后端注册 Transaction，再 finish。
                    // 若先 finish 后 verify 失败，Transaction.updates 将不再重放该交易，
                    // 导致 original_transaction_id 永久无法写入后端（核心 Bug 根因）。
                    let success = await verifyTransactionWithServerWithRetry(
                        transactionJWS: transactionJWS, transaction: transaction)
                    if success {
                        await transaction.finish()
                        await updateSubscriptionStatus()
                        LoggerService.shared.info(
                            module: "SubscriptionService", message: "购买成功，订阅已激活")
                        isLoading = false
                        return true
                    } else {
                        // 不调用 transaction.finish()，保留在 StoreKit 队列中。
                        // 下次 App 启动时 Transaction.updates 会重放，再次尝试 /verify。
                        LoggerService.shared.warning(
                            module: "SubscriptionService",
                            message: "后端 /verify 全部重试失败，Transaction 保留在队列，等待下次补发")
                        isLoading = false
                        return false
                    }
                case .unverified(_, let error):
                    errorMessage = "交易验证失败: \(error.localizedDescription)"
                    LoggerService.shared.error(
                        module: "SubscriptionService",
                        message: "交易验证失败: \(error.localizedDescription)")
                    isLoading = false
                    return false
                }
            case .userCancelled:
                errorMessage = "用户取消了购买"
                LoggerService.shared.info(module: "SubscriptionService", message: "用户取消了购买")
                isLoading = false
                return false
            case .pending:
                errorMessage = "购买正在处理中，请稍候"
                LoggerService.shared.info(module: "SubscriptionService", message: "购买正在处理中")
                isLoading = false
                return false
            @unknown default:
                errorMessage = "未知的购买结果"
                LoggerService.shared.warning(module: "SubscriptionService", message: "未知的购买结果")
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "购买失败: \(error.localizedDescription)"
            LoggerService.shared.error(
                module: "SubscriptionService", message: "购买失败: \(error.localizedDescription)")
            isLoading = false
            return false
        }
    }

    // MARK: - 验证交易（带指数退避重试）
    /// 对 /verify 接口进行最多 verifyMaxRetries 次重试，使用指数退避策略。
    /// 任何环境（sandbox / production / Xcode）下都必须执行，不得有环境分支跳过此调用。
    private func verifyTransactionWithServerWithRetry(
        transactionJWS: String, transaction: StoreKit.Transaction
    ) async -> Bool {
        for attempt in 0..<SubscriptionService.verifyMaxRetries {
            let success = await verifyTransactionWithServer(
                transactionJWS: transactionJWS, transaction: transaction)
            if success { return true }

            let isLastAttempt = attempt == SubscriptionService.verifyMaxRetries - 1
            if !isLastAttempt {
                let delay = SubscriptionService.verifyRetryDelay(attempt: attempt)
                LoggerService.shared.warning(
                    module: "SubscriptionService",
                    message: "/verify 失败，\(delay / 1_000_000_000)s 后重试 (\(attempt + 1)/\(SubscriptionService.verifyMaxRetries))")
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        LoggerService.shared.error(
            module: "SubscriptionService",
            message: "/verify 接口已重试 \(SubscriptionService.verifyMaxRetries) 次仍失败，Transaction 暂不 finish")
        return false
    }

    // MARK: - 验证交易（单次）
    private func verifyTransactionWithServer(
        transactionJWS: String, transaction: StoreKit.Transaction
    ) async -> Bool {
        guard let appleUserId = authService.appleUserId else {
            errorMessage = "无法获取 Apple 用户 ID"
            LoggerService.shared.error(module: "SubscriptionService", message: "无法获取 Apple 用户 ID")
            return false
        }

        LoggerService.shared.info(
            module: "SubscriptionService",
            message: "验证交易 - 用户: \(appleUserId.maskedAppleUserId), 产品: \(transaction.productID)")

        // 从 JWS 提取环境，任何环境都透传，不做分支跳过
        let environment = JWSParser.extractEnvironment(from: transactionJWS)
        LoggerService.shared.info(
            module: "SubscriptionService", message: "交易环境: \(environment ?? "未知")")

        do {
            LoggerService.shared.info(module: "SubscriptionService", message: "开始向服务器验证交易")
            let response = try await networkService.verifyJWS(
                transactionJWS: transactionJWS,
                appleUserId: appleUserId,
                environment: environment
            )

            syncStatusFromManager(response: response)

            if response.status == "success" {
                LoggerService.shared.info(
                    module: "SubscriptionService",
                    message: "服务器验证成功，订阅状态: \(response.subscriptionStatus ?? "未知")")
                return true
            } else {
                errorMessage = response.message ?? "订阅验证失败"
                LoggerService.shared.warning(
                    module: "SubscriptionService",
                    message: "服务器验证失败: \(response.message ?? "未知错误"), 状态: \(response.status)")
                return false
            }
        } catch {
            errorMessage = "服务器验证失败: \(error.localizedDescription)"
            LoggerService.shared.error(
                module: "SubscriptionService",
                message: "服务器验证失败: \(error.localizedDescription), 错误类型: \(type(of: error))")
            return false
        }
    }

    // MARK: - 同步订阅状态
    func syncSubscriptionStatus() async {
        LoggerService.shared.info(module: "SubscriptionService", message: "开始同步订阅状态")
        guard let appleUserId = authService.appleUserId else {
            LoggerService.shared.warning(
                module: "SubscriptionService", message: "无法获取 Apple 用户 ID，跳过同步")
            return
        }

        LoggerService.shared.info(module: "SubscriptionService", message: "同步用户 ID: \(appleUserId)")
        isLoading = true

        do {
            // 使用 Transaction.all 获取所有交易历史（包括过期的）
            // 这样可以确保后端能够正确验证用户的订阅状态
            var jwsList: [String] = []
            var validJWSCount = 0
            var expiredJWSCount = 0
            
            for await result in Transaction.all {
                guard case .verified(let transaction) = result else {
                    LoggerService.shared.warning(
                        module: "SubscriptionService", message: "交易验证失败，跳过")
                    continue
                }
                
                // 只处理订阅类型的交易
                if transaction.productType == .autoRenewable {
                    if let jws = JWSParser.getJWSString(from: result), !jws.isEmpty {
                        jwsList.append(jws)
                        
                        // 统计有效和过期的交易
                        if transaction.expirationDate ?? Date.distantPast > Date() {
                            validJWSCount += 1
                        } else {
                            expiredJWSCount += 1
                        }
                    }
                }
            }

            LoggerService.shared.info(
                module: "SubscriptionService", 
                message: "找到 \(jwsList.count) 个订阅交易（有效: \(validJWSCount), 过期: \(expiredJWSCount)）")

            if jwsList.isEmpty {
                LoggerService.shared.info(module: "SubscriptionService", message: "无本地交易，查询服务器状态")
                await querySubscriptionStatus()
            } else {
                LoggerService.shared.debug(
                    module: "SubscriptionService",
                    message: "准备同步 \(jwsList.count) 个交易到服务器")
                let environment = JWSParser.extractEnvironment(from: jwsList.first ?? "")
                let response = try await networkService.syncSubscriptions(
                    transactionJWSList: jwsList,
                    appleUserId: appleUserId,
                    environment: environment
                )

                syncStatusFromManager(response: response)

                if response.status == "success" {
                    LoggerService.shared.info(
                        module: "SubscriptionService",
                        message: "订阅同步成功，状态: \(subscriptionStatus.rawValue)")
                } else {
                    LoggerService.shared.warning(
                        module: "SubscriptionService",
                        message: "订阅同步失败: \(response.message ?? "未知错误")")
                    // 同步失败时仍然查询服务器状态作为后备
                    await querySubscriptionStatus()
                }
            }
        } catch {
            LoggerService.shared.error(
                module: "SubscriptionService", message: "同步订阅失败: \(error.localizedDescription)")
            // 发生错误时查询服务器状态作为后备
            await querySubscriptionStatus()
        }

        isLoading = false
        hasLoadedOnce = true
    }

    // MARK: - 查询订阅状态
    func querySubscriptionStatus() async {
        guard let appleUserId = authService.appleUserId else {
            LoggerService.shared.warning(
                module: "SubscriptionService", message: "无法查询订阅状态：缺少 Apple 用户 ID")
            return
        }

        LoggerService.shared.info(module: "SubscriptionService", message: "开始查询订阅状态")
        LoggerService.shared.info(module: "SubscriptionService", message: "查询用户 ID: \(appleUserId)")

        do {
            let response = try await networkService.getSubscriptionStatus(appleUserId: appleUserId)
            syncStatusFromManager(response: response)
            LoggerService.shared.info(
                module: "SubscriptionService",
                message: "查询订阅状态成功，状态: \(subscriptionStatus.rawValue)")
            hasLoadedOnce = true
        } catch {
            LoggerService.shared.error(
                module: "SubscriptionService", message: "查询订阅状态失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 同步状态管理器的数据到发布属性
    private func syncStatusFromManager(response: SubscriptionResponseProtocol) {
        statusManager.updateStatus(from: response)
        self.subscriptionStatus = statusManager.subscriptionStatus
        self.subscriptionStartDate = statusManager.subscriptionStartDate
        self.subscriptionEndDate = statusManager.subscriptionEndDate
        self.trialStartDate = statusManager.trialStartDate
        self.daysLeft = statusManager.daysLeft
    }

    // MARK: - 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            guard let self = self else { return }

            await MainActor.run {
                LoggerService.shared.info(module: "SubscriptionService", message: "开始监听交易更新")
            }

            for await result in Transaction.updates {
                await MainActor.run {
                    LoggerService.shared.info(module: "SubscriptionService", message: "收到交易更新通知")
                }

                guard let transactionJWS = JWSParser.getJWSString(from: result) else {
                    await MainActor.run {
                        LoggerService.shared.warning(
                            module: "SubscriptionService", message: "无法获取交易 JWS，跳过该交易")
                    }
                    continue
                }

                await MainActor.run {
                    LoggerService.shared.debug(
                        module: "SubscriptionService", message: "更新交易 JWS: \(transactionJWS)")
                }

                let transaction: StoreKit.Transaction
                switch result {
                case .verified(let verifiedTransaction):
                    transaction = verifiedTransaction
                case .unverified(_, let error):
                    await MainActor.run {
                        LoggerService.shared.error(
                            module: "SubscriptionService",
                            message: "交易验证失败: \(error.localizedDescription)")
                    }
                    continue
                }

                // 同样使用带重试的验证，成功后才 finish
                let success = await self.verifyTransactionWithServerWithRetry(
                    transactionJWS: transactionJWS, transaction: transaction)
                if success {
                    await transaction.finish()
                    await self.updateSubscriptionStatus()

                    await MainActor.run {
                        LoggerService.shared.info(
                            module: "SubscriptionService", message: "交易更新处理完成")
                    }
                } else {
                    await MainActor.run {
                        LoggerService.shared.warning(
                            module: "SubscriptionService",
                            message: "Transaction.updates: /verify 重试全部失败，Transaction 保留队列")
                    }
                }
            }
        }
    }

    // MARK: - 遍历 currentEntitlements 补发 /verify
    /// 每次 App 进入前台 / 用户登录后调用。
    /// 遍历 StoreKit 2 的 Transaction.currentEntitlements，对每个有效权益调用 /verify，
    /// 确保即使 Transaction.updates 未来得及触发，后端也能收到 original_transaction_id。
    func verifyCurrentEntitlements() async {
        guard authService.appleUserId != nil else {
            LoggerService.shared.warning(
                module: "SubscriptionService",
                message: "verifyCurrentEntitlements: 用户未登录，跳过")
            return
        }

        LoggerService.shared.info(
            module: "SubscriptionService",
            message: "开始遍历 currentEntitlements 补发 /verify")

        var count = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                LoggerService.shared.warning(
                    module: "SubscriptionService",
                    message: "currentEntitlements: 交易未通过 StoreKit 验证，跳过")
                continue
            }
            guard transaction.productType == .autoRenewable else { continue }

            let jws = result.jwsRepresentation
            count += 1
            LoggerService.shared.info(
                module: "SubscriptionService",
                message: "currentEntitlements: 补发 /verify，产品: \(transaction.productID)")

            let success = await verifyTransactionWithServerWithRetry(
                transactionJWS: jws, transaction: transaction)
            if success {
                await transaction.finish()
            } else {
                LoggerService.shared.warning(
                    module: "SubscriptionService",
                    message: "currentEntitlements: /verify 失败，Transaction 保留队列")
            }
        }

        LoggerService.shared.info(
            module: "SubscriptionService",
            message: "currentEntitlements 遍历完成，共处理 \(count) 个有效权益")

        // 无论是否有权益，都刷新一次服务器侧状态
        await querySubscriptionStatus()
    }

    // MARK: - 更新订阅状态
    private func updateSubscriptionStatus() async {
        await querySubscriptionStatus()
    }

    // MARK: - 恢复购买
    func restorePurchases() async {
        LoggerService.shared.info(module: "SubscriptionService", message: "开始恢复购买")
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()
            LoggerService.shared.info(module: "SubscriptionService", message: "AppStore 同步成功")
            // AppStore.sync() 会触发 Transaction.updates 重放进行 /verify，
            // 同时对 currentEntitlements 显式补发，覆盖重装/账号切换等边缘场景
            await verifyCurrentEntitlements()
            LoggerService.shared.info(module: "SubscriptionService", message: "恢复购买成功")
        } catch {
            errorMessage = "恢复购买失败: \(error.localizedDescription)"
            LoggerService.shared.error(
                module: "SubscriptionService", message: "恢复购买失败: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - 计算属性（代理到 statusManager）
    var hasValidSubscription: Bool {
        return statusManager.hasValidSubscription
    }

    var hasUsedTrial: Bool {
        return statusManager.hasUsedTrial
    }

    var subscriptionDescription: String {
        return statusManager.subscriptionDescription
    }
}
