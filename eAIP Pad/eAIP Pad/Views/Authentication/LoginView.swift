import SwiftUI
import AuthenticationServices

// MARK: - 登录视图
struct LoginView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var showingError = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景渐变（适配夜间模式）
                LinearGradient(
                    gradient: Gradient(colors: [
                        colorScheme == .dark ? Color(red: 0.05, green: 0.15, blue: 0.25) : Color(red: 0.5, green: 0.8, blue: 1.0),
                        colorScheme == .dark ? Color(red: 0.0, green: 0.1, blue: 0.2) : Color(red: 0.0, green: 0.48, blue: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer(minLength: geometry.size.height * 0.05)
                    
                    // 应用图标和标题
                    VStack(spacing: 16) {
                        // 应用图标
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "airplane.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 6) {
                            Text("eAIP Pad")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("专业中国eAIP航图阅读器")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    // 功能介绍卡片（紧凑版）
                    VStack(spacing: 12) {
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
                    
                    Spacer(minLength: 20)
                    
                    // 登录按钮区域
                    VStack(spacing: 16) {
                        // Apple Sign In 按钮（中文）
                        Button {
                            Task {
                                await authService.signInWithApple()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if authService.authenticationState == .authenticating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .primaryBlue))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "applelogo")
                                        .font(.title3)
                                }
                                
                                Text(authService.authenticationState == .authenticating ? "登录中..." : "使用 Apple 账号登录")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(colorScheme == .dark ? Color.white.opacity(0.2) : .white)
                            .foregroundColor(colorScheme == .dark ? .white : .primaryBlue)
                            .cornerRadius(25)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        }
                        .disabled(authService.authenticationState == .authenticating)
                        
                        // 隐私说明
                        VStack(spacing: 6) {
                            Text("登录即表示您同意我们的")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            
                            HStack(spacing: 4) {
                                    Button("服务条款") {
                                        if let url = URL(string: "https://github.com/star-reader/eAIP-Pad-FrontEnd/wiki/Terms-of-Service") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                    
                                    Text("和")
                                    
                                    Button("隐私政策") {
                                        if let url = URL(string: "https://github.com/star-reader/eAIP-Pad-FrontEnd/wiki/Privacy-Policy") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                            }
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: geometry.size.height * 0.05)
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
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(colorScheme == .dark ? .white : .primaryBlue)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.9))
        .cornerRadius(12)
    }
}

#Preview("Login") {
    LoginView()
}