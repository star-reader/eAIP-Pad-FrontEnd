import SwiftUI
import SwiftData
import Combine

// MARK: - 引导流程状态
enum OnboardingState {
    case loading           // 检查状态中
    case needsLogin       // 需要登录
    case newUserWelcome   // 新用户欢迎
    case needsSubscription // 需要订阅
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
        
        // 监听认证状态变化
        setupAuthenticationListener()
        
        // 然后做异步检查
        checkInitialState()
    }
    
    // MARK: - 设置认证状态监听
    private func setupAuthenticationListener() {
        // 监听认证状态变化，如果token验证失败，跳转到登录页面
        authService.$authenticationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .notAuthenticated && self?.currentState == .completed {
                    print("🔄 Token验证失败，跳转到登录页面")
                    self?.currentState = .needsLogin
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 同步检查（避免闪现）
    private func performSyncCheck() {
        // 检查是否有存储的token
        if let _ = UserDefaults.standard.string(forKey: "access_token") {
            print("🚀 检测到存储的登录信息，先进入主应用避免闪现")
            currentState = .completed
        } else {
            print("📱 未检测到存储的登录信息")
        }
    }
    
    // MARK: - 检查初始状态
    func checkInitialState() {
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
                
            case .expired, .inactive:
                // 订阅过期或未订阅，都显示升级页面
                // 无论是否为新用户，只要订阅状态为inactive就显示试用页面
                currentState = .needsSubscription
            }
        } catch {
            // 如果订阅检查失败，检查是否为inactive状态，如果是则显示订阅页面
            if subscriptionService.subscriptionStatus == .inactive {
                currentState = .needsSubscription
            } else {
                currentState = .completed
            }
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
                print("❌ 无法获取用户ID，直接进入主应用")
                // 即使无法获取用户ID，新用户试用也应该直接进入主应用
                currentState = .completed
                isLoading = false
                return
            }
            

            let response = try await NetworkService.shared.startTrial(userId: userId)
            
            
            switch response.data.status {
            case "trial_started":
                print("✅ 试用期开启成功")
                // 直接使用试用API响应更新订阅状态
                await MainActor.run {
                    subscriptionService.subscriptionStatus = .trial
                    subscriptionService.isTrialActive = true
                    subscriptionService.daysLeft = response.data.daysLeft
                    
                    // 解析试用结束日期
                    if let trialEndString = response.data.trialEndDate {
                        subscriptionService.trialEndDate = ISO8601DateFormatter().date(from: trialEndString)
                    }
                    
                    print("📱 直接设置试用状态: subscriptionStatus=\(subscriptionService.subscriptionStatus), daysLeft=\(subscriptionService.daysLeft)")
                }
                
                // 试用开启成功，直接进入主应用
                currentState = .completed
                
            case "trial_used", "trial_expired":
                print("⚠️ 试用期已使用或过期")
                currentState = .needsSubscription
                
            default:
                print("⚠️ 未知状态: \(response.data.status)")
                currentState = .needsSubscription
            }
        } catch {
            print("❌ 试用期启动失败: \(error)")
            // 试用期启动失败，也让用户进入主应用（降级方案）
            currentState = .completed
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
        .preferredColorScheme(colorScheme)
        .tint(.primaryBlue)
        .animation(.easeInOut(duration: 0.3), value: currentSettings.isDarkMode)
        .animation(.easeInOut(duration: 0.3), value: currentSettings.followSystemAppearance)
    }
    
    private var colorScheme: ColorScheme? {
        if currentSettings.followSystemAppearance {
            return nil // 跟随系统
        } else {
            return currentSettings.isDarkMode ? .dark : .light
        }
    }
}

#Preview("Loading") {
    LoadingView()
}

