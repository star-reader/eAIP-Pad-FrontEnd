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
    @State private var showingMailComposer = false
    @State private var showingBugReportOptions = false
    @State private var cacheSizeText: String = ""
    @State private var errorMessage: String = ""
    @State private var mailData: MailData?
    @State private var showingSignOutConfirmation = false
    
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
                    Button {
                        showingAbout = true
                    } label: {
                        SettingRow(
                            icon: "info.circle.fill",
                            title: "关于应用",
                            color: .blue
                        )
                    }
                    
                    Button {
                        openGitHub()
                    } label: {
                        SettingRow(
                            icon: "link.circle.fill",
                            title: "GitHub 仓库",
                            color: .green
                        )
                    }
                    
                    Button {
                        sendNewIdeaEmail()
                    } label: {
                        SettingRow(
                            icon: "lightbulb.fill",
                            title: "我有新想法",
                            color: .yellow
                        )
                    }
                    
                    Button {
                        showingBugReportOptions = true
                    } label: {
                        SettingRow(
                            icon: "ladybug.fill",
                            title: "反馈bug",
                            color: .red
                        )
                    }
                }
                
                // 法律信息
                Section("法律信息") {
                    Button {
                        openPrivacyPolicy()
                    } label: {
                        SettingRow(
                            icon: "hand.raised.fill",
                            title: "隐私政策",
                            color: .purple
                        )
                    }
                    
                    Button {
                        openTermsOfService()
                    } label: {
                        SettingRow(
                            icon: "doc.text.fill",
                            title: "服务条款",
                            color: .indigo
                        )
                    }
                }
                
                // 账户管理
                Section {
                    Button {
                        showingSignOutConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                                .frame(width: 24)
                            
                            Text("退出登录")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
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
        .sheet(isPresented: $showingAbout) {
            AboutView()
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
        .confirmationDialog("是否附带日志文件？", isPresented: $showingBugReportOptions) {
            Button("附带日志") {
                sendBugReportEmail(withLogs: true)
            }
            Button("不附带") {
                sendBugReportEmail(withLogs: false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("附带日志文件可以帮助开发者更好地定位问题")
        }
        .confirmationDialog("确定要退出登录吗？", isPresented: $showingSignOutConfirmation) {
            Button("退出登录", role: .destructive) {
                handleSignOut()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新登录才能使用应用")
        }
        .sheet(item: $mailData) { data in
            MailComposeView(
                subject: data.subject,
                body: data.body,
                attachmentData: data.attachmentData,
                onDismiss: { _ in
                    mailData = nil
                }
            )
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
            LoggerService.shared.error(module: "ProfileView", message: "清理缓存失败: \(error.localizedDescription)")
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
    
    // 退出登录
    private func handleSignOut() {
        LoggerService.shared.info(module: "ProfileView", message: "用户点击退出登录")
        AuthenticationService.shared.signOut()
        LoggerService.shared.info(module: "ProfileView", message: "用户已成功退出登录")
    }
    
    // 打开 GitHub 仓库
    private func openGitHub() {
        let urlString = "https://github.com/star-reader/eAIP-Pad-FrontEnd"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
            LoggerService.shared.info(module: "ProfileView", message: "打开 GitHub 链接：\(urlString)")
        }
    }
    
    // 打开隐私政策
    private func openPrivacyPolicy() {
        let urlString = "https://github.com/star-reader/eAIP-Pad-FrontEnd/wiki/Privacy-Policy"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
            LoggerService.shared.info(module: "ProfileView", message: "打开隐私政策链接：\(urlString)")
        }
    }
    
    // 打开服务条款
    private func openTermsOfService() {
        let urlString = "https://github.com/star-reader/eAIP-Pad-FrontEnd/wiki/Terms-of-Service"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
            LoggerService.shared.info(module: "ProfileView", message: "打开服务条款链接：\(urlString)")
        }
    }
    
    // 发送新想法邮件
    private func sendNewIdeaEmail() {
        LoggerService.shared.info(module: "ProfileView", message: "用户点击「我有新想法」")
        
        if !MFMailComposeViewController.canSendMail() {
            errorMessage = "请确保您的设备已设置邮件账户，或者直接发送邮件至：jinch2287@gmail.com"
            showingEmailAlert = true
            LoggerService.shared.warning(module: "ProfileView", message: "设备无法发送邮件")
            return
        }
        
        let subject = "eAIP Pad - 新想法反馈"
        let body = """
        
        
        ───────────────────────────
        请在上方描述您的想法或建议
        
        系统信息：
        • 设备型号：\(UIDevice.current.model)
        • 系统版本：iOS \(UIDevice.current.systemVersion)
        • App 版本：1.0.0 (Build 1)
        """
        
        mailData = MailData(subject: subject, body: body, attachmentData: nil)
        LoggerService.shared.info(module: "ProfileView", message: "打开新想法邮件编辑器")
    }
    
    // 发送bug反馈邮件
    private func sendBugReportEmail(withLogs: Bool) {
        LoggerService.shared.info(module: "ProfileView", message: "用户点击「反馈bug」，附带日志：\(withLogs)")
        
        if !MFMailComposeViewController.canSendMail() {
            errorMessage = "请确保您的设备已设置邮件账户，或者直接发送邮件至：jinch2287@gmail.com"
            showingEmailAlert = true
            LoggerService.shared.warning(module: "ProfileView", message: "设备无法发送邮件")
            return
        }
        
        let subject = "eAIP Pad - Bug 反馈"
        let body = """
        
        
        ───────────────────────────
        请在上方描述您遇到的问题
        
        系统信息：
        • 设备型号：\(UIDevice.current.model)
        • 系统版本：iOS \(UIDevice.current.systemVersion)
        • App 版本：1.0.0 (Build 1)
        """
        
        if withLogs {
            // 导出日志文件
            Task {
                do {
                    LoggerService.shared.info(module: "ProfileView", message: "开始导出日志文件")
                    let logFileURL = try await LoggerService.shared.exportLogsAsFile()
                    let logData = try Data(contentsOf: logFileURL)
                    
                    LoggerService.shared.info(module: "ProfileView", message: "日志文件读取成功，大小：\(logData.count) 字节")
                    
                    await MainActor.run {
                        // 直接创建包含所有数据的 MailData 对象
                        self.mailData = MailData(subject: subject, body: body, attachmentData: logData)
                        LoggerService.shared.info(module: "ProfileView", message: "mailData 已创建，附件大小：\(logData.count) 字节")
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "导出日志失败：\(error.localizedDescription)"
                        showingEmailAlert = true
                        LoggerService.shared.error(module: "ProfileView", message: "导出日志失败：\(error.localizedDescription)")
                    }
                }
            }
        } else {
            mailData = MailData(subject: subject, body: body, attachmentData: nil)
            LoggerService.shared.info(module: "ProfileView", message: "打开bug反馈邮件编辑器（不附带日志）")
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
                    
                    // HStack {
                    //     Image(systemName: "wifi")
                    //         .foregroundColor(.green)
                    //         .frame(width: 24)
                        
                    //     VStack(alignment: .leading, spacing: 4) {
                    //         Text("仅WiFi下载")
                    //         Text("大文件仅在WiFi环境下载载")
                    //             .font(.caption)
                    //             .foregroundColor(.secondary)
                    //     }
                        
                    //     Spacer()
                        
                    //     Toggle("", isOn: .constant(true))
                    // }
                }
                
                // 阅读设置
                // Section("阅读") {
                //     HStack {
                //         Image(systemName: "pencil.tip.crop.circle")
                //             .foregroundColor(.purple)
                //             .frame(width: 24)
                        
                //         VStack(alignment: .leading, spacing: 4) {
                //             Text("默认标注工具")
                //             Text("打开PDF时的默认标注工具")
                //                 .font(.caption)
                //                 .foregroundColor(.secondary)
                //         }
                        
                //         Spacer()
                        
                //         Picker("标注工具", selection: .constant(AnnotationTool.pen)) {
                //             ForEach(AnnotationTool.allCases, id: \.self) { tool in
                //                 Text(tool.displayName).tag(tool)
                //             }
                //         }
                //         .pickerStyle(.menu)
                //     }
                    
                //     HStack {
                //         Image(systemName: "hand.draw")
                //             .foregroundColor(.red)
                //             .frame(width: 24)
                        
                //         VStack(alignment: .leading, spacing: 4) {
                //             Text("Apple Pencil 支持")
                //             Text("启用Apple Pencil专用功能")
                //                 .font(.caption)
                //                 .foregroundColor(.secondary)
                //         }
                        
                //         Spacer()
                        
                //         Toggle("", isOn: .constant(true))
                //     }
                // }
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
                    
                    // GitHub 链接
                    Button {
                        if let url = URL(string: "https://github.com/star-reader/eAIP-Pad-FrontEnd") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .font(.title3)
                            Text("在 GitHub 上查看源码")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.orange)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    
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

// MARK: - 邮件数据模型
struct MailData: Identifiable {
    let id = UUID()
    let subject: String
    let body: String
    let attachmentData: Data?
}

// MARK: - 邮件编辑器视图
struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let attachmentData: Data?
    let onDismiss: (MFMailComposeResult) -> Void
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        LoggerService.shared.info(module: "MailComposeView", message: "开始创建邮件编辑器")
        LoggerService.shared.info(module: "MailComposeView", message: "附件数据: \(attachmentData?.count ?? 0) 字节")
        
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(["jinch2287@gmail.com"])
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        
        // 如果有附件数据，添加附件
        if let attachmentData = attachmentData {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let filename = "eAIPPad_logs_\(timestamp).txt"
            
            LoggerService.shared.info(module: "MailComposeView", message: "准备添加附件：\(filename)，大小：\(attachmentData.count) 字节")
            
            composer.addAttachmentData(
                attachmentData,
                mimeType: "text/plain",
                fileName: filename
            )
            
            LoggerService.shared.info(module: "MailComposeView", message: "✓ 已成功添加日志附件：\(filename)")
        } else {
            LoggerService.shared.warning(module: "MailComposeView", message: "⚠️ attachmentData 为 nil，未添加附件")
        }
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: (MFMailComposeResult) -> Void
        
        init(onDismiss: @escaping (MFMailComposeResult) -> Void) {
            self.onDismiss = onDismiss
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error = error {
                LoggerService.shared.error(module: "MailComposeView", message: "邮件发送错误：\(error.localizedDescription)")
            }
            
            switch result {
            case .sent:
                LoggerService.shared.info(module: "MailComposeView", message: "邮件已发送")
            case .saved:
                LoggerService.shared.info(module: "MailComposeView", message: "邮件已保存为草稿")
            case .cancelled:
                LoggerService.shared.info(module: "MailComposeView", message: "用户取消发送邮件")
            case .failed:
                LoggerService.shared.error(module: "MailComposeView", message: "邮件发送失败")
            @unknown default:
                LoggerService.shared.warning(module: "MailComposeView", message: "未知的邮件发送结果")
            }
            
            controller.dismiss(animated: true) {
                self.onDismiss(result)
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
