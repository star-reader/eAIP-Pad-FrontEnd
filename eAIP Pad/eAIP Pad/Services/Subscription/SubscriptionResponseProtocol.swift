import Foundation

// MARK: - 订阅响应协议
protocol SubscriptionResponseProtocol {
    var subscriptionStatus: String? { get }
    var subscriptionStartDate: String? { get }
    var subscriptionEndDate: String? { get }
    var trialStartDate: String? { get }
    var daysLeft: Int? { get }
}

// MARK: - 让现有响应类型遵循协议
extension VerifyJWSResponse: SubscriptionResponseProtocol {
    var daysLeft: Int? { nil }
}

extension SyncSubscriptionResponse: SubscriptionResponseProtocol {
    var daysLeft: Int? { nil }
}

extension SubscriptionStatusResponse: SubscriptionResponseProtocol {
    var subscriptionStatus: String? { status }
}
