import Combine
import Foundation
import StoreKit
import SwiftData
import SwiftUI

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
    @Published var subscriptionStartDate: Date?
    @Published var subscriptionEndDate: Date?
    @Published var trialStartDate: Date?
    @Published var daysLeft: Int = 0

    // StoreKit 产品
    @Published var monthlyProduct: Product?
    @Published var isLoading = false
    @Published var errorMessage: String?
    // 首次同步完成标记：用于避免主界面与订阅界面在启动时来回闪烁
    @Published var hasLoadedOnce = false

    private var updateListenerTask: Task<Void, Error>?
    private let networkService = NetworkService.shared
    private let authService = AuthenticationService.shared

    private init() {
        LoggerService.shared.info(module: "SubscriptionService", message: "订阅服务初始化")
        // 启动时开始监听交易更新
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
                    // 交易验证成功，从 verificationResult 获取 JWS 字符串
                    let transactionJWS = verificationResult.jwsRepresentation
                    // 加密记录 JWS（敏感信息）
                    LoggerService.shared.info(
                        module: "SubscriptionService", message: "交易 JWS: \(transactionJWS)")
                    // 发送到服务器验证
                    let success = await verifyTransactionWithServer(
                        transactionJWS: transactionJWS, transaction: transaction)
                    if success {
                        await transaction.finish()
                        // 更新订阅状态
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

    // MARK: - 验证交易（发送到服务器）
    private func verifyTransactionWithServer(
        transactionJWS: String, transaction: StoreKit.Transaction
    ) async -> Bool {
        guard let appleUserId = authService.appleUserId else {
            errorMessage = "无法获取 Apple 用户 ID"
            LoggerService.shared.error(module: "SubscriptionService", message: "无法获取 Apple 用户 ID")
            return false
        }

        // 加密记录 Apple 用户 ID（敏感信息）
        LoggerService.shared.info(
            module: "SubscriptionService", message: "Apple 用户 ID: \(appleUserId)")

        // 从 JWS 中提取环境信息
        let environment = extractEnvironment(from: transactionJWS)
        LoggerService.shared.info(
            module: "SubscriptionService", message: "交易环境: \(environment ?? "未知")")

        do {
            LoggerService.shared.info(module: "SubscriptionService", message: "开始向服务器验证交易")
            let response = try await networkService.verifyJWS(
                transactionJWS: transactionJWS,
                appleUserId: appleUserId,
                environment: environment
            )

            // 更新订阅状态
            updateStatus(from: response)

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

    // MARK: - 从 VerificationResult 获取原始 JWS 字符串
    // VerificationResult 有 jwsRepresentation 属性，可以直接获取原始 JWS
    nonisolated private func getJWSString(from result: VerificationResult<StoreKit.Transaction>)
        -> String?
    {
        // VerificationResult 有 jwsRepresentation 属性，可以直接获取原始 JWS 字符串
        return result.jwsRepresentation
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
            let environment = payload["environment"] as? String
        else {
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
        LoggerService.shared.info(module: "SubscriptionService", message: "开始同步订阅状态")
        guard let appleUserId = authService.appleUserId else {
            LoggerService.shared.warning(
                module: "SubscriptionService", message: "无法获取 Apple 用户 ID，跳过同步")
            return
        }

        // 加密记录 Apple 用户 ID
        LoggerService.shared.info(module: "SubscriptionService", message: "同步用户 ID: \(appleUserId)")
        isLoading = true

        do {
            // 获取当前有效的交易
            var jwsList: [String] = []
            for await result in Transaction.currentEntitlements {
                // 直接从 VerificationResult 获取原始 JWS 字符串
                if let jws = getJWSString(from: result), !jws.isEmpty {
                    jwsList.append(jws)
                } else {
                    LoggerService.shared.warning(
                        module: "SubscriptionService", message: "无法获取交易 JWS，跳过该交易")
                }
            }

            LoggerService.shared.info(
                module: "SubscriptionService", message: "找到 \(jwsList.count) 个本地交易")

            if jwsList.isEmpty {
                // 没有本地交易，直接查询服务器状态
                LoggerService.shared.info(module: "SubscriptionService", message: "无本地交易，查询服务器状态")
                await querySubscriptionStatus()
            } else {
                // 加密记录交易列表
                LoggerService.shared.info(
                    module: "SubscriptionService",
                    message: "交易 JWS 列表: \(jwsList.joined(separator: ","))")
                // 批量同步交易
                let environment = extractEnvironment(from: jwsList.first ?? "")
                let response = try await networkService.syncSubscriptions(
                    transactionJWSList: jwsList,
                    appleUserId: appleUserId,
                    environment: environment
                )

                updateStatus(from: response)

                if response.status == "success" {
                    LoggerService.shared.info(
                        module: "SubscriptionService",
                        message: "订阅同步成功，状态: \(subscriptionStatus.rawValue)")
                } else {
                    LoggerService.shared.warning(
                        module: "SubscriptionService",
                        message: "订阅同步失败: \(response.message ?? "未知错误")")
                    // 同步失败时，尝试查询状态
                    await querySubscriptionStatus()
                }
            }
        } catch {
            LoggerService.shared.error(
                module: "SubscriptionService", message: "同步订阅失败: \(error.localizedDescription)")
            // 同步失败时，尝试查询状态
            await querySubscriptionStatus()
        }

        isLoading = false
        // 标记已完成至少一次同步
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
        // 加密记录 Apple 用户 ID
        LoggerService.shared.info(module: "SubscriptionService", message: "查询用户 ID: \(appleUserId)")

        do {
            let response = try await networkService.getSubscriptionStatus(appleUserId: appleUserId)
            updateStatus(from: response)
            LoggerService.shared.info(
                module: "SubscriptionService",
                message: "查询订阅状态成功，状态: \(subscriptionStatus.rawValue)")
            // 标记已完成至少一次查询
            hasLoadedOnce = true
        } catch {
            LoggerService.shared.error(
                module: "SubscriptionService", message: "查询订阅状态失败: \(error.localizedDescription)")
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

        let formatter = ISO8601DateFormatter()

        // 保存订阅开始日期
        if let startDateString = response.subscriptionStartDate {
            subscriptionStartDate = formatter.date(from: startDateString)
        }

        // 保存订阅结束日期
        if let endDateString = response.subscriptionEndDate {
            subscriptionEndDate = formatter.date(from: endDateString)
        }

        // 保存试用期开始日期
        if let trialDateString = response.trialStartDate {
            trialStartDate = formatter.date(from: trialDateString)
        } else {
            // 如果后端返回 null，表示从未使用过试用期
            trialStartDate = nil
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

            await MainActor.run {
                LoggerService.shared.info(module: "SubscriptionService", message: "开始监听交易更新")
            }

            for await result in Transaction.updates {
                await MainActor.run {
                    LoggerService.shared.info(module: "SubscriptionService", message: "收到交易更新通知")
                }

                // 直接从 VerificationResult 获取原始 JWS 字符串
                guard let transactionJWS = self.getJWSString(from: result) else {
                    await MainActor.run {
                        LoggerService.shared.warning(
                            module: "SubscriptionService", message: "无法获取交易 JWS，跳过该交易")
                    }
                    continue
                }

                // 加密记录交易 JWS
                await MainActor.run {
                    LoggerService.shared.info(
                        module: "SubscriptionService", message: "更新交易 JWS: \(transactionJWS)")
                }

                // 获取 Transaction 对象用于后续操作
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

                // 验证并更新状态
                let success = await self.verifyTransactionWithServer(
                    transactionJWS: transactionJWS, transaction: transaction)
                if success {
                    // 完成交易
                    await transaction.finish()

                    // 更新订阅状态
                    await self.updateSubscriptionStatus()

                    await MainActor.run {
                        LoggerService.shared.info(
                            module: "SubscriptionService", message: "交易更新处理完成")
                    }
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
        LoggerService.shared.info(module: "SubscriptionService", message: "开始恢复购买")
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()
            LoggerService.shared.info(module: "SubscriptionService", message: "AppStore 同步成功")
            // 同步订阅状态
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

    /// 判断用户是否已使用过试用期
    /// 如果 trialStartDate 不为 nil，说明用户曾经使用过试用期
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

// MARK: - String 扩展（Base64URL 解码）
extension String {
    var base64URLDecoded: String {
        var base64 =
            self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // 添加填充
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(
                toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }

        return base64
    }
}
