import SwiftData
import SwiftUI

// MARK: - 引导流程主视图
struct OnboardingFlow: View {
    var body: some View {
        MainAppView()
    }
}

// MARK: - 主应用视图
struct MainAppView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

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
        contentView
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
            return nil  // 跟随系统
        } else {
            return currentSettings.isDarkMode ? .dark : .light
        }
    }
}
