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
        LoggerService.shared.info(module: "ContentView", message: "准备检查 AIRAC 版本...")
        guard !isCheckingAIRAC else { 
            LoggerService.shared.info(module: "ContentView", message: "AIRAC 检查已在进行中，跳过")
            return 
        }
        isCheckingAIRAC = true
        defer { isCheckingAIRAC = false }
        
        // 等待认证完成（最多 30 秒）
        LoggerService.shared.info(module: "ContentView", message: "等待用户认证完成...")
        var waitCount = 0
        while AuthenticationService.shared.authenticationState != .authenticated && waitCount < 300 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            waitCount += 1
            
            // 每 5 秒记录一次等待状态
            if waitCount % 50 == 0 {
                LoggerService.shared.info(module: "ContentView", message: "仍在等待认证... (\(waitCount / 10) 秒)")
            }
        }
        
        // 如果还未认证，则跳过 AIRAC 检查
        guard AuthenticationService.shared.authenticationState == .authenticated else {
            LoggerService.shared.warning(module: "ContentView", message: "等待超时或用户未认证，跳过 AIRAC 检查")
            return
        }
        
        LoggerService.shared.info(module: "ContentView", message: "✓ 用户已认证，等待 Access Token...")
        
        // 等待 token 设置（最多 3 秒）
        var tokenWaitCount = 0
        while NetworkService.shared.getCurrentAccessToken() == nil && tokenWaitCount < 30 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            tokenWaitCount += 1
        }
        
        // 如果还是没有 token，跳过本次检查
        guard NetworkService.shared.getCurrentAccessToken() != nil else {
            LoggerService.shared.warning(module: "ContentView", message: "Access Token 未就绪，跳过 AIRAC 检查")
            return
        }
        
        LoggerService.shared.info(module: "ContentView", message: "✓ Access Token 已就绪，开始检查 AIRAC 版本")
        
        var airacResponse: AIRACResponse?
        var lastError: Error?
        
        for attempt in 1...3 {
            do {
                airacResponse = try await NetworkService.shared.getCurrentAIRAC()
                LoggerService.shared.log(type: .info, module: "ContentView", message: "airacResponse: \(String(describing: airacResponse))")
                break
            } catch {
                lastError = error
                LoggerService.shared.log(type: .warning, module: "ContentView", message: "AIRAC 请求失败（尝试 \(attempt)/3）: \(error.localizedDescription)")
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
            LoggerService.shared.log(type: .error, module: "ContentView", message: "AIRAC 检查失败（所有重试均失败）: \(lastError?.localizedDescription ?? "未知错误")")
            return
        }
        
        // 获取本地当前版本
        let currentLocalVersion = airacVersions.first(where: { $0.isCurrent })
        
        if let localVersion = currentLocalVersion {
            if localVersion.version != response.version {
                // 云端版本已更新
                LoggerService.shared.log(type: .info, module: "ContentView", message: "检测到新版本 AIRAC: \(response.version) (本地: \(localVersion.version))")
                
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
                LoggerService.shared.log(type: .info, module: "ContentView", message: "清理旧版本数据...")
                await clearOldVersionData(oldVersion: localVersion.version)
                
                // 触发新版本数据下载
                LoggerService.shared.info(module: "ContentView", message: "开始下载新版本 AIRAC 数据")
                await AIRACService.shared.checkAndUpdateAIRAC(modelContext: modelContext)
                
                LoggerService.shared.log(type: .info, module: "ContentView", message: "AIRAC 更新完成")
            } else {
                LoggerService.shared.log(type: .info, module: "ContentView", message: "无需更新，AIRAC 版本已是最新: \(localVersion.version)")
                
                // 检查本地是否有数据，如果没有则下载
                await checkAndDownloadDataIfNeeded(version: localVersion.version)
            }
        } else {
            // 本地没有版本记录，创建新的并下载数据
            LoggerService.shared.log(type: .info, module: "ContentView", message: "初始化 AIRAC 版本: \(response.version)")
            let newVersion = AIRACVersion(
                version: response.version,
                effectiveDate: ISO8601DateFormatter().date(from: response.effectiveDate) ?? Date(),
                isCurrent: true
            )
            modelContext.insert(newVersion)
            try? modelContext.save()
            LoggerService.shared.log(type: .info, module: "ContentView", message: "AIRAC 初始化完成，准备下载航图数据")
            
            // 首次启动，触发完整的 AIRAC 数据下载
            LoggerService.shared.info(module: "ContentView", message: "检测到首次启动，开始下载 AIRAC 数据")
            await AIRACService.shared.checkAndUpdateAIRAC(modelContext: modelContext)
        }
    }
    
    // 检查并下载数据（如果本地没有）
    private func checkAndDownloadDataIfNeeded(version: String) async {
        do {
            // 检查是否有机场数据
            let airportDescriptor = FetchDescriptor<Airport>()
            let airports = try modelContext.fetch(airportDescriptor)
            
            // 检查是否有航图数据
            let chartDescriptor = FetchDescriptor<LocalChart>(
                predicate: #Predicate<LocalChart> { chart in
                    chart.airacVersion == version
                }
            )
            let charts = try modelContext.fetch(chartDescriptor)
            
            if airports.isEmpty || charts.isEmpty {
                LoggerService.shared.info(module: "ContentView", message: "检测到本地无数据（机场: \(airports.count), 航图: \(charts.count)），开始下载")
                await AIRACService.shared.checkAndUpdateAIRAC(modelContext: modelContext)
            } else {
                LoggerService.shared.info(module: "ContentView", message: "本地数据完整（机场: \(airports.count), 航图: \(charts.count)），无需下载")
            }
        } catch {
            LoggerService.shared.error(module: "ContentView", message: "检查本地数据失败: \(error.localizedDescription)")
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
            LoggerService.shared.log(type: .info, module: "ContentView", message: "clearOldVersionData completed: \(oldVersion)")
        } catch {
            LoggerService.shared.log(type: .warning, module: "ContentView", message: "清理旧版本数据失败: \(error)")
        }
        LoggerService.shared.log(type: .info, module: "ContentView", message: "clearOldVersionData completed: \(oldVersion)")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
