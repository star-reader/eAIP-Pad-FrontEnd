import Foundation
import OSLog
import SwiftData

/// PDF 准备完成后才修改 SwiftData；一次 save 同时提交目录、计数和当前周期。
@MainActor
final class AIRACPackageStore {
    private let files: AIRACFileStore
    private let saveChanges: (ModelContext) throws -> Void
    private let archiveExtractor: AIRACArchiveExtractor
    private let logger = Logger(subsystem: "eAIP-Pad", category: "AIRACPackageStore")
    private var isImporting = false

    init(
        files: AIRACFileStore = .shared,
        archiveExtractor: AIRACArchiveExtractor = AIRACArchiveExtractor(),
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.files = files
        self.archiveExtractor = archiveExtractor
        self.saveChanges = saveChanges
    }

    func importPackage(
        from sourceURL: URL, isZIPArchive: Bool = false, modelContext: ModelContext,
        progress: (@MainActor (Double, String) async -> Void)? = nil
    ) async throws {
        guard !isImporting else { throw AIRACPackageError.invalidPackage("已有 AIRAC 操作正在进行") }
        isImporting = true
        defer { isImporting = false }

        var extracted: ExtractedAIRACPackage?
        defer {
            if let extracted {
                do { try extracted.remove() }
                catch { logger.warning("临时解压目录清理失败：\(error.localizedDescription)") }
            }
        }
        if isZIPArchive {
            await progress?(0, "正在解压 ZIP 数据包...")
            let extractor = archiveExtractor
            let extractionProgress = Progress(totalUnitCount: 0)
            let updates = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let observation = extractionProgress.observe(\.fractionCompleted) { value, _ in
                updates.continuation.yield(value.fractionCompleted)
            }
            defer { observation.invalidate() }
            let extractionTask = Task.detached(priority: .userInitiated) {
                defer { updates.continuation.finish() }
                return try extractor.extract(at: sourceURL, progress: extractionProgress)
            }
            // 先取得任务结果，再检查取消，确保解压成功时临时目录总能进入 defer 清理。
            extracted = try await withTaskCancellationHandler {
                for await fraction in updates.stream {
                    await progress?(min(max(fraction, 0), 1) * 0.25, "正在解压 ZIP 数据包...")
                }
                return try await extractionTask.value
            } onCancel: {
                extractionProgress.cancel()
                extractionTask.cancel()
            }
            try Task.checkCancellation()
        }
        let folderURL = extracted?.packageURL ?? sourceURL
        let extractionWeight = isZIPArchive ? 0.25 : 0
        let reportProgress: (@MainActor (Double, String) async -> Void) = { fraction, message in
            await progress?(extractionWeight + fraction * (1 - extractionWeight), message)
        }

        await reportProgress(0.05, "解析数据包...")
        let parseTask = Task.detached(priority: .userInitiated) {
            try LocalAIRACPackageParser.parse(folderURL: folderURL)
        }
        let parsed = try await withTaskCancellationHandler {
            try await parseTask.value
        } onCancel: { parseTask.cancel() }
        try Task.checkCancellation()

        await reportProgress(0.15, "校验并保存 \(parsed.charts.count) 份 PDF...")
        let files = self.files
        let prepareTask = Task.detached(priority: .utility) {
            try files.prepare(parsed, from: folderURL)
        }
        let prepared = try await withTaskCancellationHandler {
            try await prepareTask.value
        } onCancel: { prepareTask.cancel() }
        do {
            try Task.checkCancellation()
            await reportProgress(0.9, "提交机场、文档和周期数据...")
            try Task.checkCancellation()
            try commit(parsed, prepared: prepared, modelContext: modelContext)
        } catch {
            try? files.discard(prepared)
            throw error
        }
        await reportProgress(1, "导入完成")
    }

    func configureServer(
        _ configuration: AIRACServerConfiguration, modelContext: ModelContext,
        client: AIRACServerClient = .shared, expectedVersion: String? = nil, expectedDate: Date? = nil,
        progress: (@MainActor (Double, String) async -> Void)? = nil
    ) async throws {
        guard !isImporting else { throw AIRACPackageError.invalidPackage("已有 AIRAC 操作正在进行") }
        isImporting = true
        defer { isImporting = false }
        await progress?(0.02, "读取服务器目录...")
        let parsed = try await client.catalog(
            from: configuration, expectedVersion: expectedVersion, expectedDate: expectedDate)
        let prepared = PreparedAIRACCache(
            version: parsed.version, revision: UUID().uuidString,
            documentCount: configuration.mode == .copy ? parsed.charts.count : 0)
        do {
            if configuration.mode == .copy {
                try await client.copyPDFs(parsed, from: configuration, to: files, revision: prepared.revision) { completed in
                    await progress?(0.1 + 0.8 * Double(completed) / Double(parsed.charts.count),
                        "复制 PDF \(completed) / \(parsed.charts.count)...")
                }
                let latest = try await client.metadata(from: configuration)
                guard latest.version == parsed.version, latest.effectiveDate == parsed.effectiveDate else {
                    throw AIRACPackageError.invalidPackage("复制期间服务器周期已变更，请重新配置")
                }
            }
            try Task.checkCancellation()
            await progress?(0.95, "保存服务器配置...")
            try Task.checkCancellation()
            try commit(parsed, prepared: prepared, modelContext: modelContext, configuration: configuration)
        } catch {
            try? files.discard(prepared)
            throw error
        }
        await progress?(1, "配置完成")
    }

    private func commit(
        _ parsed: ParsedAIRACPackage, prepared: PreparedAIRACCache, modelContext: ModelContext,
        configuration: AIRACServerConfiguration? = nil
    ) throws {
        // 先保存调用方已有的用户设置/收藏，失败回滚只涉及本次导入。
        if modelContext.hasChanges { try modelContext.save() }
        let autosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = autosave }

        let version = parsed.version
        let isRequest = configuration?.mode == .request
        // 请求模式只保存连接配置，目录和 PDF 在使用时获取。
        let storedAirports = isRequest ? [] : parsed.airports
        let storedCharts = isRequest ? [] : parsed.charts
        var evictedVersions: [String] = []
        var previousRevision: String?
        do {
            var versions = try modelContext.fetch(FetchDescriptor<AIRACVersion>())
            let target: AIRACVersion
            if let existing = versions.first(where: { $0.version == version }) {
                target = existing
                previousRevision = existing.cacheRevision
            } else {
                target = AIRACVersion(version: version, effectiveDate: parsed.effectiveDate)
                modelContext.insert(target)
                versions.append(target)
            }

            let allCharts = try modelContext.fetch(FetchDescriptor<LocalChart>())
            let existingCharts = allCharts.filter { $0.airacVersion == version }
            var byReaderID: [String: LocalChart] = [:]
            for chart in existingCharts { byReaderID[chart.readerChartID] = chart }
            let airports = try modelContext.fetch(FetchDescriptor<Airport>())
            var airportsByICAO = Dictionary(uniqueKeysWithValues: airports.map { ($0.icao, $0) })
            let terminalICAOs = Set(parsed.charts.filter { $0.documentType == "chart" }.compactMap(\.icao))
            for pending in storedAirports {
                let airport = airportsByICAO[pending.icao]
                    ?? Airport(icao: pending.icao, nameEn: pending.nameEn, nameCn: pending.nameCn)
                if airportsByICAO[pending.icao] == nil {
                    modelContext.insert(airport)
                    airportsByICAO[pending.icao] = airport
                }
                airport.nameEn = pending.nameEn
                airport.nameCn = pending.nameCn
                airport.isModified = pending.isModified
                airport.hasTerminalCharts = terminalICAOs.contains(pending.icao)
            }

            var incomingKeys = Set<String>()
            for pending in storedCharts {
                let key = AIRACDocumentIdentity.storageID(version: version, readerID: pending.readerID)
                incomingKeys.insert(key)
                let chart = byReaderID[pending.readerID] ?? LocalChart(
                    chartID: key, documentID: pending.documentID, nameEn: pending.nameEn,
                    nameCn: pending.nameCn, chartType: pending.chartType,
                    airacVersion: version, documentType: pending.documentType)
                if byReaderID[pending.readerID] == nil { modelContext.insert(chart) }
                chart.apply(pending, version: version)
            }
            for chart in existingCharts where !incomingKeys.contains(chart.chartID) {
                modelContext.delete(chart)
            }

            try updatePins(parsed, previousCharts: allCharts, modelContext: modelContext)
            target.effectiveDate = parsed.effectiveDate
            target.source = configuration?.mode.source ?? "local"
            target.serverURL = configuration?.rootURL.absoluteString
            target.cacheRevision = isRequest ? nil : prepared.revision
            target.airportICAOs = isRequest ? nil : parsed.airports.map(\.icao)
            target.totalCharts = parsed.charts.count
            target.downloadedCharts = prepared.documentCount
            for item in versions { item.isCurrent = item.version == version }

            // 当前周期必须保留，即使本次手动导入的是更早的周期。
            let newestOthers = versions.filter { $0.version != version }.sorted {
                if $0.effectiveDate != $1.effectiveDate { return $0.effectiveDate > $1.effectiveDate }
                return $0.version > $1.version
            }
            let retained = Set([version] + newestOthers.prefix(2).map(\.version))
            for item in versions where !retained.contains(item.version) {
                evictedVersions.append(item.version)
                for chart in allCharts where chart.airacVersion == item.version { modelContext.delete(chart) }
                modelContext.delete(item)
            }
            try saveChanges(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }

        // 元数据已经提交，旧文件回收失败只会留下不可见的文件，不影响新周期可用性。
        for removed in evictedVersions {
            do { try files.removeVersion(removed) }
            catch { logger.warning("旧周期文件回收失败：\(error.localizedDescription)") }
        }
        if let previousRevision, previousRevision != prepared.revision {
            do { try files.removeRevision(version: version, revision: previousRevision) }
            catch { logger.warning("旧缓存目录回收失败：\(error.localizedDescription)") }
        }
    }

    private func updatePins(
        _ parsed: ParsedAIRACPackage, previousCharts: [LocalChart], modelContext: ModelContext
    ) throws {
        let pendingByID = Dictionary(uniqueKeysWithValues: parsed.charts.map { ($0.readerID, $0) })
        let legacyGroups = Dictionary(grouping: previousCharts) { "\($0.documentType)_\($0.documentID)" }
        let pins = try modelContext.fetch(FetchDescriptor<PinnedChart>())
        var claimedIDs = Set(pins.map(\.chartID))
        for pin in pins {
            var readerID = pin.chartID
            if let legacy = legacyGroups[readerID] {
                let identities = Set(legacy.map(\.readerChartID))
                if identities.count == 1, let canonical = identities.first { readerID = canonical }
            }
            guard let pending = pendingByID[readerID] else { continue }
            if readerID != pin.chartID {
                if claimedIDs.contains(readerID) {
                    modelContext.delete(pin)
                    continue
                }
                claimedIDs.remove(pin.chartID)
                pin.chartID = readerID
                claimedIDs.insert(readerID)
            }
            pin.displayName = pending.nameCn
            pin.icao = pending.icao ?? ""
            pin.type = pending.chartType
            pin.documentType = pending.documentType
            pin.airacVersion = parsed.version
        }
    }

    func clearAll(modelContext: ModelContext) async throws {
        try await removeData(modelContext: modelContext, includingCurrent: true)
    }

    func clearOldVersions(modelContext: ModelContext) async throws {
        try await removeData(modelContext: modelContext, includingCurrent: false)
    }

    private func removeData(modelContext: ModelContext, includingCurrent: Bool) async throws {
        guard !isImporting else { throw AIRACPackageError.invalidPackage("正在导入 AIRAC 数据，请稍后清理") }
        isImporting = true
        defer { isImporting = false }
        if modelContext.hasChanges { try modelContext.save() }
        let versions = try modelContext.fetch(FetchDescriptor<AIRACVersion>())
        let removed = versions.filter { includingCurrent || !$0.isCurrent }
        let removedNames = Set(removed.map(\.version))
        let files = self.files
        // 移走和物理删除放在后台；数据库失败仍可恢复原文件。
        let quarantine = try await Task.detached(priority: .utility) {
            try includingCurrent ? files.quarantineAll() : files.quarantineVersions(Array(removedNames))
        }.value
        let autosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = autosave }
        do {
            for chart in try modelContext.fetch(FetchDescriptor<LocalChart>())
                where includingCurrent || removedNames.contains(chart.airacVersion) {
                modelContext.delete(chart)
            }
            for version in removed { modelContext.delete(version) }
            if includingCurrent {
                for airport in try modelContext.fetch(FetchDescriptor<Airport>()) { modelContext.delete(airport) }
            }
            try saveChanges(modelContext)
        } catch {
            modelContext.rollback()
            do { try await Task.detached(priority: .utility) { try files.restore(quarantine) }.value }
            catch { throw AIRACPackageError.fileOperation("恢复缓存", error.localizedDescription) }
            throw error
        }
        try await Task.detached(priority: .utility) { try files.finishRemoval(quarantine) }.value
    }

    static func currentVersion(modelContext: ModelContext) throws -> AIRACVersion? {
        try modelContext.fetch(FetchDescriptor<AIRACVersion>(
            predicate: #Predicate { $0.isCurrent == true })).first
    }

    static func currentCharts(
        modelContext: ModelContext, documentType: String, icao: String? = nil
    ) throws -> [LocalChart] {
        guard let current = try currentVersion(modelContext: modelContext) else {
            throw AIRACPackageError.missingLocalData
        }
        let version = current.version
        let charts = try modelContext.fetch(FetchDescriptor<LocalChart>(
            predicate: #Predicate { $0.airacVersion == version && $0.documentType == documentType }))
        return icao.map { code in charts.filter { $0.icao == code } } ?? charts
    }

    static func currentAirports(modelContext: ModelContext) throws -> [Airport] {
        guard let current = try currentVersion(modelContext: modelContext) else {
            throw AIRACPackageError.missingLocalData
        }
        let codes: Set<String>
        if let imported = current.airportICAOs {
            codes = Set(imported)
        } else {
            let version = current.version
            codes = Set(try modelContext.fetch(FetchDescriptor<LocalChart>(
                predicate: #Predicate { $0.airacVersion == version })).compactMap(\.icao))
        }
        return try modelContext.fetch(FetchDescriptor<Airport>(sortBy: [SortDescriptor(\.icao)]))
            .filter { codes.contains($0.icao) }
    }

    static func resolveDocument(
        chartID: String, documentType: String, version requestedVersion: String?, modelContext: ModelContext
    ) throws -> (chart: LocalChart, version: AIRACVersion) {
        let selected: AIRACVersion?
        if let requestedVersion {
            selected = try modelContext.fetch(FetchDescriptor<AIRACVersion>(
                predicate: #Predicate { $0.version == requestedVersion })).first
        } else {
            selected = try currentVersion(modelContext: modelContext)
        }
        guard let selected else {
            if requestedVersion == nil { throw AIRACPackageError.missingLocalData }
            throw AIRACPackageError.invalidPackage("该文档所属的 AIRAC 周期已清理，请重新导入或选择当前周期的文档")
        }
        let version = selected.version
        let candidates = try modelContext.fetch(FetchDescriptor<LocalChart>(
            predicate: #Predicate { $0.airacVersion == version && $0.documentType == documentType }))
        if let chart = candidates.first(where: { $0.readerChartID == chartID }) { return (chart, selected) }
        // 旧版 AIP 收藏没有 GEN/ENR 命名空间；只在能唯一定位时兼容。
        let rawID = AIRACDocumentIdentity.documentID(from: chartID, documentType: documentType)
        let legacy = candidates.filter { $0.documentID == rawID }
        guard legacy.count == 1, let chart = legacy.first else {
            throw AIRACPackageError.invalidPackage("此周期中找不到唯一对应的文档，请从列表重新选择或重新导入数据包")
        }
        return (chart, selected)
    }
}
