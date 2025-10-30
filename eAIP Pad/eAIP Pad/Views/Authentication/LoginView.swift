import SwiftUI
import AuthenticationServices

// MARK: - 登录视图
struct LoginView: View {
    @State private var authService = AuthenticationService.shared
    @State private var showingError = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景渐变
                LinearGradient.skyGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 40) {
                        Spacer(minLength: geometry.size.height * 0.1)
                        
                        // 应用图标和标题
                        VStack(spacing: 24) {
                            // 应用图标
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.2))
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: "airplane.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(spacing: 8) {
                                Text("eAIP Pad")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("专业中国eAIP航图阅读器")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // 功能介绍卡片
                        VStack(spacing: 16) {
                            FeatureCard(
                                icon: "map.fill",
                                title: "完整航图库",
                                description: "中国所有机场的SID、STAR、进近和机场图"
                            )
                            
                            FeatureCard(
                                icon: "pencil.tip.crop.circle.fill",
                                title: "专业标注",
                                description: "Apple Pencil支持，标注永久保存"
                            )
                            
                            FeatureCard(
                                icon: "arrow.clockwise.circle.fill",
                                title: "自动更新",
                                description: "AIRAC版本自动同步，确保数据最新"
                            )
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                        
                        // 登录按钮区域
                        VStack(spacing: 20) {
                            // Apple Sign In 按钮
                            SignInWithAppleButton(
                                onRequest: { request in
                                    request.requestedScopes = [.fullName, .email]
                                },
                                onCompletion: { result in
                                    // 处理结果在 AuthenticationService 中
                                }
                            )
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 50)
                            .cornerRadius(25)
                            .disabled(authService.authenticationState == .authenticating)
                            
                            // 或者使用自定义按钮
                            Button {
                                Task {
                                    await authService.signInWithApple()
                                }
                            } label: {
                                HStack {
                                    if authService.authenticationState == .authenticating {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "applelogo")
                                            .font(.title3)
                                    }
                                    
                                    Text(authService.authenticationState == .authenticating ? "登录中..." : "使用 Apple 账号登录")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.primaryBlue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(.white)
                                .cornerRadius(25)
                            }
                            .disabled(authService.authenticationState == .authenticating)
                            
                            // 隐私说明
                            VStack(spacing: 8) {
                                Text("登录即表示您同意我们的")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                HStack {
                                    Button("服务条款") {
                                        // TODO: 打开服务条款
                                    }
                                    
                                    Text("和")
                                    
                                    Button("隐私政策") {
                                        // TODO: 打开隐私政策
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: geometry.size.height * 0.1)
                    }
                }
            }
        }
        .alert("登录失败", isPresented: $showingError) {
            Button("确定") {
                showingError = false
            }
        } message: {
            Text(authService.errorMessage ?? "未知错误")
        }
        .onChange(of: authService.authenticationState) { _, newState in
            if case .error(_) = newState {
                showingError = true
            }
        }
    }
}

// MARK: - 功能介绍卡片
struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.primaryBlue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(.white.opacity(0.9))
        .cornerRadius(12)
    }
}

// MARK: - 欢迎界面（新用户）
struct WelcomeView: View {
    let onContinue: () -> Void
    
    var body: some View {
        ZStack {
            LinearGradient.primaryBlueGradient
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // 欢迎图标
                VStack(spacing: 24) {
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 12) {
                        Text("欢迎使用 eAIP Pad")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("您的专业航图阅读伙伴")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                // 新用户福利
                VStack(spacing: 20) {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.white)
                        Text("新用户专享 30 天免费试用")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(.white.opacity(0.2))
                    .cornerRadius(12)
                    
                    Text("试用期内可免费使用所有功能")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // 继续按钮
                Button {
                    onContinue()
                } label: {
                    Text("开始使用")
                        .fontWeight(.semibold)
                        .foregroundColor(.primaryBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white)
                        .cornerRadius(25)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 50)
            }
        }
    }
}

#Preview("Login") {
    LoginView()
}

#Preview("Welcome") {
    WelcomeView {
        print("Continue tapped")
    }
}
