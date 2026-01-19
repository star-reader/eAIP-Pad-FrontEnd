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

    private init() {
        LoggerService.shared.info(module: "SubscriptionService", message: "订阅服务初始化")
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
                        module: "SubscriptionService", message: "交易验证成功，准备发送到服务器")
                    let transactionJWS = verificationResult.jwsRepresentation
                    LoggerService.shared.info(
                        module: "SubscriptionService", message: "交易 JWS: \(transactionJWS)")
                    
                    let success = await verifyTransactionWithServer(
                        transactionJWS: transactionJWS, transaction: transaction)
                    if success {
                        await transaction.finish()
                        await updateSubscriptionStatus()
                        LoggerService.shared.info(
                            module: "SubscriptionService", message: "购买成功，订阅已激活")
                        isLoading = false
                        return true
                    } else {
                        await transaction.finish()
                        LoggerService.shared.warning(
                            module: "SubscriptionService", message: "服务器验证失败，购买未完成")
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

    // MARK: - 验证交易
    private func verifyTransactionWithServer(
        transactionJWS: String, transaction: StoreKit.Transaction
    ) async -> Bool {
        guard let appleUserId = authService.appleUserId else {
            errorMessage = "无法获取 Apple 用户 ID"
            LoggerService.shared.error(module: "SubscriptionService", message: "无法获取 Apple 用户 ID")
            return false
        }

        LoggerService.shared.info(
            module: "SubscriptionService", message: "Apple 用户 ID: \(appleUserId)")

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

            syncStatusFromManager(statusManager: statusManager, response: response)

            if response.status == "success" {
                LoggerService.shared.info(
                    module: "SubscriptionService",
                    message: "服务器验证成功，订阅状态: \(response.subscriptionStatus ?? "未知")")
                return true
            } else {
                errorMessage = response.message ?? "订阅验证失败"
                LoggerService.shared.warning(
                    module: "SubscriptionService", message: "服务器验证失败: \(response.message ?? "未知错误")"
                )
                return false
            }
        } catch {
            errorMessage = "服务器验证失败: \(error.localizedDescription)"
            LoggerService.shared.error(
                module: "SubscriptionService", message: "服务器验证失败: \(error.localizedDescription)")
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
            var jwsList: [String] = []
            for await result in Transaction.currentEntitlements {
                if let jws = JWSParser.getJWSString(from: result), !jws.isEmpty {
                    jwsList.append(jws)
                } else {
                    LoggerService.shared.warning(
                        module: "SubscriptionService", message: "无法获取交易 JWS，跳过该交易")
                }
            }

            LoggerService.shared.info(
                module: "SubscriptionService", message: "找到 \(jwsList.count) 个本地交易")

            if jwsList.isEmpty {
                LoggerService.shared.info(module: "SubscriptionService", message: "无本地交易，查询服务器状态")
                await querySubscriptionStatus()
            } else {
                LoggerService.shared.info(
                    module: "SubscriptionService",
                    message: "交易 JWS 列表: \(jwsList.joined(separator: ","))")
                let environment = JWSParser.extractEnvironment(from: jwsList.first ?? "")
                let response = try await networkService.syncSubscriptions(
                    transactionJWSList: jwsList,
                    appleUserId: appleUserId,
                    environment: environment
                )

                syncStatusFromManager(statusManager: statusManager, response: response)

                if response.status == "success" {
                    LoggerService.shared.info(
                        module: "SubscriptionService",
                        message: "订阅同步成功，状态: \(subscriptionStatus.rawValue)")
                } else {
                    LoggerService.shared.warning(
                        module: "SubscriptionService",
                        message: "订阅同步失败: \(response.message ?? "未知错误")")
                    await querySubscriptionStatus()
                }
            }
        } catch {
            LoggerService.shared.error(
                module: "SubscriptionService", message: "同步订阅失败: \(error.localizedDescription)")
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
            syncStatusFromManager(statusManager: statusManager, response: response)
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
    private func syncStatusFromManager(statusManager: SubscriptionStatusManager, response: VerifyJWSResponse) {
        statusManager.updateStatus(from: response)
        self.subscriptionStatus = statusManager.subscriptionStatus
        self.subscriptionStartDate = statusManager.subscriptionStartDate
        self.subscriptionEndDate = statusManager.subscriptionEndDate
        self.trialStartDate = statusManager.trialStartDate
        self.daysLeft = statusManager.daysLeft
    }
    
    private func syncStatusFromManager(statusManager: SubscriptionStatusManager, response: SyncSubscriptionResponse) {
        statusManager.updateStatus(from: response)
        self.subscriptionStatus = statusManager.subscriptionStatus
        self.subscriptionStartDate = statusManager.subscriptionStartDate
        self.subscriptionEndDate = statusManager.subscriptionEndDate
        self.trialStartDate = statusManager.trialStartDate
        self.daysLeft = statusManager.daysLeft
    }
    
    private func syncStatusFromManager(statusManager: SubscriptionStatusManager, response: SubscriptionStatusResponse) {
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
                    LoggerService.shared.info(
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

                let success = await self.verifyTransactionWithServer(
                    transactionJWS: transactionJWS, transaction: transaction)
                if success {
                    await transaction.finish()
                    await self.updateSubscriptionStatus()

                    await MainActor.run {
                        LoggerService.shared.info(
                            module: "SubscriptionService", message: "交易更新处理完成")
                    }
                }
            }
        }
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
            await syncSubscriptionStatus()
            LoggerService.shared.info(module: "SubscriptionService", message: "恢复购买成功")
        } catch {
            errorMessage = "恢复购买失败: \(error.localizedDescription)"
            LoggerService.shared.error(
                module: "SubscriptionService", message: "恢复购买失败: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - 计算属性
    var hasValidSubscription: Bool {
        return subscriptionStatus.isValid
    }

    var hasUsedTrial: Bool {
        return trialStartDate != nil
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
