import SwiftUI
import StoreKit

// MARK: - 订阅视图（根据状态显示不同内容）
struct SubscriptionView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Group {
            // 根据订阅状态显示不同视图
            if subscriptionService.subscriptionStatus == .inactive {
                // 未订阅状态：使用 LoginView 中的 WelcomeView
                WelcomeView {
                    Task {
                        await startTrial()
                    }
                }
            } else {
                // 过期状态：显示升级页面
                SubscriptionUpgradeView(
                    subscriptionService: subscriptionService,
                    showingError: $showingError,
                    errorMessage: $errorMessage
                )
            }
        }
        .alert("提示", isPresented: $showingError) {
            Button("确定", role: .cancel) {
                showingError = false
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - 开始试用
    private func startTrial() async {
        let success = await subscriptionService.startTrial()
        
        if !success {
            await MainActor.run {
                errorMessage = subscriptionService.errorMessage ?? "开启试用失败，请稍后重试"
                showingError = true
            }
        }
    }
}

// MARK: - 订阅升级视图
struct SubscriptionUpgradeView: View {
    @ObservedObject var subscriptionService: SubscriptionService
    @Binding var showingError: Bool
    @Binding var errorMessage: String
    
    // 获取订阅价格显示（如果有试用期，显示首月免费）
    private var priceDisplay: String {
        if let product = subscriptionService.monthlyProduct {
            // 检查是否有试用期优惠
            if let subscription = product.subscription, subscription.introductoryOffer != nil {
                // 有试用期，显示首月免费，然后正常价格
                return "首月免费，然后 \(product.displayPrice)/月"
            } else {
                // 没有试用期，直接显示价格
                return "\(product.displayPrice)/月"
            }
        }
        return "¥18/月"
    }
    
    var body: some View {
        ZStack {
            // 简洁的背景
            Color.primaryBlue.opacity(0.1)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // 简洁的标题
                VStack(spacing: 16) {
                    Image(systemName: "airplane.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(Color.primaryBlue)
                    
                    VStack(spacing: 8) {
                        Text("升级到专业版")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("解锁所有航图和专业功能")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 简洁的功能列表
                VStack(spacing: 12) {
                    SimpleFeature(icon: "map.fill", text: "完整航图库")
                    SimpleFeature(icon: "pencil.tip.crop.circle.fill", text: "专业标注工具")
                    SimpleFeature(icon: "pin.fill", text: "智能收藏夹")
                    SimpleFeature(icon: "arrow.clockwise.circle.fill", text: "自动更新")
                    SimpleFeature(icon: "icloud.fill", text: "云端同步")
                }
                .padding(.horizontal)
                
                // 价格信息卡片
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text(priceDisplay)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color.primaryBlue)
                        
                        Text("自动续费订阅")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
                
                Spacer()
                
                // 简洁的按钮
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await purchaseSubscription()
                        }
                    } label: {
                        HStack {
                            if subscriptionService.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            
                            Text(subscriptionService.isLoading ? "处理中..." : "开始订阅")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.primaryBlue)
                        .cornerRadius(12)
                    }
                    .disabled(subscriptionService.isLoading)
                    
                    Button("恢复购买") {
                        Task {
                            await restorePurchases()
                        }
                    }
                    .foregroundColor(.secondary)
                    .disabled(subscriptionService.isLoading)
                    
                    Text("订阅可随时取消，首月免费后按 \(subscriptionService.monthlyProduct?.displayPrice ?? "¥18")/月 自动续费")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .alert("订阅失败", isPresented: $showingError) {
            Button("确定") {
                showingError = false
            }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            Task {
                await subscriptionService.loadProducts()
            }
        }
    }
    
    // MARK: - 购买订阅
    func purchaseSubscription() async {
        let success = await subscriptionService.purchaseMonthlySubscription()
        
        if !success {
            await MainActor.run {
                errorMessage = subscriptionService.errorMessage ?? "发生错误，请稍后重试"
                showingError = true
            }
        }
    }
    
    // MARK: - 恢复购买
    func restorePurchases() async {
        await subscriptionService.restorePurchases()
        
        if let error = subscriptionService.errorMessage {
            await MainActor.run {
                errorMessage = error
                showingError = true
            }
        }
    }
}

// MARK: - 简洁功能项
struct SimpleFeature: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color.primaryBlue)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundColor(.green)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 订阅套餐选择卡片
struct SubscriptionPlanSelectionCard: View {
    let title: String
    let description: String
    let price: String
    let productID: String
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 16) {
                // 选择指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? Color.primaryBlue : .gray)
                    .frame(width: 28)
                
                // 套餐信息
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(price)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Color.primaryBlue)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.primaryBlue.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.primaryBlue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 订阅计划枚举
enum SubscriptionPlan {
    case monthly
    case yearly
    
    var title: String {
        switch self {
        case .monthly: return "月度订阅"
        case .yearly: return "年度订阅"
        }
    }
    
    var price: String {
        switch self {
        case .monthly: return "¥15/月"
        case .yearly: return "¥150/年"
        }
    }
    
    var savings: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "节省 ¥30"
        }
    }
    
    var productId: String {
        switch self {
        case .monthly: return "com.eaip.pad.monthly"
        case .yearly: return "com.eaip.pad.yearly"
        }
    }
}

// MARK: - 订阅计划卡片
struct SubscriptionPlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? Color.primaryBlue : .white)
                    
                    Text(plan.price)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? Color.primaryBlue : .white)
                    
                    if let savings = plan.savings {
                        Text(savings)
                            .font(.caption)
                            .foregroundColor(.successGreen)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? Color.primaryBlue : .white.opacity(0.5))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? .white : .white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.primaryBlue : .white.opacity(0.3), lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview("Subscription View") {
    SubscriptionView()
}
