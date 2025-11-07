import SwiftUI
import SwiftData
import Combine

// MARK: - 引导流程状态
enum OnboardingState {
    case needsLogin       // 需要登录
    case completed        // 完成，进入主应用
}

// MARK: - 引导流程协调器
class OnboardingCoordinator: ObservableObject {
    @Published var currentState: OnboardingState = .completed
    @Published var errorMessage: String?
    
    private let authService = AuthenticationService.shared
    
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
        // 监听认证状态变化
        // 注意：登录成功的处理由 OnboardingFlow 的监听器负责，这里只处理退出登录的情况
        authService.$authenticationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .authenticated:
                    // 已认证：如果当前不在登录流程中，则切换到主应用
                    // 这主要用于 app 重新启动时，已有 token 的情况
                    if self.currentState != .needsLogin {
                        LoggerService.shared.info(module: "OnboardingCoordinator", message: "已认证且不在登录流程中，进入主应用")
                        self.currentState = .completed
                    } else {
                        LoggerService.shared.info(module: "OnboardingCoordinator", message: "已认证，但在登录流程中，由 OnboardingFlow 处理")
                    }
                case .authenticating:
                    // 登录中：保持当前状态，不做任何切换
                    LoggerService.shared.info(module: "OnboardingCoordinator", message: "正在认证中，保持登录界面")
                case .notAuthenticated:
                    // 仅当确无本地 token 时才进入登录
                    let hasStoredAccessToken = UserDefaults.standard.string(forKey: "access_token") != nil
                    if !hasStoredAccessToken && self.currentState != .needsLogin {
                        LoggerService.shared.info(module: "OnboardingCoordinator", message: "Token 无效且无本地凭据，进入登录页面")
                        self.currentState = .needsLogin
                    }
                case .error:
                    // 出错也不要闪现登录，交由用户主动进入登录
                    LoggerService.shared.info(module: "OnboardingCoordinator", message: "认证出错")
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 同步检查（避免闪现）
    private func performSyncCheck() {
        // 检查是否有存储的token
        if let _ = UserDefaults.standard.string(forKey: "access_token") {
            LoggerService.shared.info(module: "OnboardingCoordinator", message: "检测到存储的登录信息，先进入主应用避免闪现")
            currentState = .completed
        } else {
            LoggerService.shared.info(module: "OnboardingCoordinator", message: "未检测到存储的登录信息")
        }
    }
    
    // MARK: - 检查初始状态
    func checkInitialState() {
        errorMessage = nil
        
        Task {
            await performInitialChecks()
        }
    }
    
    @MainActor
    private func performInitialChecks() async {
        // 0. 启动期间避免闪现登录：如果正在认证或已加载到本地 token，则直接进入主应用
        let hasStoredAccessToken = UserDefaults.standard.string(forKey: "access_token") != nil
        if authService.authenticationState == .authenticating || hasStoredAccessToken {
            currentState = .completed
            // 后台继续后续检查
        } else if !authService.isAuthenticated {
            // 无本地 token 且未认证，才进入登录
            currentState = .needsLogin
            return
        }
        
        // 同步订阅状态（后台执行，不阻塞）
        Task {
            await SubscriptionService.shared.syncSubscriptionStatus()
        }
        
        // 已登录，直接进入主应用
        currentState = .completed
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
        LoggerService.shared.info(module: "OnboardingCoordinator", message: "登录完成，进入主应用")
        currentState = .completed
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
            case .needsLogin:
                LoginView()
                    .onReceive(AuthenticationService.shared.$authenticationState) { state in
                        if state == .authenticated {
                            coordinator.handleLoginCompleted()
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
    @StateObject private var subscriptionService = SubscriptionService.shared
    
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
            // 启动时在首个订阅状态同步完成前，始终展示主应用，避免闪屏
            if !subscriptionService.hasLoadedOnce {
                contentView
            } else if subscriptionService.hasValidSubscription {
                // 有订阅：显示主应用内容
                contentView
            } else {
                // 没有订阅：直接显示订阅页面
                UnifiedSubscriptionView()
            }
        }
        .task {
            // 进入主应用时同步订阅状态
            await subscriptionService.syncSubscriptionStatus()
        }
    }
    
    private var contentView: some View {
        Group {
            if horizontalSizeClass == .compact {
                MainTabView()
            } else {
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

