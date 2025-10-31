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
        if userSettings.isEmpty {
            let settings = UserSettings()
            modelContext.insert(settings)
        }
        
        // 启动时检查 AIRAC 版本更新
        await checkAndUpdateAIRAC()
    }
    
    private func checkAndUpdateAIRAC() async {
        guard !isCheckingAIRAC else { return }
        isCheckingAIRAC = true
        
        do {
            // 等待认证完成（最多等待 3 秒）
            var waitCount = 0
            while AuthenticationService.shared.authenticationState != .authenticated && waitCount < 30 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                waitCount += 1
            }
            
            // 如果还未认证，则跳过 AIRAC 检查
            guard AuthenticationService.shared.authenticationState == .authenticated else {
                print("⚠️ 用户未认证，跳过 AIRAC 检查")
                isCheckingAIRAC = false
                return
            }
            
            print("🔄 检查 AIRAC 版本...")
            
            // 从 API 获取最新 AIRAC 版本
            let airacResponse = try await NetworkService.shared.getCurrentAIRAC()
            
            // 获取本地当前版本
            let currentLocalVersion = airacVersions.first(where: { $0.isCurrent })
            
            if let localVersion = currentLocalVersion {
                if localVersion.version != airacResponse.version {
                    // 云端版本已更新
                    print("🆕 检测到新版本 AIRAC: \(airacResponse.version) (本地: \(localVersion.version))")
                    
                    // 创建新版本记录
                    let newVersion = AIRACVersion(
                        version: airacResponse.version,
                        effectiveDate: ISO8601DateFormatter().date(from: airacResponse.effectiveDate) ?? Date(),
                        isCurrent: true
                    )
                    modelContext.insert(newVersion)
                    
                    // 将旧版本标记为非当前
                    localVersion.isCurrent = false
                    
                    try? modelContext.save()
                    
                    // 清理旧版本缓存
                    print("🧹 清理旧版本数据...")
                    await clearOldVersionData(oldVersion: localVersion.version)
                    
                    print("✅ AIRAC 更新完成")
                } else {
                    print("✅ AIRAC 版本已是最新: \(localVersion.version)")
                }
            } else {
                // 本地没有版本记录，创建新的
                print("🆕 初始化 AIRAC 版本: \(airacResponse.version)")
                let newVersion = AIRACVersion(
                    version: airacResponse.version,
                    effectiveDate: ISO8601DateFormatter().date(from: airacResponse.effectiveDate) ?? Date(),
                    isCurrent: true
                )
                modelContext.insert(newVersion)
                try? modelContext.save()
            }
            
        } catch {
            print("⚠️ AIRAC 检查失败: \(error.localizedDescription)")
        }
        
        isCheckingAIRAC = false
    }
    
    private func clearOldVersionData(oldVersion: String) async {
        // 清理旧版本的 PDF 缓存
        PDFCacheService.shared.clearCacheForVersion(oldVersion)
        
        // 清理旧版本的数据缓存（机场列表、航路图列表等）
        PDFCacheService.shared.clearDataCacheForVersion(oldVersion)
        
        // 清理旧版本的航图数据
        do {
            let descriptor = FetchDescriptor<LocalChart>(
                predicate: #Predicate<LocalChart> { chart in
                    chart.airacVersion == oldVersion
                }
            )
            let oldCharts = try modelContext.fetch(descriptor)
            for chart in oldCharts {
                modelContext.delete(chart)
            }
            
            // 清理机场列表（机场数据可能也需要更新）
            let airportDescriptor = FetchDescriptor<Airport>()
            let airports = try modelContext.fetch(airportDescriptor)
            for airport in airports {
                modelContext.delete(airport)
            }
            
            try? modelContext.save()
            print("✅ 已清理旧版本数据: \(oldVersion)")
        } catch {
            print("⚠️ 清理旧版本数据失败: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
