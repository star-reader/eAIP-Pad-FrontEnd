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
        defer { isCheckingAIRAC = false }
        
        // 等待认证完成（最多等待 5 秒）
        var waitCount = 0
        while AuthenticationService.shared.authenticationState != .authenticated && waitCount < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            waitCount += 1
        }
        
        // 如果还未认证，则跳过 AIRAC 检查
        guard AuthenticationService.shared.authenticationState == .authenticated else {
            print("⚠️ 用户未认证，跳过 AIRAC 检查")
            return
        }
        
        // 确保 NetworkService 已设置 token（额外等待一小段时间让 token 验证完成）
        var tokenWaitCount = 0
        while NetworkService.shared.getCurrentAccessToken() == nil && tokenWaitCount < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            tokenWaitCount += 1
        }
        
        // 如果仍然没有 token，再尝试一次等待
        if NetworkService.shared.getCurrentAccessToken() == nil {
            print("⚠️ Token 尚未设置，等待 token 验证完成...")
            try? await Task.sleep(nanoseconds: 500_000_000) // 额外等待 0.5 秒
        }
        
        // 如果还是没有 token，跳过本次检查（会在下次进入主应用时重试）
        guard NetworkService.shared.getCurrentAccessToken() != nil else {
            print("⚠️ Token 未设置，跳过 AIRAC 检查（将在下次重试）")
            return
        }
        
        print("🔄 检查 AIRAC 版本...")
        
        // 从 API 获取最新 AIRAC 版本（最多重试 3 次）
        var airacResponse: AIRACResponse?
        var lastError: Error?
        
        for attempt in 1...3 {
            do {
                airacResponse = try await NetworkService.shared.getCurrentAIRAC()
                break // 成功，退出重试循环
            } catch {
                lastError = error
                print("⚠️ AIRAC 请求失败（尝试 \(attempt)/3）: \(error.localizedDescription)")
                
                // 如果是最后一次尝试，不再等待
                if attempt < 3 {
                    // 等待后重试（指数退避）
                    let delay = UInt64(attempt * 500_000_000) // 0.5s, 1s
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        // 如果所有重试都失败，记录错误但不崩溃
        guard let response = airacResponse else {
            print("❌ AIRAC 检查失败（所有重试均失败）: \(lastError?.localizedDescription ?? "未知错误")")
            return
        }
        
        // 获取本地当前版本
        let currentLocalVersion = airacVersions.first(where: { $0.isCurrent })
        
        if let localVersion = currentLocalVersion {
            if localVersion.version != response.version {
                // 云端版本已更新
                print("🆕 检测到新版本 AIRAC: \(response.version) (本地: \(localVersion.version))")
                
                // 创建新版本记录
                let newVersion = AIRACVersion(
                    version: response.version,
                    effectiveDate: ISO8601DateFormatter().date(from: response.effectiveDate) ?? Date(),
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
            print("🆕 初始化 AIRAC 版本: \(response.version)")
            let newVersion = AIRACVersion(
                version: response.version,
                effectiveDate: ISO8601DateFormatter().date(from: response.effectiveDate) ?? Date(),
                isCurrent: true
            )
            modelContext.insert(newVersion)
            try? modelContext.save()
            print("✅ AIRAC 初始化完成")
        }
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
