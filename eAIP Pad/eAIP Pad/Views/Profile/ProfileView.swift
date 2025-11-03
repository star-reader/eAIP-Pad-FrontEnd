import SwiftUI
import MessageUI
import SwiftData
import Foundation

// MARK: - 个人中心视图
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    @Query private var pinnedCharts: [PinnedChart]
    @Query private var airacVersions: [AIRACVersion]
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingSubscription = false
    @State private var showingCacheCleared = false
    @State private var showingCacheError = false
    @State private var showingEmailAlert = false
    @State private var cacheSizeText: String = ""
    @State private var errorMessage: String = ""
    
    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }
    
    private var currentAIRAC: AIRACVersion? {
        airacVersions.first { $0.isCurrent }
    }
    
    var body: some View {
        List {
            // 订阅状态卡片
            Section {
                SubscriptionStatusCard(
                    subscriptionService: subscriptionService,
                    onSubscribe: {
                        showingSubscription = true
                    }
                )
            }
            
            // 统计信息
            Section("使用统计") {
                    StatisticRow(
                        icon: "pin.fill",
                        title: "收藏航图",
                        value: "\(pinnedCharts.count) 个",
                        color: .orange
                    )
                    
                    if let currentAIRAC = currentAIRAC {
                        StatisticRow(
                            icon: "arrow.clockwise",
                            title: "当前AIRAC",
                            value: currentAIRAC.version,
                            color: .blue
                        )
                    }
                }
                
                // 应用设置
                Section("应用设置") {
                    Button {
                        showingSettings = true
                    } label: {
                        SettingRow(
                            icon: "gearshape.fill",
                            title: "偏好设置",
                            color: .gray
                        )
                    }
                    
                    Button {
                        Task {
                            await clearCache()
                            await MainActor.run {
                                showingCacheCleared = true
                            }
                        }
                    } label: {
                        SettingRow(
                            icon: "trash.fill",
                            title: "清理缓存",
                            color: .red,
                            trailingText: cacheSizeText
                        )
                    }
                }
                
                // 帮助与支持
                Section("帮助与支持") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingRow(
                            icon: "info.circle.fill",
                            title: "关于应用",
                            color: .blue
                        )
                    }
                    
                    Button {
                        sendEmail()
                    } label: {
                        SettingRow(
                            icon: "envelope.fill",
                            title: "联系开发者",
                            color: .orange
                        )
                    }
                }
                
                // 法律信息
                Section("法律信息") {
                    Button {
                        // TODO: 打开隐私政策
                    } label: {
                        SettingRow(
                            icon: "hand.raised.fill",
                            title: "隐私政策",
                            color: .purple
                        )
                    }
                    
                    Button {
                        // TODO: 打开服务条款
                    } label: {
                        SettingRow(
                            icon: "doc.text.fill",
                            title: "服务条款",
                            color: .indigo
                        )
                    }
                }
        }
        .navigationTitle("个人")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingSubscription) {
            UnifiedSubscriptionView()
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .alert("缓存已清理", isPresented: $showingCacheCleared) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("已成功清理所有AIRAC数据与PDF缓存文件。")
        }
        .alert("清理缓存失败", isPresented: $showingCacheError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("邮件发送失败", isPresented: $showingEmailAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            Task { await updateCacheSize() }
        }
    }
    
    private func clearCache() async {
        do {
            // 1. 清理所有AIRAC数据（包括当前版本）
            for version in airacVersions {
                // 记录版本号，用于清理文件缓存
                let versionString = version.version
                
                // 删除相关的航图数据
                let chartsDescriptor = FetchDescriptor<LocalChart>(
                    predicate: #Predicate<LocalChart> { chart in
                        chart.airacVersion == versionString
                    }
                )
                let chartsToDelete = try modelContext.fetch(chartsDescriptor)
                
                for chart in chartsToDelete {
                    modelContext.delete(chart)
                }
                
                // 清理该版本的PDF文件缓存
                PDFCacheService.shared.clearCacheForVersion(versionString)
                
                // 清理该版本的数据缓存
                PDFCacheService.shared.clearDataCacheForVersion(versionString)
                
                // 如果是当前版本，不删除版本记录，只清空其数据
                if !version.isCurrent {
                    modelContext.delete(version)
                }
            }
            
            // 2. 清理网络缓存
            URLCache.shared.removeAllCachedResponses()
            
            // 3. 保存更改
            try modelContext.save()
            
            // 4. 更新缓存大小显示
            await updateCacheSize()
            
            // 5. 显示成功提示
            await MainActor.run {
                showingCacheCleared = true
            }
            
        } catch {
            print("清理缓存失败: \(error)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingCacheError = true
            }
        }
    }

    private func updateCacheSize() async {
        // 读取总缓存（PDF+数据）大小
        let formatted = PDFCacheService.shared.getFormattedTotalCacheSize()
        await MainActor.run {
            cacheSizeText = formatted
        }
    }
    
    // 发送邮件功能
    private func sendEmail() {
        let emailAddress = "jinch2287@outlook.com"
        let subject = "eAIP Pad 用户反馈"
        let body = "请在此处描述您的问题或建议..."
        
        let urlString = "mailto:\(emailAddress)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // 如果无法打开邮件应用，显示提示
            errorMessage = "请确保您的设备已设置邮件账户，或者直接发送邮件至：\(emailAddress)"
            showingEmailAlert = true
        }
    }
}

// MARK: - 订阅状态卡片
struct SubscriptionStatusCard: View {
    @ObservedObject var subscriptionService: SubscriptionService
    let onSubscribe: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("订阅状态")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(subscriptionService.subscriptionDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: subscriptionService.hasValidSubscription ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(subscriptionService.hasValidSubscription ? .green : .orange)
                    
                    if subscriptionService.daysLeft > 0 {
                        Text("\(subscriptionService.daysLeft) 天")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if !subscriptionService.hasValidSubscription {
                Button("立即订阅") {
                    onSubscribe()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            // 页面显示时刷新订阅状态
            Task {
                await subscriptionService.querySubscriptionStatus()
            }
        }
    }
}

// MARK: - 统计行视图
struct StatisticRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 设置行视图
struct SettingRow: View {
    let icon: String
    let title: String
    let color: Color
    var trailingText: String? = nil
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            if let trailingText = trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 设置视图
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    
    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 外观设置
                Section("外观") {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        Text("跟随系统外观")
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { currentSettings.followSystemAppearance },
                            set: { newValue in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentSettings.followSystemAppearance = newValue
                                }
                                try? modelContext.save()
                            }
                        ))
                    }
                    
                    if !currentSettings.followSystemAppearance {
                        HStack {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.indigo)
                                .frame(width: 24)
                            
                            Text("深色模式")
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { currentSettings.isDarkMode },
                                set: { newValue in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentSettings.isDarkMode = newValue
                                    }
                                    try? modelContext.save()
                                }
                            ))
                        }
                    }
                    
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        
                        Text("Pinboard 样式")
                        
                        Spacer()
                        
                        Picker("Pinboard 样式", selection: Binding(
                            get: { PinboardStyle(rawValue: currentSettings.pinboardStyle) ?? .compact },
                            set: { newValue in
                                currentSettings.pinboardStyle = newValue.rawValue
                                try? modelContext.save()
                            }
                        )) {
                            ForEach(PinboardStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                // 数据设置
                Section("数据") {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("自动同步")
                            Text("启动时自动检查AIRAC更新")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: .constant(true))
                    }
                    
                    HStack {
                        Image(systemName: "wifi")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("仅WiFi下载")
                            Text("大文件仅在WiFi环境下载载")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: .constant(true))
                    }
                }
                
                // 阅读设置
                Section("阅读") {
                    HStack {
                        Image(systemName: "pencil.tip.crop.circle")
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("默认标注工具")
                            Text("打开PDF时的默认标注工具")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Picker("标注工具", selection: .constant(AnnotationTool.pen)) {
                            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                                Text(tool.displayName).tag(tool)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    HStack {
                        Image(systemName: "hand.draw")
                            .foregroundColor(.red)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple Pencil 支持")
                            Text("启用Apple Pencil专用功能")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: .constant(true))
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 关于视图
struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 应用图标和信息
                    VStack(spacing: 16) {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.orange)
                        
                        Text("eAIP Pad")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("专业中国eAIP航图阅读器")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("版本 1.0.0 (Build 1)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // 功能介绍
                    VStack(alignment: .leading, spacing: 16) {
                        Text("主要功能")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureItem(
                                icon: "airplane",
                                title: "完整航图库",
                                description: "支持中国所有机场的SID、STAR、进近和机场图"
                            )
                            
                            FeatureItem(
                                icon: "map",
                                title: "航路图支持",
                                description: "高清航路图和区域图，支持缩放和标注"
                            )
                            
                            FeatureItem(
                                icon: "pencil.tip.crop.circle",
                                title: "专业标注",
                                description: "Apple Pencil支持，标注永久保存"
                            )
                            
                            FeatureItem(
                                icon: "pin",
                                title: "快速访问",
                                description: "收藏常用航图，支持多种显示样式"
                            )
                            
                            FeatureItem(
                                icon: "arrow.clockwise",
                                title: "自动更新",
                                description: "AIRAC版本自动同步，确保数据最新"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    
                    // 技术信息
                    VStack(alignment: .leading, spacing: 12) {
                        Text("技术信息")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• 基于 SwiftUI + SwiftData 构建")
                            Text("• 支持 iOS 18+ / iPadOS 18+")
                            Text("• 响应式设计，完美适配各种设备")
                            Text("• 本地优先存储，支持离线使用")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    
                    // 版权信息
                    VStack(spacing: 8) {
                        Text("© 2025 eAIP Pad")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("专为中国航空爱好者设计")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 功能项目视图
struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview("Profile") {
    ProfileView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}

#Preview("Settings") {
    SettingsView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}

#Preview("About") {
    AboutView()
}
