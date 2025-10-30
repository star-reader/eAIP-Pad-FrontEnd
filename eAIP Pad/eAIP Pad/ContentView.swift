//
//  ContentView.swift
//  eAIP Pad
//
//  Created by usagi on 2025/10/30.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    // 查询用户设置
    @Query private var userSettings: [UserSettings]
    
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
        Group {
            if horizontalSizeClass == .compact {
                // iPhone: 使用 TabView
                MainTabView()
            } else {
                // iPad: 使用 Sidebar
                MainSidebarView()
            }
        }
        .preferredColorScheme(currentSettings.isDarkMode ? .dark : .light)
        .onAppear {
            // 初始化应用
            initializeApp()
        }
    }
    
    private func initializeApp() {
        // 确保用户设置存在
        if userSettings.isEmpty {
            let settings = UserSettings()
            modelContext.insert(settings)
        }
        
        // 初始化网络服务等
        Task {
            await loadInitialData()
        }
    }
    
    private func loadInitialData() async {
        // 加载初始数据，如当前AIRAC版本等
        do {
            let airacResponse = try await NetworkService.shared.getCurrentAIRAC()
            
            // 检查是否已存在该版本
            let existingVersions = try modelContext.fetch(
                FetchDescriptor<AIRACVersion>(
                    predicate: #Predicate { $0.version == airacResponse.version }
                )
            )
            
            if existingVersions.isEmpty {
                let newVersion = AIRACVersion(
                    version: airacResponse.version,
                    effectiveDate: ISO8601DateFormatter().date(from: airacResponse.effectiveDate) ?? Date(),
                    isCurrent: airacResponse.isCurrent
                )
                modelContext.insert(newVersion)
            }
        } catch {
            print("加载初始数据失败: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
