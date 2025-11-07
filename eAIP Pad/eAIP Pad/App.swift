import SwiftUI
import SwiftData

@main
struct eAIPPadApp: App {
    // SwiftData 模型容器
    let modelContainer: ModelContainer
    
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
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .tint(.primaryBlue) // 全局蓝色主题
        }
    }
}
