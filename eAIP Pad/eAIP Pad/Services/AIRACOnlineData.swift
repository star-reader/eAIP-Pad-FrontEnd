import Foundation
import PDFKit
import SwiftData

extension LocalChart {
    convenience init(pending: ParsedAIRACPackage.Chart, version: String) {
        self.init(chartID: AIRACDocumentIdentity.storageID(version: version, readerID: pending.readerID),
            documentID: pending.documentID, nameEn: pending.nameEn, nameCn: pending.nameCn,
            chartType: pending.chartType, airacVersion: version, documentType: pending.documentType)
        apply(pending, version: version)
    }

    func apply(_ pending: ParsedAIRACPackage.Chart, version: String) {
        chartID = AIRACDocumentIdentity.storageID(version: version, readerID: pending.readerID)
        documentID = pending.documentID
        airacVersion = version
        documentType = pending.documentType
        nameEn = pending.nameEn
        nameCn = pending.nameCn
        chartType = pending.chartType
        pdfPath = pending.pdfPath
        parentID = pending.parentID
        icao = pending.icao
        isModified = pending.isModified
        category = pending.category
        serialNumber = pending.serialNumber
        subject = pending.subject
        localSubject = pending.localSubject
        chapterType = pending.chapterType
        effectiveTime = pending.effectiveTime
        outDate = pending.outDate
        pubDate = pending.pubDate
        seriesName = pending.seriesName
        generateTime = pending.generateTime
        generateTimeEn = pending.generateTimeEn
    }
}

extension AIRACPackageStore {
    static func loadAirports(modelContext: ModelContext, client: AIRACServerClient = .shared) async throws -> [Airport] {
        guard let current = try currentVersion(modelContext: modelContext) else { throw AIRACPackageError.missingLocalData }
        guard current.source == AIRACServerMode.request.source else { return try currentAirports(modelContext: modelContext) }
        let parsed = try await remoteCatalog(current, sections: ["AD"], modelContext: modelContext, client: client)
        let terminals = Set(parsed.charts.filter { $0.documentType == "chart" }.compactMap(\.icao))
        return parsed.airports.map {
            Airport(icao: $0.icao, nameEn: $0.nameEn, nameCn: $0.nameCn,
                hasTerminalCharts: terminals.contains($0.icao), isModified: $0.isModified)
        }
    }

    static func loadCharts(
        modelContext: ModelContext, documentType: String, icao: String? = nil,
        client: AIRACServerClient = .shared
    ) async throws -> [LocalChart] {
        guard let current = try currentVersion(modelContext: modelContext) else { throw AIRACPackageError.missingLocalData }
        guard current.source == AIRACServerMode.request.source else {
            return try currentCharts(modelContext: modelContext, documentType: documentType, icao: icao)
        }
        let parsed = try await remoteCatalog(
            current, sections: AIRACServerClient.sections(for: documentType), modelContext: modelContext, client: client)
        return parsed.charts.filter { $0.documentType == documentType && (icao == nil || $0.icao == icao) }
            .map { LocalChart(pending: $0, version: parsed.version) }
    }

    static func loadDocument(
        chartID: String, documentType: String, version requestedVersion: String?, modelContext: ModelContext,
        client: AIRACServerClient = .shared, files: AIRACFileStore = .shared
    ) async throws -> (chart: LocalChart, version: AIRACVersion, document: PDFDocument) {
        let selected: AIRACVersion?
        if let requestedVersion {
            selected = try modelContext.fetch(FetchDescriptor<AIRACVersion>(
                predicate: #Predicate { $0.version == requestedVersion })).first
        } else { selected = try currentVersion(modelContext: modelContext) }
        guard let selected else {
            if requestedVersion == nil { throw AIRACPackageError.missingLocalData }
            throw AIRACPackageError.invalidPackage("文档所属的 AIRAC 周期不可用，请重新导入或配置服务器")
        }
        if selected.source == AIRACServerMode.request.source {
            let configuration = try serverConfiguration(selected)
            let selection = RemoteSelection(selected)
            let parsed = try await remoteCatalog(
                selected, sections: AIRACServerClient.sections(for: documentType), modelContext: modelContext, client: client)
            let candidates = parsed.charts.filter { $0.documentType == documentType }
            let rawID = AIRACDocumentIdentity.documentID(from: chartID, documentType: documentType)
            let exact = candidates.first { $0.readerID == chartID }
            let legacy = candidates.filter { $0.documentID == rawID }
            guard let pending = exact ?? (legacy.count == 1 ? legacy.first : nil) else {
                throw AIRACPackageError.invalidPackage("服务器目录中找不到该文档，请刷新列表后重新选择")
            }
            let data = try await client.fetch(pending.pdfPath!, from: configuration)!
            try selection.validate(modelContext: modelContext)
            // PDF 下载期间也可能切换周期；再次检查，避免在旧周期标题下显示新 PDF。
            let latest = try await client.metadata(from: configuration)
            guard latest.version == parsed.version, latest.effectiveDate == parsed.effectiveDate else {
                throw AIRACPackageError.invalidPackage("服务器周期已变更，请重新配置在线服务器")
            }
            try selection.validate(modelContext: modelContext)
            guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                throw AIRACPackageError.invalidPDF(pending.readerID)
            }
            return (LocalChart(pending: pending, version: parsed.version), selected, document)
        }
        let resolved = try resolveDocument(chartID: chartID, documentType: documentType,
            version: requestedVersion, modelContext: modelContext)
        var document = files.loadPDF(version: resolved.version.version, revision: resolved.version.cacheRevision,
            documentType: documentType, id: resolved.chart.cacheDocumentID)
        if document == nil, resolved.version.cacheRevision == nil {
            document = files.loadPDF(version: resolved.version.version, revision: nil,
                documentType: documentType, id: resolved.chart.documentID)
        }
        guard let document else { throw AIRACPackageError.missingPDF(resolved.chart.nameCn) }
        return (resolved.chart, resolved.version, document)
    }

    private static func serverConfiguration(_ version: AIRACVersion) throws -> AIRACServerConfiguration {
        guard let address = version.serverURL else { throw AIRACPackageError.invalidPackage("在线服务器地址缺失，请重新配置") }
        return try AIRACServerConfiguration(address: address, mode: .request)
    }

    private static func remoteCatalog(
        _ version: AIRACVersion, sections: [String], modelContext: ModelContext, client: AIRACServerClient
    ) async throws -> ParsedAIRACPackage {
        let configuration = try serverConfiguration(version)
        let selection = RemoteSelection(version)
        let parsed = try await client.catalog(from: configuration, sections: sections,
            expectedVersion: version.version, expectedDate: version.effectiveDate, requireDocuments: false)
        try selection.validate(modelContext: modelContext)
        return parsed
    }

    private struct RemoteSelection {
        let selected: AIRACVersion
        let source: String
        let address: String?
        let revision: String?
        let effectiveDate: Date
        let wasCurrent: Bool

        init(_ selected: AIRACVersion) {
            self.selected = selected
            source = selected.source
            address = selected.serverURL
            revision = selected.cacheRevision
            effectiveDate = selected.effectiveDate
            wasCurrent = selected.isCurrent
        }

        func validate(modelContext: ModelContext) throws {
            try Task.checkCancellation()
            let versions = try modelContext.fetch(FetchDescriptor<AIRACVersion>())
            guard versions.contains(where: { $0 === selected }), selected.source == source,
                selected.serverURL == address, selected.cacheRevision == revision,
                selected.effectiveDate == effectiveDate, !wasCurrent || selected.isCurrent else {
                throw AIRACPackageError.invalidPackage("数据源已更改，请重新打开页面")
            }
        }
    }
}
