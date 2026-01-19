import Foundation

// MARK: - 订阅状态枚举
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

// MARK: - IAP 请求模型
struct VerifyJWSRequest: Codable {
    let transactionJWS: String
    let appleUserId: String
    let environment: String?

    enum CodingKeys: String, CodingKey {
        case transactionJWS = "transaction_jws"
        case appleUserId = "apple_user_id"
        case environment
    }
}

struct SyncSubscriptionRequest: Codable {
    let transactionJWSList: [String]
    let appleUserId: String
    let environment: String?

    enum CodingKeys: String, CodingKey {
        case transactionJWSList = "transaction_jws_list"
        case appleUserId = "apple_user_id"
        case environment
    }
}

// MARK: - IAP 响应模型
struct VerifyJWSResponse: Codable {
    let status: String
    let subscriptionStatus: String?
    let subscriptionStartDate: String?
    let subscriptionEndDate: String?
    let trialStartDate: String?
    let autoRenew: Bool?
    let productId: String?
    let originalTransactionId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case subscriptionStatus = "subscription_status"
        case subscriptionStartDate = "subscription_start_date"
        case subscriptionEndDate = "subscription_end_date"
        case trialStartDate = "trial_start_date"
        case autoRenew = "auto_renew"
        case productId = "product_id"
        case originalTransactionId = "original_transaction_id"
        case message
    }
}

struct SyncSubscriptionResponse: Codable {
    let status: String
    let subscriptionStatus: String?
    let subscriptionStartDate: String?
    let subscriptionEndDate: String?
    let trialStartDate: String?
    let autoRenew: Bool?
    let productId: String?
    let syncedCount: Int?
    let totalCount: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case subscriptionStatus = "subscription_status"
        case subscriptionStartDate = "subscription_start_date"
        case subscriptionEndDate = "subscription_end_date"
        case trialStartDate = "trial_start_date"
        case autoRenew = "auto_renew"
        case productId = "product_id"
        case syncedCount = "synced_count"
        case totalCount = "total_count"
        case message
    }
}

struct SubscriptionStatusResponse: Codable {
    let status: String
    let subscriptionStartDate: String?
    let subscriptionEndDate: String?
    let trialStartDate: String?
    let autoRenew: Bool?
    let productId: String?
    let originalTransactionId: String?
    let environment: String?
    let daysLeft: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case subscriptionStartDate = "subscription_start_date"
        case subscriptionEndDate = "subscription_end_date"
        case trialStartDate = "trial_start_date"
        case autoRenew = "auto_renew"
        case productId = "product_id"
        case originalTransactionId = "original_transaction_id"
        case environment
        case daysLeft = "days_left"
    }
}
