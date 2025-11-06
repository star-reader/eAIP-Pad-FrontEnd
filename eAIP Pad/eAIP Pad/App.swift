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
        } catch {
            fatalError("无法初始化 SwiftData 容器: \(error)")
        }

        // 初始化日志服务
        LoggerService.shared.addLog(type: .info, message: "Application started.")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .tint(.primaryBlue) // 全局蓝色主题
        }
    }
}
