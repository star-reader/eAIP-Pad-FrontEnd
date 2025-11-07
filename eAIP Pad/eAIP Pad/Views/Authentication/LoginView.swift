import SwiftUI
import AuthenticationServices

// MARK: - 轮播项数据
struct CarouselItem: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let description: String
}

// MARK: - 登录视图
struct LoginView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var showingError = false
    @State private var currentPage = 0
    @Environment(\.colorScheme) private var colorScheme
    
    // 定义轮播数据
    private let carouselItems: [CarouselItem] = [
        CarouselItem(
            imageName: "terminal",
            title: "机场航图",
            description: "国内AIP公开机场完整航图"
        ),
        CarouselItem(
            imageName: "enroute",
            title: "航路图",
            description: "eAIP航路图"
        ),
        CarouselItem(
            imageName: "area",
            title: "区域图",
            description: "北京、上海、广州等空域对应区域图"
        ),
        CarouselItem(
            imageName: "ad",
            title: "机场细则",
            description: "查看机场细则文档"
        ),
        CarouselItem(
            imageName: "aip",
            title: "AIP文档",
            description: "AIP、SUP、NOTAM文档阅读"
        ),   
        
    ]
    
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
                
                VStack(spacing: 20) {
                    // 应用标题
                    VStack(spacing: 6) {
                        Spacer().frame(height: 30)
                        Text("eAIP Pad")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("专业中国eAIP航图阅读器")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    // 轮播视图
                    CarouselView(items: carouselItems, currentPage: $currentPage)
                        .frame(height: geometry.size.height * 0.6)
                        .padding(.horizontal)
                    
                    Spacer(minLength: 10)
                    
                    // 登录按钮区域
                    VStack(spacing: 16) {
                        // Apple Sign In 按钮
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
                    
                    Spacer(minLength: geometry.size.height * 0.02)
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

// MARK: - 轮播视图
struct CarouselView: View {
    let items: [CarouselItem]
    @Binding var currentPage: Int
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // TabView 实现轮播
            TabView(selection: $currentPage) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    CarouselItemView(item: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onAppear {
                startAutoScroll()
            }
            .onDisappear {
                stopAutoScroll()
            }
            
            // 自定义页面指示器
            HStack(spacing: 8) {
                ForEach(0..<items.count, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                }
            }
            .padding(.top, 12)
        }
    }
    
    private func startAutoScroll() {
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentPage = (currentPage + 1) % items.count
            }
        }
    }
    
    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - 轮播项视图
struct CarouselItemView: View {
    let item: CarouselItem
    
    var body: some View {
        VStack(spacing: 16) {
            // 图片容器，保持固定高度
            GeometryReader { geometry in
                Image(item.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 5)
            }
            
            // 文字说明
            VStack(spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(item.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal)
            .frame(height: 60)
        }
        .padding(.horizontal, 4)
    }
}

#Preview("Login") {
    LoginView()
}
