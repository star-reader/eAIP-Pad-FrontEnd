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
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .preferredColorScheme(.dark) // 默认深色模式
                .tint(.primaryBlue) // 全局蓝色主题
        }
    }
}
