import Foundation

// MARK: - 订阅状态管理器
/// 管理订阅状态的工具类
class SubscriptionStatusManager {
    
    private(set) var subscriptionStatus: AppSubscriptionStatus = .inactive
    private(set) var subscriptionStartDate: Date?
    private(set) var subscriptionEndDate: Date?
    private(set) var trialStartDate: Date?
    private(set) var daysLeft: Int = 0
    
    /// 从 VerifyJWSResponse 更新状态
    func updateStatus(from response: VerifyJWSResponse) {
        subscriptionStatus = AppSubscriptionStatus(from: response.subscriptionStatus)

        if let endDateString = response.subscriptionEndDate {
            let formatter = ISO8601DateFormatter()
            subscriptionEndDate = formatter.date(from: endDateString)
            updateDaysLeft()
        }
    }
    
    /// 从 SyncSubscriptionResponse 更新状态
    func updateStatus(from response: SyncSubscriptionResponse) {
        subscriptionStatus = AppSubscriptionStatus(from: response.subscriptionStatus)

        if let endDateString = response.subscriptionEndDate {
            let formatter = ISO8601DateFormatter()
            subscriptionEndDate = formatter.date(from: endDateString)
            updateDaysLeft()
        }
    }
    
    /// 从 SubscriptionStatusResponse 更新状态
    func updateStatus(from response: SubscriptionStatusResponse) {
        subscriptionStatus = AppSubscriptionStatus(from: response.status)

        let formatter = ISO8601DateFormatter()

        if let startDateString = response.subscriptionStartDate {
            subscriptionStartDate = formatter.date(from: startDateString)
        }

        if let endDateString = response.subscriptionEndDate {
            subscriptionEndDate = formatter.date(from: endDateString)
        }

        if let trialDateString = response.trialStartDate {
            trialStartDate = formatter.date(from: trialDateString)
        } else {
            trialStartDate = nil
        }

        if let days = response.daysLeft {
            daysLeft = days
        } else {
            updateDaysLeft()
        }
    }
    
    /// 更新剩余天数
    private func updateDaysLeft() {
        guard let endDate = subscriptionEndDate else {
            daysLeft = 0
            return
        }

        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        daysLeft = max(0, days)
    }
    
    /// 判断是否有有效订阅
    var hasValidSubscription: Bool {
        return subscriptionStatus.isValid
    }
    
    /// 判断用户是否已使用过试用期
    var hasUsedTrial: Bool {
        return trialStartDate != nil
    }
    
    /// 订阅描述
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
