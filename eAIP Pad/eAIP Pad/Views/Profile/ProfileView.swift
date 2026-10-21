import SwiftUI
import MessageUI
import SwiftData
import Foundation

// MARK: - 个人中心视图
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pinnedCharts: [PinnedChart]
    @Query private var airacVersions: [AIRACVersion]
    @ObservedObject private var airacService = AIRACService.shared
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingAIRACImport = false
    @State private var showingCacheCleared = false
    @State private var showingCacheError = false
    @State private var showingCacheActions = false
    @State private var showingDeleteAllConfirmation = false
    @State private var cacheResultMessage = ""
    @State private var showingEmailAlert = false
    @State private var showingBugReportOptions = false
    @State private var cacheSizeText: String = ""
    @State private var errorMessage: String = ""
    @State private var mailData: MailData?

    private var currentAIRAC: AIRACVersion? {
        airacVersions.first { $0.isCurrent }
    }
    
    var body: some View {
        List {
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
            .compactListRow()

            Section("应用设置") {
                Button {
                    showingAIRACImport = true
                } label: {
                    SettingRow(
                        icon: "tray.and.arrow.down.fill",
                        title: "导入 AIRAC 数据包",
                        color: .blue
                    )
                }

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
                    showingCacheActions = true
                } label: {
                    SettingRow(
                        icon: "trash.fill",
                        title: "管理 AIRAC 数据",
                        color: .red,
                        trailingText: cacheSizeText
                    )
                }
                .disabled(airacService.isUpdating)
                .confirmationDialog("管理 AIRAC 数据", isPresented: $showingCacheActions, titleVisibility: .visible) {
                    Button("清理旧周期") {
                        Task { await clearCache() }
                    }
                    Button("删除全部 AIRAC 数据", role: .destructive) {
                        showingDeleteAllConfirmation = true
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("清理旧周期会保留当前周期的离线资料、服务器配置、收藏和标注。")
                }
            }
            .compactListRow()

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

                if let url = URL(string: "https://testflight.apple.com/join/4ctRjbAq") {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            AppSymbolView(systemImage: "app.badge", size: .compact)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("加入 TestFlight")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text("抢先体验新功能，帮助改进 eAIP Pad")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("打开 TestFlight 邀请页面")
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
                        color: .orange
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
            }
            .compactListRow()

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
            .compactListRow()
        }
        .airacNavigationTitle("个人")
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingAIRACImport) {
            AIRACUpdateView()
        }
        .alert("删除全部 AIRAC 数据？", isPresented: $showingDeleteAllConfirmation) {
            Button("删除全部数据", role: .destructive) {
                Task { await clearCache(includingCurrent: true) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有周期的离线资料和在线服务器配置，需要重新导入或配置后才能浏览。收藏和标注会保留。")
        }
        .alert("数据清理完成", isPresented: $showingCacheCleared) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(cacheResultMessage)
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
        .task(id: airacService.dataRevision) {
            await updateCacheSize()
        }
    }
    
    // MARK: - 缓存管理
    
    private func clearCache(includingCurrent: Bool = false) async {
        showingCacheCleared = false
        showingCacheError = false
        let succeeded = await airacService.clearAllCache(modelContext: modelContext, includingCurrent: includingCurrent)
        await updateCacheSize()
        if succeeded {
            cacheResultMessage = includingCurrent
                ? "已删除全部 AIRAC 数据和服务器配置，收藏和标注已保留。"
                : "已清理旧周期，当前离线资料、服务器配置、收藏和标注已保留。"
            showingCacheCleared = true
        } else {
            errorMessage = airacService.errorMessage ?? "已有 AIRAC 操作正在进行，请稍后重试"
            showingCacheError = true
        }
    }

    private func updateCacheSize() async {
        let scan = Task.detached(priority: .utility) { try AIRACFileStore.shared.totalCacheSize() }
        do {
            let size = try await withTaskCancellationHandler {
                try await scan.value
            } onCancel: { scan.cancel() }
            guard !Task.isCancelled else { return }
            cacheSizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } catch {
            if !Task.isCancelled { cacheSizeText = "暂不可用" }
        }
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
        • App 版本：\(AppVersion.appVersion)
        """
    }
}


#Preview("Profile") {
    ProfileView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
