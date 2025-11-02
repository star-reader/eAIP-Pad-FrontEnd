import SwiftUI
import StoreKit

/// 统一订阅页面
struct UnifiedSubscriptionView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color.primaryBlue.opacity(0.05)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: 40)
                        
                        // 标题和图标
                        VStack(spacing: 16) {
                            Image(systemName: "airplane.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(Color.primaryBlue)
                            
                            VStack(spacing: 8) {
                                Text("订阅 eAIP Pad 专业版")
                                    .font(.title)
                                    .fontWeight(.bold)
                                
                                Text("解锁所有航图和专业功能")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 功能列表
                        VStack(spacing: 16) {
                            FeatureRow(icon: "map.fill", text: "完整航图库")
                            FeatureRow(icon: "pencil.tip.crop.circle.fill", text: "专业标注工具")
                            FeatureRow(icon: "pin.fill", text: "智能收藏夹")
                            FeatureRow(icon: "arrow.clockwise.circle.fill", text: "自动更新")
                            FeatureRow(icon: "icloud.fill", text: "云端同步")
                        }
                        .padding(.horizontal)
                        
                        // 价格信息卡片
                        if let product = subscriptionService.monthlyProduct {
                            VStack(spacing: 16) {
                                VStack(spacing: 8) {
                                    // 检查是否有试用期优惠且用户未使用过试用期
                                    if let subscription = product.subscription,
                                       subscription.introductoryOffer != nil,
                                       !subscriptionService.hasUsedTrial {
                                        Text("首月免费")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.primaryBlue)
                                        
                                        Text("然后 \(product.displayPrice)/月")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(product.displayPrice)/月")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.primaryBlue)
                                    }
                                    
                                    Text("自动续费订阅")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }
                            .padding(.horizontal)
                        } else {
                            // 产品未加载时的占位
                            VStack(spacing: 8) {
                                if subscriptionService.isLoading {
                                    ProgressView()
                                } else {
                                    Text("加载中...")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                        }
                        
                        // 订阅按钮
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await purchaseSubscription()
                                }
                            } label: {
                                HStack {
                                    if isLoading || subscriptionService.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    }
                                    
                                    Text(isLoading || subscriptionService.isLoading ? "处理中..." : "开始订阅")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.primaryBlue)
                                .cornerRadius(12)
                            }
                            .disabled(isLoading || subscriptionService.isLoading)
                            
                            Button {
                                Task {
                                    await restorePurchases()
                                }
                            } label: {
                                Text("恢复购买")
                                    .foregroundColor(.secondary)
                            }
                            .disabled(isLoading || subscriptionService.isLoading)
                            
                            if let product = subscriptionService.monthlyProduct {
                                Text(subscriptionService.hasUsedTrial 
                                    ? "订阅可随时取消，按 \(product.displayPrice)/月 自动续费"
                                    : "订阅可随时取消，首月免费后按 \(product.displayPrice)/月 自动续费")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("订阅")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("订阅失败", isPresented: $showingError) {
            Button("确定", role: .cancel) {
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
        errorMessage = ""
        
        let success = await subscriptionService.purchaseMonthlySubscription()
        
        await MainActor.run {
            if success {
                // 购买成功，显示成功提示并关闭页面
                print("✅ 订阅购买成功")
                // 这里可以添加成功提示，然后自动关闭
                // 页面会自动关闭因为订阅状态已更新
            } else {
                errorMessage = subscriptionService.errorMessage ?? "订阅失败，请稍后重试"
                showingError = true
            }
            isLoading = false
        }
    }
    
    // MARK: - 恢复购买
    private func restorePurchases() async {
        isLoading = true
        errorMessage = ""
        
        await subscriptionService.restorePurchases()
        
        if let error = subscriptionService.errorMessage {
            await MainActor.run {
                errorMessage = error
                showingError = true
            }
        } else {
            print("✅ 恢复购买成功")
        }
        
        isLoading = false
    }
}

// MARK: - 功能行
struct FeatureRow: View {
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

#Preview("Unified Subscription View") {
    UnifiedSubscriptionView()
}