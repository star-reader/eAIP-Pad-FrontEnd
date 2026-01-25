import SwiftUI

struct SubscriptionStatusCard: View {
    @ObservedObject var subscriptionService: SubscriptionService
    let onSubscribe: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("订阅状态")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(subscriptionService.subscriptionDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: subscriptionService.hasValidSubscription ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(subscriptionService.hasValidSubscription ? .green : .orange)
                    
                    if subscriptionService.daysLeft > 0 {
                        Text("\(subscriptionService.daysLeft) 天")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            
            if let endDate = subscriptionService.subscriptionEndDate {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("续费日期: \(formatDate(endDate).components(separatedBy: " ").first ?? formatDate(endDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            if subscriptionService.subscriptionStatus == .trial && subscriptionService.daysLeft > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("免费试用还剩 \(subscriptionService.daysLeft) 天过期")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            if !subscriptionService.hasValidSubscription && subscriptionService.subscriptionStatus != .trial {
                Button("立即订阅") {
                    onSubscribe()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            Task {
                await subscriptionService.querySubscriptionStatus()
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

struct SubscriptionStatusCardPreview: View {
    let status: AppSubscriptionStatus
    let daysLeft: Int
    let startDate: Date?
    let endDate: Date?
    let onSubscribe: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("订阅状态")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(subscriptionDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: status.isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(status.isValid ? .green : .orange)
                }
            }
            
            if let endDate = endDate {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)    
                    Text("续费时间: \(formatDate(endDate).components(separatedBy: " ").first ?? "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            if status == .trial && daysLeft > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("免费试用还剩 \(daysLeft) 天过期")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            if !status.isValid && status != .trial {
                Button("立即订阅") {
                    onSubscribe()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var subscriptionDescription: String {
        switch status {
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

#Preview("订阅状态 - 试用期", traits: .sizeThatFitsLayout) {
    SubscriptionStatusCardPreview(
        status: .trial,
        daysLeft: 5,
        startDate: Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
        onSubscribe: { print("订阅按钮点击") }
    )
    .padding()
}

#Preview("订阅状态 - 已订阅", traits: .sizeThatFitsLayout) {
    SubscriptionStatusCardPreview(
        status: .active,
        daysLeft: 25,
        startDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()),
        endDate: Calendar.current.date(byAdding: .day, value: 25, to: Date()),
        onSubscribe: { print("订阅按钮点击") }
    )
    .padding()
}

#Preview("订阅状态 - 未订阅", traits: .sizeThatFitsLayout) {
    SubscriptionStatusCardPreview(
        status: .inactive,
        daysLeft: 0,
        startDate: nil,
        endDate: nil,
        onSubscribe: { print("订阅按钮点击") }
    )
    .padding()
}
