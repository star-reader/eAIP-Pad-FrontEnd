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
    func importLocalPackage(from folderURL: URL, modelContext: ModelContext) async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        errorMessage = nil
        updateProgress = 0
        updateMessage = "读取数据包..."
        let scopedAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess { folderURL.stopAccessingSecurityScopedResource() }
            isUpdating = false
        }
        guard scopedAccess || FileManager.default.isReadableFile(atPath: folderURL.path) else {
            errorMessage = "无法访问所选文件夹，请重新选择"
            return false
        }

        do {
            try await packageStore.importPackage(from: folderURL, modelContext: modelContext) { [weak self] progress, message in
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
    @State private var showingFolderPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    importContent
                        .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !airacService.isUpdating {
                    SheetWideBottomInset {
                        VStack(spacing: 12) {
                            selectFolderButton
                            doneButton
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
            isPresented: $showingFolderPicker, allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    let succeeded = await airacService.importLocalPackage(
                        from: url, modelContext: modelContext)
                    if succeeded {
                        dismiss()
                    }
                }
            case .failure(let error):
                airacService.errorMessage = "选择文件夹失败: \(error.localizedDescription)"
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
                    : "选择从 EAIP China 官网下载\n并解压后的 Web 数据包文件夹。"
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
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var selectFolderButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                showingFolderPicker = true
            } label: {
                Label("选择文件夹", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        } else {
            Button {
                showingFolderPicker = true
            } label: {
                Label("选择文件夹", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        } else {
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    AIRACUpdateView()
        .modelContainer(for: AIRACVersion.self, inMemory: true)
}
