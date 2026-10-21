//
//  ContentView.swift
//  eAIP Pad
//
//  Created by usagi on 2025/10/30.
//

import SwiftUI
import SwiftData

// 导入所有需要的模型和服务

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    // 查询用户设置
    @Query private var userSettings: [UserSettings]
    @Query private var airacVersions: [AIRACVersion]
    
    @State private var isCheckingAIRAC = false
    
    // 当前用户设置（单例）
    private var currentSettings: UserSettings {
        if let settings = userSettings.first {
            return settings
        } else {
            // 创建默认设置
            let newSettings = UserSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }
    
    var body: some View {
        OnboardingFlow()
            .preferredColorScheme(colorScheme)
            .tint(.primaryBlue) // 设置全局主题色为蓝色
            .task {
                await initializeApp()
            }
    }
    
    private var colorScheme: ColorScheme? {
        if currentSettings.followSystemAppearance {
            return nil // 跟随系统
        } else {
            return currentSettings.isDarkMode ? .dark : .light
        }
    }
    
    private func initializeApp() async {
        // 确保用户设置存在
        do {
            if try modelContext.fetch(FetchDescriptor<UserSettings>()).isEmpty {
                modelContext.insert(UserSettings())
            }
            try UserSettings.migratePinboardStyle(in: modelContext)
            try modelContext.save()
        } catch {
            LoggerService.shared.warning(module: "ContentView", message: "保存用户偏好失败：\(error.localizedDescription)")
        }
        
        // 启动时检查 AIRAC 版本更新
        await checkAndUpdateAIRAC()
    }
    
    /// 启动时读取已启用的数据源周期；在线请求由各列表和阅读器按需发起。
    private func checkAndUpdateAIRAC() async {
        guard !isCheckingAIRAC else { return }
        isCheckingAIRAC = true
        defer { isCheckingAIRAC = false }

        let currentLocalVersion = airacVersions.first(where: { $0.isCurrent })
        if let localVersion = currentLocalVersion {
            LoggerService.shared.info(
                module: "ContentView", message: "当前 AIRAC 版本: \(localVersion.version)")
        } else {
            LoggerService.shared.info(
                module: "ContentView", message: "暂无 AIRAC 数据，等待用户导入或配置服务器")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
