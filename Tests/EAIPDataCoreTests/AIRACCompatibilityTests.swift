import Foundation
import PDFKit
import SwiftData
import Testing
@testable import EAIPDataCore

@Suite("Official package and legacy cache compatibility", .serialized)
@MainActor
struct AIRACCompatibilityTests {
    typealias Fixture = AIRACDataCoreTests.Fixture

    private func officialPackage(_ fixture: Fixture) throws -> URL {
        let package = try fixture.package(version: "2026-09.V1")
        // AMDT uses the same tree schema as AD/GEN/ENR, including directory-only nodes.
        let nodes: [[String: Any]] = [
            ["id": "amendment", "pId": "", "name": "AMD", "name_cn": "修订单",
                "pdfPath": "/Data/PDFs/gen.pdf", "airporticao": NSNull(), "Is_Modified": NSNull()],
            fixture.node("section", "", "GENERAL", ""),
            fixture.node("gen", "section", "GEN 0.1", "/Data/PDFs/gen.pdf")
        ]
        try JSONSerialization.data(withJSONObject: nodes).write(
            to: package.appendingPathComponent("Data/JsonPath/AMDT.JSON"))
        return package
    }

    private func expectReadableCatalog(
        _ fixture: Fixture, client: AIRACServerClient = .shared
    ) async throws {
        for type in ["chart", "ad", "aip", "enroute", "amdt"] {
            let charts = try await AIRACPackageStore.loadCharts(
                modelContext: fixture.context, documentType: type, client: client)
            #expect(!charts.isEmpty)
            if type == "amdt" {
                #expect(Set(charts.map(\.documentID)) == ["amendment", "gen"])
            }
            for chart in charts {
                let loaded = try await AIRACPackageStore.loadDocument(
                    chartID: chart.readerChartID, documentType: type, version: "2026-09.V1",
                    modelContext: fixture.context, client: client, files: fixture.files)
                #expect(loaded.document.pageCount == 1)
            }
        }
    }

    @Test(arguments: [false, true])
    func officialAmendmentTreeImportsFromFolderAndZIP(_ zipped: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let package = try officialPackage(fixture)
        let source = zipped ? try fixture.archive(package) : package
        try await fixture.store.importPackage(
            from: source, isZIPArchive: zipped, modelContext: fixture.context)
        try await expectReadableCatalog(fixture)
        try fixture.expectNoExtractedFiles()
    }

    @Test(arguments: AIRACServerMode.allCases)
    func officialAmendmentTreeWorksInBothServerModes(_ mode: AIRACServerMode) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let serverTests = AIRACServerTests()
        let (_, client) = try serverTests.server(officialPackage(fixture))
        try await fixture.store.configureServer(
            serverTests.configuration(mode), modelContext: fixture.context, client: client)
        try await expectReadableCatalog(fixture, client: client)
    }

    @Test func invalidIndexNamesFileAndMissingField() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let package = try fixture.package()
        try fixture.writeJSON([["id": "broken", "pId": "", "name": "AMD", "pdfPath": ""]],
            to: "AMDT.JSON", in: package)
        do {
            _ = try LocalAIRACPackageParser.parse(folderURL: package)
            Issue.record("Accepted malformed AMDT node")
        } catch {
            #expect(error.localizedDescription.contains("AMDT.JSON"))
            #expect(error.localizedDescription.contains("name_cn"))
        }
    }

    @Test func dottedLegacyCycleLoadsChartsAndRegulationsWithoutReimport() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let cycle = "2026-09.V1"
        let version = AIRACVersion(version: cycle, effectiveDate: Date(), isCurrent: true)
        fixture.context.insert(version)
        let directory = fixture.cacheRoot.appendingPathComponent("PDFCache").appendingPathComponent(cycle)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for type in ["chart", "ad", "aip"] {
            let id = type == "aip" ? "1.2_中文" : "6340f1f6-06c8-4c67-9663-c4cd7741b9a4"
            let chart = LocalChart(chartID: "\(type)_\(id)", documentID: id, nameEn: "Legacy",
                nameCn: "旧版", chartType: type, airacVersion: cycle, documentType: type)
            if type == "aip" { chart.category = "GEN" }
            fixture.context.insert(chart)
            try Fixture.pdf().write(to: directory.appendingPathComponent("\(type)_\(id).pdf"))
            try fixture.context.save()
            let loaded = try await AIRACPackageStore.loadDocument(
                chartID: chart.chartID, documentType: type, version: cycle,
                modelContext: fixture.context, files: fixture.files)
            #expect(loaded.document.pageCount == 1)
        }
        // A transaction revision must never fall back to an older cache for the same cycle.
        version.cacheRevision = "missing-revision"
        try fixture.context.save()
        await #expect(throws: (any Error).self) {
            try await AIRACPackageStore.loadDocument(
                chartID: "chart_6340f1f6-06c8-4c67-9663-c4cd7741b9a4", documentType: "chart",
                version: cycle, modelContext: fixture.context, files: fixture.files)
        }
    }

    @Test func legacyCleanupRemovesBothLayoutsAndSupportsRollback() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let cycle = "2026-09.V1"
        var directories: [URL] = []
        for root in ["PDFCache", "DataCache"] {
            for name in [cycle, AIRACDocumentIdentity.fileComponent(cycle)] {
                let directory = fixture.cacheRoot.appendingPathComponent(root).appendingPathComponent(name)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data("legacy cache".utf8).write(to: directory.appendingPathComponent("saved"))
                directories.append(directory)
            }
        }
        let quarantine = try fixture.files.quarantineVersions([cycle, cycle])
        for directory in directories { #expect(!FileManager.default.fileExists(atPath: directory.path)) }
        try fixture.files.restore(quarantine)
        for directory in directories {
            #expect(try Data(contentsOf: directory.appendingPathComponent("saved")) == Data("legacy cache".utf8))
        }
        try fixture.files.removeVersion(cycle)
        for directory in directories { #expect(!FileManager.default.fileExists(atPath: directory.path)) }
    }

    @Test func legacyFallbackCannotReadOrRemoveFilesOutsideCacheRoot() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let outside = fixture.cacheRoot.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let pdf = outside.appendingPathComponent("chart_saved.pdf")
        try Fixture.pdf().write(to: pdf)
        #expect(fixture.files.loadPDF(version: "../outside", revision: nil,
            documentType: "chart", id: "saved") == nil)
        try fixture.files.removeVersion("../outside")
        #expect(FileManager.default.fileExists(atPath: pdf.path))
    }
}
