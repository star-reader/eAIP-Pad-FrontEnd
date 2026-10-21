import Foundation
import PDFKit
import SwiftData
import Testing
@testable import EAIPDataCore

@Suite("AIRAC complete catalogs and safe cleanup", .serialized)
@MainActor
struct AIRACCompletenessTests {
    typealias Fixture = AIRACDataCoreTests.Fixture

    func completePackage(_ fixture: Fixture) throws -> URL {
        let package = try fixture.package()
        let url = package.appendingPathComponent("Data/JsonPath/AD.JSON")
        var nodes = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
        nodes += [
            fixture.node("ad-general", "0", "AD 1 General", "/Data/PDFs/ad-general.pdf"),
            fixture.node("approaches", "chart_section", "Approach charts", ""),
            fixture.node("nested-chart", "approaches", "Unclassified chart", "/Data/PDFs/nested.pdf"),
            fixture.node("ad-chapter", "airport", "AD 2.1", "/Data/PDFs/ad-chapter.pdf")
        ]
        try fixture.writeJSON(nodes, to: "AD.JSON", in: package)
        for section in ["AIC", "AMDT", "SUP"] {
            try fixture.writeJSON([["Id": "shared", "Document": "/Data/PDFs/flat.pdf",
                "Serial": "001", "Subject": section + " subject"]], to: "\(section).JSON", in: package)
        }
        let pdf = try Fixture.pdf()
        for name in ["ad-general", "nested", "ad-chapter", "flat"] {
            try pdf.write(to: package.appendingPathComponent("Data/PDFs/\(name).pdf"))
        }
        return package
    }

    @Test func localImportPreservesEveryPDFAndSourceNamespace() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.store.importPackage(from: completePackage(fixture), modelContext: fixture.context)
        let charts = try fixture.context.fetch(FetchDescriptor<LocalChart>())
        #expect(charts.count == 11)
        let general = try #require(charts.first { $0.documentID == "ad-general" })
        #expect(general.documentType == "aip")
        #expect(general.category == "AD")
        let nested = try #require(charts.first { $0.documentID == "nested-chart" })
        #expect(nested.documentType == "chart")
        #expect(nested.icao == "ZBAA")
        #expect(nested.chartType == "OTHERS")
        #expect(charts.first { $0.documentID == "ad-chapter" }?.documentType == "ad")
        for chart in charts {
            let loaded = try await AIRACPackageStore.loadDocument(chartID: chart.readerChartID,
                documentType: chart.documentType, version: "2601", modelContext: fixture.context, files: fixture.files)
            #expect(loaded.document.pageCount == 1)
        }
        #expect(Set(charts.filter { $0.documentID == "shared" }.map(\.readerChartID)) == ["sup_shared", "aic_shared", "amdt_shared"])
        let aic = try #require(charts.first { $0.documentType == "aic" })
        #expect(aic.toSUPDocumentResponse().localSubject == "AIC subject")
    }

    @Test(arguments: AIRACServerMode.allCases)
    func onlineModesExposeAddedDocumentTypes(_ mode: AIRACServerMode) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let serverTests = AIRACServerTests()
        let (_, client) = try serverTests.server(completePackage(fixture))
        try await fixture.store.configureServer(serverTests.configuration(mode), modelContext: fixture.context, client: client)
        for type in ["aic", "amdt", "aip", "chart", "ad"] {
            let charts = try await AIRACPackageStore.loadCharts(modelContext: fixture.context, documentType: type, client: client)
            #expect(!charts.isEmpty)
            for chart in charts {
                let loaded = try await AIRACPackageStore.loadDocument(chartID: chart.readerChartID,
                    documentType: type, version: "2601", modelContext: fixture.context, client: client, files: fixture.files)
                #expect(loaded.document.pageCount == 1)
            }
        }
        if mode == .request { #expect(try fixture.context.fetch(FetchDescriptor<LocalChart>()).isEmpty) }
    }

    @Test func missingAddedPDFRejectsImportAndPreservesCurrentCycle() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let package = try completePackage(fixture)
        try FileManager.default.removeItem(at: package.appendingPathComponent("Data/PDFs/flat.pdf"))
        await fixture.expectFailure(package, message: "缺少 PDF")
        try fixture.expectCurrent("2601", pages: 1)
    }

    @Test func cleanupPreservesCurrentOfflineCopyServerAndUserData() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let serverTests = AIRACServerTests()
        let (_, client) = try serverTests.server(fixture.package(version: "2602", date: "2602010000", pages: 2))
        try await fixture.store.configureServer(serverTests.configuration(.copy), modelContext: fixture.context, client: client)
        fixture.context.insert(PinnedChart(chartID: "chart_chart_one", displayName: "Saved", icao: "ZBAA", type: "SID", documentType: "chart", airacVersion: "2602"))
        fixture.context.insert(ChartAnnotation(chartID: "chart_chart_one", pageNumber: 0, pathsJSON: "[]", documentType: "chart"))
        try fixture.context.save()
        try await fixture.store.clearOldVersions(modelContext: fixture.context)
        try fixture.expectCurrent("2602", pages: 2)
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context))
        #expect(current.source == "serverCopy")
        #expect(current.serverURL == "https://example.com/packages/current/")
        #expect(try fixture.context.fetch(FetchDescriptor<AIRACVersion>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<PinnedChart>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<ChartAnnotation>()).count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheRoot.appendingPathComponent("PDFCache/2601").path))
        try await fixture.store.clearOldVersions(modelContext: fixture.context)
        try fixture.expectCurrent("2602", pages: 2)
    }

    @Test func cleanupPreservesRequestServerConfiguration() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let serverTests = AIRACServerTests()
        let (_, client) = try serverTests.server(fixture.package(version: "2602", date: "2602010000"))
        try await fixture.store.configureServer(serverTests.configuration(.request), modelContext: fixture.context, client: client)
        try await fixture.store.clearOldVersions(modelContext: fixture.context)
        let reopened = ModelContext(fixture.container)
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: reopened))
        #expect(current.source == "serverRequest")
        #expect(current.serverURL != nil)
        #expect(try await AIRACPackageStore.loadAirports(modelContext: reopened, client: client).count == 1)
    }

    @Test func failedOldCycleCleanupRestoresOldAndCurrentPDFs() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        try await fixture.install(version: "2602", date: "2602010000", pages: 2)
        let failing = AIRACPackageStore(files: fixture.files) { _ in throw AIRACDataCoreTests.InjectedFailure.database }
        await #expect(throws: (any Error).self) { try await failing.clearOldVersions(modelContext: fixture.context) }
        try fixture.expectCurrent("2602", pages: 2)
        let old = try await AIRACPackageStore.loadDocument(chartID: "chart_chart_one", documentType: "chart",
            version: "2601", modelContext: fixture.context, files: fixture.files)
        #expect(old.document.pageCount == 1)
    }

    @Test func cacheSizeScanDoesNotCreateDirectoriesAndCountsPDFs() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        #expect(try fixture.files.totalCacheSize() == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheRoot.appendingPathComponent("PDFCache").path))
        try await fixture.install(version: "2601", date: "2601010000")
        #expect(try fixture.files.totalCacheSize() > 0)
    }
}
