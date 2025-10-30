import SwiftUI
import StoreKit

// MARK: - 订阅视图
struct SubscriptionView: View {
    @State private var subscriptionService = SubscriptionService.shared
    @State private var selectedPlan: SubscriptionPlan = .monthly
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景渐变
                LinearGradient.aviationGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        Spacer(minLength: geometry.size.height * 0.05)
                        
                        // 标题区域
                        VStack(spacing: 16) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.yellow)
                            
                            VStack(spacing: 8) {
                                Text("解锁完整功能")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("专业航图阅读体验")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        
                        // 功能列表
                        VStack(spacing: 16) {
                            SubscriptionFeature(
                                icon: "map.fill",
                                title: "完整航图库",
                                description: "访问中国所有机场的SID、STAR、进近和机场图"
                            )
                            
                            SubscriptionFeature(
                                icon: "pencil.tip.crop.circle.fill",
                                title: "专业标注工具",
                                description: "Apple Pencil支持，标注永久保存到云端"
                            )
                            
                            SubscriptionFeature(
                                icon: "pin.fill",
                                title: "智能收藏夹",
                                description: "快速访问常用航图，支持多种显示样式"
                            )
                            
                            SubscriptionFeature(
                                icon: "arrow.clockwise.circle.fill",
                                title: "自动更新",
                                description: "AIRAC版本自动同步，确保数据始终最新"
                            )
                            
                            SubscriptionFeature(
                                icon: "icloud.fill",
                                title: "云端同步",
                                description: "标注和收藏在所有设备间自动同步"
                            )
                        }
                        .padding(.horizontal)
                        
                        // 订阅计划选择
                        VStack(spacing: 20) {
                            Text("选择订阅计划")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            VStack(spacing: 12) {
                                // 月度订阅
                                SubscriptionPlanCard(
                                    plan: .monthly,
                                    isSelected: selectedPlan == .monthly,
                                    onSelect: { selectedPlan = .monthly }
                                )
                                
                                // 年度订阅（如果有的话）
                                if subscriptionService.availableProducts.count > 1 {
                                    SubscriptionPlanCard(
                                        plan: .yearly,
                                        isSelected: selectedPlan == .yearly,
                                        onSelect: { selectedPlan = .yearly }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // 新用户优惠
                        if AuthenticationService.shared.isNewUser {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "gift.fill")
                                        .foregroundColor(.yellow)
                                    Text("新用户专享")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                                
                                Text("首月免费试用")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("试用期内可随时取消")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding()
                            .background(.yellow.opacity(0.2))
                            .cornerRadius(16)
                            .padding(.horizontal)
                        }
                        
                        // 订阅按钮
                        VStack(spacing: 16) {
                            Button {
                                Task {
                                    await purchaseSubscription()
                                }
                            } label: {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: Color.primaryBlue))
                                            .scaleEffect(0.8)
                                    }
                                    
                                    Text(isLoading ? "处理中..." : "开始订阅")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(Color.primaryBlue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(.white)
                                .cornerRadius(25)
                            }
                            .disabled(isLoading)
                            
                            // 恢复购买
                            Button("恢复购买") {
                                Task {
                                    await restorePurchases()
                                }
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .disabled(isLoading)
                        }
                        .padding(.horizontal)
                        
                        // 法律信息
                        VStack(spacing: 8) {
                            Text("订阅将自动续费，可随时在设置中取消")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                            
                            HStack {
                                Button("服务条款") {
                                    // TODO: 打开服务条款
                                }
                                
                                Text("•")
                                
                                Button("隐私政策") {
                                    // TODO: 打开隐私政策
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: geometry.size.height * 0.05)
                    }
                }
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
    private func purchaseSubscription() async {
        isLoading = true
        
        let success = await subscriptionService.purchaseMonthlySubscription()
        
        if !success {
            await MainActor.run {
                errorMessage = "购买失败，请稍后重试"
                showingError = true
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    // MARK: - 恢复购买
    private func restorePurchases() async {
        isLoading = true
        
        do {
            try await AppStore.sync()
            await subscriptionService.updateSubscriptionStatus()
        } catch {
            await MainActor.run {
                errorMessage = "恢复购买失败: \(error.localizedDescription)"
                showingError = true
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - 订阅功能卡片
struct SubscriptionFeature: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
        }
        .padding()
        .background(.white.opacity(0.1))
        .cornerRadius(12)
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
