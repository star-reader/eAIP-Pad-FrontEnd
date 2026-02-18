import SwiftUI
import SwiftData

@main
struct eAIPPadApp: App {
    // SwiftData 模型容器
    let modelContainer: ModelContainer

    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            // 配置 SwiftData 模型容器
            modelContainer = try ModelContainer(for:
                PinnedChart.self,
                ChartAnnotation.self,
                AIRACVersion.self,
                UserSettings.self,
                LocalChart.self,
                Airport.self
            )
            LoggerService.shared.log(type: .info, module: "App", message: "APP initialized successfully")
        } catch {
            LoggerService.shared.log(type: .error, module: "App", message: "Failed to initialize SwiftData container: \(error)")
            fatalError("无法初始化 SwiftData 容器: \(error)")
        }
        _ = SubscriptionService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .tint(.primaryBlue) // 全局蓝色主题
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await SubscriptionService.shared.querySubscriptionStatus()
                }
            }
        }
    }
}
