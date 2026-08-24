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
    func importLocalPackage(from folderURL: URL, modelContext: ModelContext) async {
        LoggerService.shared.info(module: "AIRACService", message: "importLocalPackage started: \(folderURL)")
        isUpdating = true
        updateProgress = 0.0
        updateMessage = "读取数据包..."
        errorMessage = nil

        guard folderURL.startAccessingSecurityScopedResource() else {
            errorMessage = "无法访问所选文件夹，请重新选择"
            isUpdating = false
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        do {
            let dataURL = folderURL.appendingPathComponent("Data")
            let jsonPathURL = dataURL.appendingPathComponent("JsonPath")

            // 1. 解析 AIRAC 版本信息（Customers.js 是 `var Customers=[{...}];` 形式，需要先剥离变量声明）
            let customersURL = dataURL.appendingPathComponent("Customers.js")
            let customersRaw = try String(contentsOf: customersURL, encoding: .utf8)
            let customer = try parseCustomer(customersRaw)
            let version = customer.dataVersion
            let effectiveDate = parseEAIPDate(customer.effectiveDate) ?? Date()

            LoggerService.shared.info(module: "AIRACService", message: "解析到 AIRAC 版本: \(version)")
            updateProgress = 0.05
            updateMessage = "解析航图目录..."

            // 2. 校验实际存放 PDF 的包目录存在（Data/ 下除 JsonPath 外的那个子目录，如 EAIP2026-08.V1.5）
            _ = try findPackageRoot(under: dataURL)

            // 3. 解析各分类 JSON，得到待入库的机场/航图/文档条目
            var pendingCharts: [PendingChart] = []
            var pendingAirports: [String: (nameEn: String, nameCn: String)] = [:]

            try parseAD(
                jsonPathURL.appendingPathComponent("AD.JSON"), version: version,
                charts: &pendingCharts, airports: &pendingAirports)
            updateProgress = 0.2
            updateMessage = "解析 GEN/ENR 文档..."

            try parseGEN(jsonPathURL.appendingPathComponent("GEN.JSON"), version: version, charts: &pendingCharts)
            try parseENR(jsonPathURL.appendingPathComponent("ENR.JSON"), version: version, charts: &pendingCharts)
            updateProgress = 0.3
            updateMessage = "解析 SUP/NOTAM 文档..."

            try parseSUP(jsonPathURL.appendingPathComponent("SUP.JSON"), version: version, charts: &pendingCharts)
            try parseNOTAM(jsonPathURL.appendingPathComponent("NOTAM.JSON"), version: version, charts: &pendingCharts)

            LoggerService.shared.info(
                module: "AIRACService",
                message: "共解析出 \(pendingAirports.count) 个机场，\(pendingCharts.count) 条文档/航图记录")

            // 4. 写入 AIRACVersion（新版本设为当前，其余标记为非当前）
            let allVersionsDescriptor = FetchDescriptor<AIRACVersion>()
            let allVersions = try modelContext.fetch(allVersionsDescriptor)
            for existing in allVersions {
                existing.isCurrent = (existing.version == version)
            }
            if !allVersions.contains(where: { $0.version == version }) {
                let newVersion = AIRACVersion(
                    version: version, effectiveDate: effectiveDate, isCurrent: true, source: "local")
                modelContext.insert(newVersion)
            }

            // 5. 写入机场
            updateProgress = 0.35
            updateMessage = "写入机场数据..."
            for (icao, info) in pendingAirports {
                let descriptor = FetchDescriptor<Airport>(
                    predicate: #Predicate<Airport> { $0.icao == icao })
                if try modelContext.fetch(descriptor).isEmpty {
                    let airport = Airport(icao: icao, nameEn: info.nameEn, nameCn: info.nameCn)
                    modelContext.insert(airport)
                }
            }
            try modelContext.save()

            // 6. 写入航图/文档记录 + 拷贝 PDF
            let total = pendingCharts.count
            var done = 0
            for pending in pendingCharts {
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

                // 拷贝 PDF 到 PDFCacheService 的缓存目录
                if let relativePdfPath = pending.pdfPath, !relativePdfPath.isEmpty {
                    let cleanedPath = relativePdfPath.hasPrefix("/") ? String(relativePdfPath.dropFirst()) : relativePdfPath
                    // relativePdfPath 形如 "Data/EAIP2026-08.V1.5/Terminal/ZBAA/xxx.pdf"，需要相对于 folderURL 解析
                    let sourceURL = folderURL.appendingPathComponent(cleanedPath)
                    if let pdfData = try? Data(contentsOf: sourceURL) {
                        try? PDFCacheService.shared.saveToCache(
                            pdfData: pdfData, airacVersion: version,
                            documentType: pending.documentType, id: pending.documentID)
                    }
                }

                done += 1
                if done % 25 == 0 {
                    updateProgress = 0.35 + (Double(done) / Double(max(total, 1))) * 0.6
                    updateMessage = "导入航图数据... (\(done)/\(total))"
                    try? modelContext.save()
                }
            }
            try modelContext.save()

            updateProgress = 1.0
            updateMessage = "导入完成"

            // 7. 清理旧版本，只保留最新 3 个
            await cleanupOldVersions(modelContext: modelContext)

            LoggerService.shared.info(module: "AIRACService", message: "importLocalPackage completed")
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
            LoggerService.shared.error(module: "AIRACService", message: "导入失败: \(error.localizedDescription)")
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isUpdating = false
    }

    // MARK: - 解析辅助结构
    private struct PendingChart {
        let chartID: String
        let documentID: String
        let nameEn: String
        let nameCn: String
        let chartType: String
        let documentType: String
        let pdfPath: String?
        var icao: String?
        var parentID: String?
        var isModified: Bool = false
        var category: String?
        var serialNumber: String?
        var subject: String?
        var localSubject: String?
        var chapterType: String?
        var effectiveTime: String?
        var outDate: String?
        var pubDate: String?
        var seriesName: String?
        var generateTime: String?
        var generateTimeEn: String?
    }

    /// Customers.js 是 `var Customers=[{ IataCode:"", DataName:"2026-08", ... }];` 形式的
    /// JS 对象字面量（键名不带引号），不是合法 JSON，不能直接用 JSONDecoder 解析，
    /// 这里改成按 key:"value" 逐个抽取。
    private func parseCustomer(_ raw: String) throws -> EAIPCustomer {
        func extract(_ key: String) -> String? {
            guard let keyRange = raw.range(of: "\(key):\"") else { return nil }
            let afterKey = raw[keyRange.upperBound...]
            guard let endQuote = afterKey.firstIndex(of: "\"") else { return nil }
            return String(afterKey[..<endQuote])
        }

        guard let dataVersion = extract("DataVersion"), !dataVersion.isEmpty,
            let effectiveDate = extract("EffectiveDate"), !effectiveDate.isEmpty
        else {
            throw NSError(
                domain: "AIRACService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法解析 Customers.js 中的 AIRAC 版本信息"])
        }

        return EAIPCustomer(
            dataName: extract("DataName") ?? dataVersion,
            dataVersion: dataVersion,
            effectiveDate: effectiveDate,
            deadline: extract("Deadline") ?? "",
            publishDate: extract("PublishDate") ?? "")
    }

    /// EAIP 日期格式形如 "2608051600" = YY MM DD HH mm
    private func parseEAIPDate(_ raw: String) -> Date? {
        guard raw.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }

    private func findPackageRoot(under dataURL: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: dataURL, includingPropertiesForKeys: [.isDirectoryKey])
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir && url.lastPathComponent != "JsonPath" {
                return url
            }
        }
        throw NSError(
            domain: "AIRACService", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "未找到航图数据目录"])
    }

    /// 官方包里的 .JSON 文件带 UTF-8 BOM，JSONDecoder 遇到开头的 BOM 字节会解析失败，先去掉。
    private func stripBOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.starts(with: bom) {
            return data.dropFirst(bom.count)
        }
        return data
    }

    private func loadNodes(_ url: URL) throws -> [EAIPTreeNode] {
        let data = stripBOM(try Data(contentsOf: url))
        return try JSONDecoder().decode([EAIPTreeNode].self, from: data)
    }

    // MARK: - AD.JSON：机场 + AD 细则 + 航图
    private func parseAD(
        _ url: URL, version: String, charts: inout [PendingChart],
        airports: inout [String: (nameEn: String, nameCn: String)]
    ) throws {
        let nodes = try loadNodes(url)
        let byParent = Dictionary(grouping: nodes, by: { $0.pId })

        let airportRoots = nodes.filter { ($0.airporticao?.isEmpty == false) }
        for root in airportRoots {
            guard let icao = root.airporticao else { continue }

            let nameEn = stripIcaoPrefix(root.name, icao: icao)
            let nameCn = stripIcaoPrefix(root.nameCn, icao: icao)
            airports[icao] = (nameEn: nameEn, nameCn: nameCn)

            // 机场级 AD 细则（整本 PDF）
            charts.append(
                PendingChart(
                    chartID: "ad_\(root.id)", documentID: root.id, nameEn: root.name,
                    nameCn: root.nameCn, chartType: "AD", documentType: "ad",
                    pdfPath: root.pdfPath, icao: icao,
                    isModified: root.isModified == "Y"))

            // 航图（挂在 "Charts related to an aerodrome" 小节下）
            let children = byParent[root.id] ?? []
            guard
                let chartSection = children.first(where: {
                    $0.name.localizedCaseInsensitiveContains("Charts related to an aerodrome")
                })
            else { continue }

            let chartLeaves = byParent[chartSection.id] ?? []
            for leaf in chartLeaves where !leaf.pdfPath.isEmpty {
                charts.append(
                    PendingChart(
                        chartID: "chart_\(leaf.id)", documentID: leaf.id, nameEn: leaf.name,
                        nameCn: leaf.nameCn, chartType: EAIPChartClassifier.classify(name: leaf.name),
                        documentType: "chart", pdfPath: leaf.pdfPath, icao: icao,
                        parentID: root.id, isModified: leaf.isModified == "Y"))
            }
        }
    }

    private func stripIcaoPrefix(_ name: String, icao: String) -> String {
        let prefix = "\(icao)-"
        if name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }

    // MARK: - GEN.JSON：总则文档（归到 AIP - GEN 分类）
    private func parseGEN(_ url: URL, version: String, charts: inout [PendingChart]) throws {
        let nodes = try loadNodes(url)
        for node in nodes where !node.pdfPath.isEmpty {
            charts.append(
                PendingChart(
                    chartID: "aip_\(node.id)", documentID: node.id, nameEn: node.name,
                    nameCn: node.nameCn, chartType: "AIP", documentType: "aip",
                    pdfPath: node.pdfPath, isModified: node.isModified == "Y", category: "GEN"))
        }
    }

    // MARK: - ENR.JSON：航路文档（ENR 6 下是实际航路图，其余是 AIP - ENR 分类文档）
    private func parseENR(_ url: URL, version: String, charts: inout [PendingChart]) throws {
        let nodes = try loadNodes(url)
        let byId = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let byParent = Dictionary(grouping: nodes, by: { $0.pId })

        guard
            let enrChartsRoot = nodes.first(where: {
                $0.name.localizedCaseInsensitiveContains("EN-ROUTE CHARTS")
            })
        else {
            // 找不到航路图小节，全部当作 AIP - ENR 文档处理
            for node in nodes where !node.pdfPath.isEmpty {
                charts.append(
                    PendingChart(
                        chartID: "aip_\(node.id)", documentID: node.id, nameEn: node.name,
                        nameCn: node.nameCn, chartType: "AIP", documentType: "aip",
                        pdfPath: node.pdfPath, isModified: node.isModified == "Y", category: "ENR"))
            }
            return
        }

        // 收集航路图小节下所有后代 id
        var enrouteIds = Set<String>()
        var stack = [enrChartsRoot.id]
        while let current = stack.popLast() {
            for child in byParent[current] ?? [] {
                enrouteIds.insert(child.id)
                stack.append(child.id)
            }
        }

        for node in nodes where !node.pdfPath.isEmpty {
            if enrouteIds.contains(node.id) {
                let enrouteType = EAIPChartClassifier.classifyEnroute(name: node.name)
                charts.append(
                    PendingChart(
                        chartID: "enroute_\(node.id)", documentID: node.id, nameEn: node.name,
                        nameCn: node.nameCn, chartType: enrouteType, documentType: "enroute",
                        pdfPath: node.pdfPath, isModified: node.isModified == "Y"))
            } else if node.id != enrChartsRoot.id {
                charts.append(
                    PendingChart(
                        chartID: "aip_\(node.id)", documentID: node.id, nameEn: node.name,
                        nameCn: node.nameCn, chartType: "AIP", documentType: "aip",
                        pdfPath: node.pdfPath, isModified: node.isModified == "Y", category: "ENR"))
            }
        }
        _ = byId
    }

    // MARK: - SUP.JSON：补充资料
    private func parseSUP(_ url: URL, version: String, charts: inout [PendingChart]) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = stripBOM(try Data(contentsOf: url))
        let docs = try JSONDecoder().decode([EAIPFlatDocument].self, from: data)
        for doc in docs {
            charts.append(
                PendingChart(
                    chartID: "sup_\(doc.id)", documentID: doc.id,
                    nameEn: doc.subject ?? "", nameCn: doc.localSubject ?? "",
                    chartType: "SUP", documentType: "sup", pdfPath: doc.document,
                    isModified: doc.isModified == "Y", serialNumber: doc.serial,
                    subject: doc.subject, localSubject: doc.localSubject,
                    chapterType: doc.chapterType, effectiveTime: doc.effectiveTime,
                    outDate: doc.outDate, pubDate: doc.pubDate))
        }
    }

    // MARK: - NOTAM.JSON：航行通告系列
    private func parseNOTAM(_ url: URL, version: String, charts: inout [PendingChart]) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = stripBOM(try Data(contentsOf: url))
        let docs = try JSONDecoder().decode([EAIPNotamDocument].self, from: data)
        for doc in docs {
            let stableID = "\(doc.seriesName)_\(doc.generateTime)"
            charts.append(
                PendingChart(
                    chartID: "notam_\(stableID)", documentID: stableID,
                    nameEn: "NOTAM \(doc.seriesName)", nameCn: "NOTAM \(doc.seriesName)",
                    chartType: "NOTAM", documentType: "notam", pdfPath: doc.document,
                    seriesName: doc.seriesName, generateTime: doc.generateTime,
                    generateTimeEn: doc.generateTimeEn))
        }
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
                Image(
                    systemName: airacService.isUpdating
                        ? "arrow.clockwise" : "tray.and.arrow.down.fill"
                )
                .font(.system(size: 60))
                .foregroundColor(airacService.isUpdating ? .orange : .blue)
                .rotationEffect(.degrees(airacService.isUpdating ? 360 : 0))
                .animation(
                    .linear(duration: 1).repeatForever(autoreverses: false),
                    value: airacService.isUpdating)

                VStack(spacing: 8) {
                    Text(airacService.isUpdating ? "正在导入..." : "导入 AIRAC 数据包")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        airacService.isUpdating
                            ? airacService.updateMessage
                            : "请选择从 EAIP China 官网下载并解压后的 Web 数据包文件夹"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                }

                if airacService.isUpdating {
                    VStack(spacing: 8) {
                        ProgressView(value: airacService.updateProgress)
                            .progressViewStyle(.linear)

                        Text("\(Int(airacService.updateProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }

                if let errorMessage = airacService.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                if !airacService.isUpdating {
                    VStack(spacing: 12) {
                        Button {
                            showingFolderPicker = true
                        } label: {
                            Label("选择文件夹", systemImage: "folder.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("完成") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("AIRAC 数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !airacService.isUpdating {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("关闭") {
                            dismiss()
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
                    await airacService.importLocalPackage(from: url, modelContext: modelContext)
                }
            case .failure(let error):
                airacService.errorMessage = "选择文件夹失败: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    AIRACUpdateView()
        .modelContainer(for: AIRACVersion.self, inMemory: true)
}
