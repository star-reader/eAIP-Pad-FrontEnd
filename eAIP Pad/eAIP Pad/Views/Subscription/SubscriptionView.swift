import SwiftUI
import StoreKit

// MARK: - 订阅视图
struct SubscriptionView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showingError = false
    @State private var errorMessage = ""
    
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
                
                // 价格信息（写死）
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("¥15")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(Color.primaryBlue)
                        
                        Text("每月")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                
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
                    // .glassEffect()
                    
                    Text("订阅将自动续费，可随时取消")
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
    private func purchaseSubscription() async {
        let success = await subscriptionService.purchaseMonthlySubscription()
        
        if !success {
            await MainActor.run {
                errorMessage = subscriptionService.errorMessage ?? "发生错误，请稍后重试"
                showingError = true
            }
        }
    }
    
    // MARK: - 恢复购买
    private func restorePurchases() async {
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
