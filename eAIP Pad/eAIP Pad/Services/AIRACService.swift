import Combine
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AIRAC 版本管理服务
@MainActor
final class AIRACService: ObservableObject {
    static let shared = AIRACService()

    @Published var isUpdating = false
    @Published var updateProgress: Double = 0
    @Published var updateMessage = ""
    @Published var errorMessage: String?
    @Published private(set) var dataRevision: UInt = 0

    private let packageStore = AIRACPackageStore()
    private init() {}

    /// 文件校验和写入全部成功后，才提交当前周期和元数据。
    func importLocalPackage(
        from sourceURL: URL, isZIPArchive: Bool = false, modelContext: ModelContext
    ) async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        errorMessage = nil
        updateProgress = 0
        updateMessage = "读取数据包..."
        let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
            isUpdating = false
        }
        guard scopedAccess || FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            errorMessage = "无法访问所选数据包，请重新选择"
            return false
        }

        do {
            try await packageStore.importPackage(
                from: sourceURL, isZIPArchive: isZIPArchive, modelContext: modelContext
            ) { [weak self] progress, message in
                self?.updateProgress = progress
                self?.updateMessage = message
                await Task.yield()
            }
            dataRevision &+= 1
            LoggerService.shared.info(module: "AIRACService", message: "AIRAC 数据包导入完成")
            return true
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
            LoggerService.shared.error(module: "AIRACService", message: errorMessage ?? "导入失败")
            return false
        }
    }

    func getCacheSize() -> String {
        PDFCacheService.shared.getFormattedTotalCacheSize()
    }

    /// 删除导入内容和所有周期标记，保留用户收藏和标注。
    func clearAllCache(modelContext: ModelContext) async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        errorMessage = nil
        updateMessage = "清理 AIRAC 数据..."
        defer {
            isUpdating = false
            // 即使最后的文件回收报错，页面也应重新读取已经提交的数据状态。
            dataRevision &+= 1
        }
        do {
            try packageStore.clearAll(modelContext: modelContext)
            URLCache.shared.removeAllCachedResponses()
            updateMessage = "缓存清理完成"
            return true
        } catch {
            errorMessage = "清理缓存失败: \(error.localizedDescription)"
            LoggerService.shared.error(module: "AIRACService", message: errorMessage ?? "清理失败")
            return false
        }
    }
}

// MARK: - AIRAC 导入视图
struct AIRACUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var airacService = AIRACService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var showingPackagePicker = false
    @State private var selectingZIP = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    importContent

                    if !airacService.isUpdating {
                        localImportSection
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("AIRAC 数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !airacService.isUpdating {
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) {
                                dismiss()
                            }
                        }
                    } else {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("关闭") {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.25),
                value: airacService.isUpdating
            )
        }
        .interactiveDismissDisabled(airacService.isUpdating)
        .fileImporter(
            isPresented: $showingPackagePicker, allowedContentTypes: selectingZIP ? [.zip] : [.folder]
        ) { result in
            switch result {
            case .success(let url):
                let isZIPArchive = selectingZIP
                Task {
                    let succeeded = await airacService.importLocalPackage(
                        from: url, isZIPArchive: isZIPArchive, modelContext: modelContext)
                    if succeeded {
                        dismiss()
                    }
                }
            case .failure(let error):
                airacService.errorMessage = "选择数据包失败: \(error.localizedDescription)"
            }
        }
    }

    private var importContent: some View {
        VStack(spacing: 24) {
            StateMessageContent(
                title: airacService.isUpdating ? "正在导入 AIRAC 数据" : "导入 AIRAC 数据包",
                systemImage: airacService.isUpdating ? "arrow.down.doc.fill" : "tray.and.arrow.down.fill",
                description: airacService.isUpdating
                    ? "请保持应用开启，完成后即可离线浏览。"
                    : "选择从 EAIP China 官网下载的 Web 数据包，支持 ZIP 文件或已解压的文件夹。"
            )
            .id(airacService.isUpdating)
            .transition(.opacity)

            if airacService.isUpdating {
                VStack(spacing: 12) {
                    ProgressView(value: airacService.updateProgress)
                        .tint(.blue)
                        .accessibilityLabel("导入进度")

                    Text(airacService.updateProgress, format: .percent.precision(.fractionLength(0)))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text(airacService.updateMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 340)
                .transition(.opacity)
            } else if let errorMessage = airacService.errorMessage {
                Label {
                    Text(errorMessage)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: 340, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                .modifier(StateEntranceModifier())
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var localImportSection: some View {
        AIRACDataActionSection(title: "本地导入") {
            AIRACDataActionRow(
                title: "选择 ZIP 文件",
                subtitle: "自动解压并导入数据包",
                systemImage: "doc.zipper"
            ) {
                selectingZIP = true
                showingPackagePicker = true
            }

            Divider()
                .padding(.leading, 68)

            AIRACDataActionRow(
                title: "选择已解压文件夹",
                subtitle: "从解压后的 Web 数据包导入",
                systemImage: "folder"
            ) {
                selectingZIP = false
                showingPackagePicker = true
            }
        }
    }
}

// 数据入口按用途分组，后续在线数据源配置可使用同样的分组和行。
private struct AIRACDataActionSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0, content: content)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

private struct AIRACDataActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AIRACDataActionButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct AIRACDataActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : .clear)
    }
}

#Preview {
    AIRACUpdateView()
        .modelContainer(for: AIRACVersion.self, inMemory: true)
}
