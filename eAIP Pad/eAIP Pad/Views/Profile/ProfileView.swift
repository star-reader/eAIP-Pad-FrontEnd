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
    
    // MARK: - 缓存管理
    
    private func clearCache() async {
        do {
            for version in airacVersions {
                let versionString = version.version
                let chartsDescriptor = FetchDescriptor<LocalChart>(
                    predicate: #Predicate<LocalChart> { chart in
                        chart.airacVersion == versionString
                    }
                )
                let chartsToDelete = try modelContext.fetch(chartsDescriptor)
                chartsToDelete.forEach { modelContext.delete($0) }
                
                PDFCacheService.shared.clearCacheForVersion(versionString)
                PDFCacheService.shared.clearDataCacheForVersion(versionString)
                
                if !version.isCurrent {
                    modelContext.delete(version)
                }
            }
            
            URLCache.shared.removeAllCachedResponses()
            try modelContext.save()
            await updateCacheSize()
            
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
        let formatted = PDFCacheService.shared.getFormattedTotalCacheSize()
        await MainActor.run {
            cacheSizeText = formatted
        }
    }
    
    // MARK: - 账户管理
    
    private func handleSignOut() {
        LoggerService.shared.info(module: "ProfileView", message: "用户点击退出登录")
        AuthenticationService.shared.signOut()
        LoggerService.shared.info(module: "ProfileView", message: "用户已成功退出登录")
    }
    
    // MARK: - 外部链接
    
    private func openGitHub() {
        openURL("https://github.com/star-reader/eAIP-Pad-FrontEnd", name: "GitHub")
    }
    
    private func openPrivacyPolicy() {
        openURL("https://github.com/star-reader/eAIP-Pad-FrontEnd/wiki/Privacy-Policy", name: "隐私政策")
    }
    
    private func openTermsOfService() {
        openURL("https://github.com/star-reader/eAIP-Pad-FrontEnd/wiki/Terms-of-Service", name: "服务条款")
    }
    
    private func openURL(_ urlString: String, name: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
            LoggerService.shared.info(module: "ProfileView", message: "打开\(name)链接：\(urlString)")
        }
    }
    
    // MARK: - 邮件反馈
    
    private func sendNewIdeaEmail() {
        LoggerService.shared.info(module: "ProfileView", message: "用户点击「我有新想法」")
        guard checkMailAvailability() else { return }
        
        let subject = "eAIP Pad - 新想法反馈"
        let body = createEmailBody(prompt: "请在上方描述您的想法或建议")
        mailData = MailData(subject: subject, body: body, attachmentData: nil)
        LoggerService.shared.info(module: "ProfileView", message: "打开新想法邮件编辑器")
    }
    
    private func sendBugReportEmail(withLogs: Bool) {
        LoggerService.shared.info(module: "ProfileView", message: "用户点击「反馈bug」，附带日志：\(withLogs)")
        guard checkMailAvailability() else { return }
        
        let subject = "eAIP Pad - Bug 反馈"
        let body = createEmailBody(prompt: "请在上方描述您遇到的问题")
        
        if withLogs {
            Task {
                do {
                    LoggerService.shared.info(module: "ProfileView", message: "开始导出日志文件")
                    let logFileURL = try await LoggerService.shared.exportLogsAsFile()
                    let logData = try Data(contentsOf: logFileURL)
                    
                    await MainActor.run {
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
    
    private func checkMailAvailability() -> Bool {
        guard MFMailComposeViewController.canSendMail() else {
            errorMessage = "请确保您的设备已设置邮件账户，或者直接发送邮件至：jinch2287@gmail.com"
            showingEmailAlert = true
            LoggerService.shared.warning(module: "ProfileView", message: "设备无法发送邮件")
            return false
        }
        return true
    }
    
    private func createEmailBody(prompt: String) -> String {
        return """
        
        
        ───────────────────────────
        \(prompt)
        
        系统信息：
        • 设备型号：\(UIDevice.current.model)
        • 系统版本：iOS \(UIDevice.current.systemVersion)
        • App 版本：1.0.0 (Build 1)
        """
    }
}


#Preview("Profile") {
    ProfileView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
