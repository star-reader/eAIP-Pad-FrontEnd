import Combine
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AIRAC 版本管理服务
// 数据来源改为手动导入官方 EAIP Web 包（不再联网同步），详见 importLocalPackage。
class AIRACService: ObservableObject {
    static let shared = AIRACService()

    @Published var isUpdating = false
    @Published var updateProgress: Double = 0.0
    @Published var updateMessage = ""
    @Published var errorMessage: String?

    private init() {}

    // MARK: - 导入本地 EAIP Web 包
    /// folderURL 指向解压后的包根目录（内部应包含 Data/Customers.js 和 Data/JsonPath/*.JSON）
    @MainActor
    func importLocalPackage(from folderURL: URL, modelContext: ModelContext) async -> Bool {
        LoggerService.shared.info(module: "AIRACService", message: "importLocalPackage started: \(folderURL)")
        isUpdating = true
        await setImportProgress(0, message: "读取数据包...")
        errorMessage = nil

        guard folderURL.startAccessingSecurityScopedResource() else {
            errorMessage = "无法访问所选文件夹，请重新选择"
            isUpdating = false
            return false
        }

        defer {
            folderURL.stopAccessingSecurityScopedResource()
            isUpdating = false
        }

        do {
            await setImportProgress(0.05, message: "解析数据包...")

            let parsed = try await Task.detached(priority: .userInitiated) {
                try LocalAIRACPackageParser.parse(folderURL: folderURL)
            }.value

            LoggerService.shared.info(
                module: "AIRACService",
                message: "共解析出 \(parsed.airports.count) 个机场，\(parsed.charts.count) 条文档/航图记录")

            let version = parsed.version

            let allVersionsDescriptor = FetchDescriptor<AIRACVersion>()
            let allVersions = try modelContext.fetch(allVersionsDescriptor)
            for existing in allVersions {
                existing.isCurrent = (existing.version == version)
            }
            if !allVersions.contains(where: { $0.version == version }) {
                let newVersion = AIRACVersion(
                    version: version, effectiveDate: parsed.effectiveDate, isCurrent: true, source: "local")
                modelContext.insert(newVersion)
            }

            await setImportProgress(0.35, message: "写入机场数据...")
            for airport in parsed.airports {
                let icao = airport.icao
                let descriptor = FetchDescriptor<Airport>(
                    predicate: #Predicate<Airport> { $0.icao == icao })
                if try modelContext.fetch(descriptor).isEmpty {
                    modelContext.insert(
                        Airport(icao: airport.icao, nameEn: airport.nameEn, nameCn: airport.nameCn))
                }
            }
            try modelContext.save()

            let total = parsed.charts.count
            for (index, pending) in parsed.charts.enumerated() {
                let documentID = pending.documentID
                let descriptor = FetchDescriptor<LocalChart>(
                    predicate: #Predicate<LocalChart> { $0.documentID == documentID })
                if try modelContext.fetch(descriptor).isEmpty {
                    let chart = LocalChart(
                        chartID: pending.chartID,
                        documentID: pending.documentID,
                        nameEn: pending.nameEn,
                        nameCn: pending.nameCn,
                        chartType: pending.chartType,
                        airacVersion: version,
                        documentType: pending.documentType
                    )
                    chart.icao = pending.icao
                    chart.parentID = pending.parentID
                    chart.isModified = pending.isModified
                    chart.category = pending.category
                    chart.serialNumber = pending.serialNumber
                    chart.subject = pending.subject
                    chart.localSubject = pending.localSubject
                    chart.chapterType = pending.chapterType
                    chart.effectiveTime = pending.effectiveTime
                    chart.outDate = pending.outDate
                    chart.pubDate = pending.pubDate
                    chart.seriesName = pending.seriesName
                    chart.generateTime = pending.generateTime
                    chart.generateTimeEn = pending.generateTimeEn
                    modelContext.insert(chart)
                }

                if let relativePdfPath = pending.pdfPath, !relativePdfPath.isEmpty {
                    let cleanedPath =
                        relativePdfPath.hasPrefix("/")
                        ? String(relativePdfPath.dropFirst()) : relativePdfPath
                    let sourceURL = folderURL.appendingPathComponent(cleanedPath)
                    let pdfData = await Task.detached(priority: .utility) {
                        try? Data(contentsOf: sourceURL)
                    }.value
                    if let pdfData {
                        try? PDFCacheService.shared.saveToCache(
                            pdfData: pdfData, airacVersion: version,
                            documentType: pending.documentType, id: pending.documentID)
                    }
                }

                let done = index + 1
                if done % 10 == 0 || done == total {
                    let progress = 0.35 + (Double(done) / Double(max(total, 1))) * 0.6
                    await setImportProgress(
                        progress, message: "导入航图数据... (\(done)/\(total))")
                }

                if done % 25 == 0 {
                    try? modelContext.save()
                }
            }
            try modelContext.save()

            await setImportProgress(1.0, message: "导入完成")
            await cleanupOldVersions(modelContext: modelContext)

            LoggerService.shared.info(module: "AIRACService", message: "importLocalPackage completed")
            return true
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
            LoggerService.shared.error(module: "AIRACService", message: "导入失败: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    private func setImportProgress(_ progress: Double, message: String) async {
        updateProgress = progress
        updateMessage = message
        await Task.yield()
    }

    // MARK: - 清理旧版本数据
    @MainActor
    func cleanupOldVersions(modelContext: ModelContext) async {
        do {
            LoggerService.shared.log(
                type: .info, module: "AIRACService", message: "cleanupOldVersions started")
            updateMessage = "清理旧版本数据..."

            // 获取所有版本，保留最新的3个版本
            let allVersionsDescriptor = FetchDescriptor<AIRACVersion>(
                sortBy: [SortDescriptor(\.effectiveDate, order: .reverse)]
            )
            let allVersions = try modelContext.fetch(allVersionsDescriptor)
            if allVersions.count > 3 {
                let versionsToDelete = Array(allVersions.dropFirst(3))
                for version in versionsToDelete {
                    // 删除相关的航图数据
                    let versionString = version.version
                    let chartsDescriptor = FetchDescriptor<LocalChart>(
                        predicate: #Predicate<LocalChart> { chart in
                            chart.airacVersion == versionString
                        }
                    )
                    let chartsToDelete = try modelContext.fetch(chartsDescriptor)
                    for chart in chartsToDelete {
                        modelContext.delete(chart)
                    }
                    // 删除版本记录
                    modelContext.delete(version)

                    PDFCacheService.shared.clearCacheForVersion(versionString)
                    PDFCacheService.shared.clearDataCacheForVersion(versionString)
                }
                try modelContext.save()
            }
        } catch {
            LoggerService.shared.error(
                module: "AIRACService", message: "清理旧版本数据失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 获取缓存大小
    func getCacheSize() -> String {
        return PDFCacheService.shared.getFormattedTotalCacheSize()
    }

    // MARK: - 强制清理所有缓存
    @MainActor
    func clearAllCache(modelContext: ModelContext) async {
        LoggerService.shared.info(module: "AIRACService", message: "开始清理所有缓存")
        isUpdating = true
        updateMessage = "清理缓存..."

        do {
            let allVersionsDescriptor = FetchDescriptor<AIRACVersion>()
            let allVersions = try modelContext.fetch(allVersionsDescriptor)
            let nonCurrentVersions = allVersions.filter { !$0.isCurrent }

            for version in nonCurrentVersions {
                let versionString = version.version
                let chartsDescriptor = FetchDescriptor<LocalChart>(
                    predicate: #Predicate<LocalChart> { chart in
                        chart.airacVersion == versionString
                    }
                )
                let chartsToDelete = try modelContext.fetch(chartsDescriptor)
                for chart in chartsToDelete {
                    modelContext.delete(chart)
                }
                modelContext.delete(version)
            }

            try modelContext.save()
            PDFCacheService.shared.clearAllCache()
            PDFCacheService.shared.clearDataCache()

            updateMessage = "缓存清理完成"
            LoggerService.shared.info(module: "AIRACService", message: "所有缓存清理完成")
        } catch {
            errorMessage = "清理缓存失败: \(error.localizedDescription)"
            LoggerService.shared.error(
                module: "AIRACService", message: "清理缓存失败: \(error.localizedDescription)")
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isUpdating = false
    }
}

// MARK: - AIRAC 导入视图
struct AIRACUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var airacService = AIRACService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var showingFolderPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !airacService.isUpdating {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 8) {
                        Text("导入 AIRAC 数据包")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("请选择从 EAIP China 官网下载并解压后的 Web 数据包文件夹")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if let errorMessage = airacService.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
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
                if airacService.isUpdating {
                    SheetWideBottomInset(height: 72) {
                        VStack(spacing: 10) {
                            Text(airacService.updateMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            ProgressView(value: airacService.updateProgress)
                                .progressViewStyle(.linear)
                        }
                    }
                } else {
                    SheetWideBottomInset(height: 112) {
                        VStack(spacing: 12) {
                            selectFolderButton
                            doneButton
                        }
                    }
                }
            }
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
