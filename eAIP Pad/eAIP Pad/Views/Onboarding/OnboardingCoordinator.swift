import SwiftUI
import SwiftData
import Combine

// MARK: - 引导流程状态
enum OnboardingState {
    case loading           // 检查状态中
    case needsLogin       // 需要登录
    case newUserWelcome   // 新用户欢迎
    case needsSubscription // 需要订阅
    case subscriptionExpired // 订阅过期
    case completed        // 完成，进入主应用
}

// MARK: - 引导流程协调器
class OnboardingCoordinator: ObservableObject {
    @Published var currentState: OnboardingState = .loading
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let authService = AuthenticationService.shared
    private let subscriptionService = SubscriptionService.shared
    
    init() {
        // 先做同步检查，避免闪现
        performSyncCheck()
        
        // 然后做异步检查
        checkInitialState()
    }
    
    // MARK: - 同步检查（避免闪现）
    private func performSyncCheck() {
        // 如果已经有存储的token，先设为已认证状态
        if authService.isAuthenticated {
            print("🚀 检测到已登录用户，直接进入主应用")
            currentState = .completed
        }
    }
    
    // MARK: - 检查初始状态
    func checkInitialState() {
        // 如果已经是完成状态，不需要重新检查
        if currentState == .completed {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            await performInitialChecks()
        }
    }
    
    @MainActor
    private func performInitialChecks() async {
        
        // 1. 检查登录状态
        print("📱 检查登录状态: \(authService.isAuthenticated)")
        if !authService.isAuthenticated {
            currentState = .needsLogin
            isLoading = false
            return
        }
        
        // 2. 检查是否是新用户
        print("👤 检查是否新用户: \(authService.isNewUser)")
        if authService.isNewUser {
            currentState = .newUserWelcome
            isLoading = false
            return
        }
        
        // 3. 检查订阅状态
        await checkSubscriptionStatus()
    }
    
    @MainActor
    private func checkSubscriptionStatus() async {
        do {
            // 添加超时保护，避免卡住
            try await withTimeout(seconds: 5) {
                await self.subscriptionService.updateSubscriptionStatus()
            }
            
            print("📊 订阅状态: \(subscriptionService.subscriptionStatus)")
            
            switch subscriptionService.subscriptionStatus {
            case .trial, .active:
                // 有效订阅，进入主应用
                currentState = .completed
                
            case .expired:
                // 订阅过期
                currentState = .subscriptionExpired
                
            case .inactive:
                // 未订阅
                currentState = .needsSubscription
            }
        } catch {
            // 如果订阅检查失败，也允许用户进入应用（降级方案）
            currentState = .completed
        }
        
        isLoading = false
    }
    
    // 超时辅助函数
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - 处理登录完成
    func handleLoginCompleted() {
        Task {
            await MainActor.run {
                if authService.isNewUser {
                    currentState = .newUserWelcome
                } else {
                    isLoading = true
                }
            }
            
            if !authService.isNewUser {
                await checkSubscriptionStatus()
            }
        }
    }
    
    // MARK: - 处理新用户欢迎完成（开始试用）
    func handleWelcomeCompleted() {
        Task {
            await startTrialForNewUser()
        }
    }
    
    @MainActor
    private func startTrialForNewUser() async {
        isLoading = true
        
        do {
            // 获取当前用户ID（从 accessToken 或其他方式）
            guard let userId = getCurrentUserId() else {

                currentState = .needsSubscription
                isLoading = false
                return
            }
            

            let response = try await NetworkService.shared.startTrial(userId: userId)
            
            
            switch response.data.status {
            case "trial_started":

                // 更新订阅服务状态
                await subscriptionService.updateSubscriptionStatus()
                currentState = .completed
                
            case "trial_used", "trial_expired":

                currentState = .needsSubscription
                
            default:

                currentState = .needsSubscription
            }
        } catch {

            // 试用期启动失败，跳转到订阅页面
            currentState = .needsSubscription
        }
        
        isLoading = false
    }
    
    // 获取当前用户ID的辅助方法
    private func getCurrentUserId() -> String? {
        // 这里可以从 AuthenticationService 获取用户ID
        // 或者从 JWT token 中解析用户ID
        // 暂时使用一个模拟的用户ID
        return authService.currentUser?.accessToken.hashValue.description
    }
    
    // MARK: - 处理订阅完成
    func handleSubscriptionCompleted() {
        Task {
            await checkSubscriptionStatus()
        }
    }
    
    // MARK: - 重试
    func retry() {
        checkInitialState()
    }
}

// MARK: - 引导流程主视图
struct OnboardingFlow: View {
    @StateObject private var coordinator = OnboardingCoordinator()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            switch coordinator.currentState {
            case .loading:
                LoadingView()
                
            case .needsLogin:
                LoginView()
                    .onReceive(AuthenticationService.shared.$authenticationState) { state in
                        if state == .authenticated {
                            coordinator.handleLoginCompleted()
                        }
                    }
                
            case .newUserWelcome:
                WelcomeView {
                    coordinator.handleWelcomeCompleted()
                }
                
            case .needsSubscription:
                SubscriptionView()
                    .onReceive(SubscriptionService.shared.$subscriptionStatus) { status in
                        if status.isValid {
                            coordinator.handleSubscriptionCompleted()
                        }
                    }
                
            case .subscriptionExpired:
                SubscriptionExpiredView {
                    coordinator.handleSubscriptionCompleted()
                }
                
            case .completed:
                MainAppView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.currentState)
        .alert("错误", isPresented: .constant(coordinator.errorMessage != nil)) {
            Button("重试") {
                coordinator.retry()
            }
            Button("取消", role: .cancel) {
                coordinator.errorMessage = nil
            }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
    }
}

// MARK: - 加载视图
struct LoadingView: View {
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            LinearGradient.skyGradient
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // 旋转的飞机图标
                Image(systemName: "airplane")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(rotationAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
                
                VStack(spacing: 12) {
                    Text("eAIP Pad")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("正在检查登录状态...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        }
    }
}

// MARK: - 订阅过期视图
struct SubscriptionExpiredView: View {
    let onRenew: () -> Void
    
    var body: some View {
        ZStack {
            LinearGradient.primaryBlueGradient
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // 过期图标
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.warningOrange)
                    
                    VStack(spacing: 12) {
                        Text("订阅已过期")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("续订以继续使用所有功能")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                }
                
                // 过期说明
                VStack(spacing: 16) {
                    Text("您的订阅已过期，无法访问:")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ExpiredFeatureRow(text: "完整航图库")
                        ExpiredFeatureRow(text: "PDF 标注功能")
                        ExpiredFeatureRow(text: "快速访问收藏")
                        ExpiredFeatureRow(text: "AIRAC 自动更新")
                    }
                }
                .padding()
                .background(.white.opacity(0.1))
                .cornerRadius(16)
                
                Spacer()
                
                // 续订按钮
                VStack(spacing: 16) {
                    Button {
                        onRenew()
                    } label: {
                        Text("立即续订")
                            .fontWeight(.semibold)
                            .foregroundColor(.primaryBlue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white)
                            .cornerRadius(25)
                    }
                    
                    Button("稍后提醒") {
                        // TODO: 实现稍后提醒逻辑
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal)
                
                Spacer(minLength: 50)
            }
        }
    }
}

// MARK: - 过期功能行
struct ExpiredFeatureRow: View {
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.errorRed)
            Text(text)
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }
}

// MARK: - 超时错误
struct TimeoutError: Error {
    var localizedDescription: String {
        return "操作超时"
    }
}

// MARK: - 主应用视图
struct MainAppView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    
    private var currentSettings: UserSettings {
        if let settings = userSettings.first {
            return settings
        } else {
            let newSettings = UserSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }
    
    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                // iPhone: 使用 TabView
                MainTabView()
            } else {
                // iPad: 使用 Sidebar
                MainSidebarView()
            }
        }
        .preferredColorScheme(currentSettings.isDarkMode ? .dark : .light)
        .tint(.primaryBlue)
    }
}

#Preview("Loading") {
    LoadingView()
}

#Preview("Subscription Expired") {
    SubscriptionExpiredView {
        print("Renew tapped")
    }
}
