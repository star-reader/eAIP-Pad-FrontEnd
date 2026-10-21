import CoreGraphics
import Foundation
import PDFKit
import SwiftData
import Testing
import ZIPFoundation
@testable import EAIPDataCore

@Suite("AIRAC import and storage", .serialized)
@MainActor
struct AIRACDataCoreTests {
    enum InjectedFailure: Error { case write, database }

    @Test func notamPreservesEntireIDAndReadsItsPDF() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package(notam: true, pages: 2)
        try await fixture.store.importPackage(from: package, modelContext: fixture.context)
        let charts = try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "notam")
        let chart = try #require(charts.first)
        #expect(chart.documentID == "A_series_2026/10/20 08:00")
        #expect(AIRACDocumentIdentity.documentID(from: chart.readerChartID, documentType: "notam") == chart.documentID)
        let resolved = try AIRACPackageStore.resolveDocument(
            chartID: chart.toChartResponse().readerChartID, documentType: "notam",
            version: "2601", modelContext: fixture.context)
        #expect(fixture.document(resolved.chart, version: resolved.version)?.pageCount == 2)
    }

    @Test func missingPDFFailsWithoutChangingCurrentVersion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let package = try fixture.package(version: "2602", date: "2602010000")
        try FileManager.default.removeItem(at: package.appendingPathComponent("Data/PDFs/chart_0.pdf"))
        await fixture.expectFailure(package, message: "缺少 PDF")
        try fixture.expectCurrent("2601", pages: 1)
        #expect(try fixture.context.fetch(FetchDescriptor<AIRACVersion>()).count == 1)
    }

    @Test func corruptPDFFailsWithoutPublishingMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package()
        try Data("not a PDF".utf8).write(to: package.appendingPathComponent("Data/PDFs/gen.pdf"))
        await fixture.expectFailure(package, message: "PDF 无法读取")
        #expect(try fixture.context.fetch(FetchDescriptor<LocalChart>()).isEmpty)
        #expect(try AIRACPackageStore.currentVersion(modelContext: fixture.context) == nil)
    }

    @Test func fileWriteFailureKeepsExistingPDFAndMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let failingFiles = AIRACFileStore(documentsDirectory: fixture.cacheRoot) { data, destination in
            if destination.lastPathComponent.hasPrefix("chart_") { throw InjectedFailure.write }
            try data.write(to: destination, options: .atomic)
        }
        let store = AIRACPackageStore(files: failingFiles)
        let replacement = try fixture.package(airportName: "Changed", pages: 2)
        await fixture.expectFailure(replacement, using: store, message: "处理文件失败")
        try fixture.expectCurrent("2601", pages: 1)
        #expect(try AIRACPackageStore.currentAirports(modelContext: fixture.context).first?.nameCn == "Original")
        let directories = try FileManager.default.contentsOfDirectory(
            at: fixture.cacheRoot.appendingPathComponent("PDFCache/2601"), includingPropertiesForKeys: nil)
        #expect(directories.count == 1)
    }

    @Test func databaseFailureRollsBackSameCycleReplacement() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context))
        let revision = current.cacheRevision
        let count = try fixture.context.fetch(FetchDescriptor<LocalChart>()).count
        let failingStore = AIRACPackageStore(files: fixture.files) { _ in throw InjectedFailure.database }
        let replacement = try fixture.package(airportName: "Changed", chartIDs: ["replacement"], pages: 2)
        await fixture.expectFailure(replacement, using: failingStore)
        try fixture.expectCurrent("2601", pages: 1)
        #expect(try AIRACPackageStore.currentVersion(modelContext: fixture.context)?.cacheRevision == revision)
        #expect(try fixture.context.fetch(FetchDescriptor<LocalChart>()).count == count)
        #expect(try AIRACPackageStore.currentAirports(modelContext: fixture.context).first?.nameCn == "Original")
        #expect(!fixture.context.hasChanges)
    }

    @Test func databaseFailureDoesNotActivateNewCycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let failingStore = AIRACPackageStore(files: fixture.files) { _ in throw InjectedFailure.database }
        let package = try fixture.package(version: "2602", date: "2602010000")
        await fixture.expectFailure(package, using: failingStore)
        try fixture.expectCurrent("2601", pages: 1)
        #expect(try fixture.context.fetch(FetchDescriptor<AIRACVersion>()).count == 1)
    }

    @Test func repeatedImportReplacesNamesFlagsAndRetiredDocuments() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.package(chartIDs: ["kept", "retired"])
        try await fixture.store.importPackage(from: first, modelContext: fixture.context)
        let previous = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context)?.cacheRevision)
        let corrected = try fixture.package(airportName: "Corrected", chartIDs: ["kept"], chartName: "STAR corrected", pages: 2)
        try await fixture.store.importPackage(from: corrected, modelContext: fixture.context)
        let charts = try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "chart")
        #expect(charts.count == 1)
        #expect(charts.first?.documentID == "kept")
        #expect(charts.first?.chartType == "STAR")
        #expect(charts.first?.nameCn == "STAR corrected 0")
        let airport = try #require(try AIRACPackageStore.currentAirports(modelContext: fixture.context).first)
        #expect(airport.nameCn == "Corrected")
        #expect(airport.isModified)
        #expect(airport.hasTerminalCharts)
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context))
        #expect(current.cacheRevision != previous)
        #expect(current.totalCharts == 5)
        #expect(current.downloadedCharts == 5)
        try fixture.expectCurrent("2601", pages: 2)
    }

    @Test func stableIDsSurviveFourCyclesAndEviction() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for month in 1...4 {
            let version = String(format: "26%02d", month)
            try await fixture.install(version: version, date: "\(version)010000", pages: month)
        }
        let versions = try fixture.context.fetch(FetchDescriptor<AIRACVersion>())
        #expect(Set(versions.map(\.version)) == ["2602", "2603", "2604"])
        #expect(try fixture.context.fetch(FetchDescriptor<LocalChart>()).count == 15)
        #expect(try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "chart").count == 1)
        try fixture.expectCurrent("2604", pages: 4)
        let resolved = try AIRACPackageStore.resolveDocument(
            chartID: "chart_chart_one", documentType: "chart", version: "2602", modelContext: fixture.context)
        #expect(fixture.document(resolved.chart, version: resolved.version)?.pageCount == 2)
    }

    @Test func importingOlderCycleProtectsNewCurrentCycleFromEviction() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for month in 2...4 {
            let version = String(format: "26%02d", month)
            try await fixture.install(version: version, date: "\(version)010000")
        }
        try await fixture.install(version: "2601", date: "2601010000")
        try fixture.expectCurrent("2601", pages: 1)
        let versions = try fixture.context.fetch(FetchDescriptor<AIRACVersion>())
        #expect(Set(versions.map(\.version)) == ["2601", "2603", "2604"])
        #expect(versions.filter(\.isCurrent).count == 1)
    }

    @Test func sourceNamespacesKeepEqualRawIDsDistinct() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package(chartIDs: ["shared"])
        try fixture.writeJSON([fixture.node("shared", "0", "GEN shared", "/Data/PDFs/gen.pdf")], to: "GEN.JSON", in: package)
        try fixture.writeJSON([fixture.node("shared", "0", "ENR shared", "/Data/PDFs/enr.pdf")], to: "ENR.JSON", in: package)
        try fixture.writeJSON([["Id": "shared", "Document": "/Data/PDFs/sup.pdf", "Serial": "1"]], to: "SUP.JSON", in: package)
        try Fixture.pdf().write(to: package.appendingPathComponent("Data/PDFs/sup.pdf"))
        try await fixture.store.importPackage(from: package, modelContext: fixture.context)
        let aip = try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "aip")
        #expect(Set(aip.map { $0.toAIPDocumentResponse().id }) == ["GEN_shared", "ENR_shared"])
        for chart in aip {
            let resolved = try AIRACPackageStore.resolveDocument(
                chartID: chart.readerChartID, documentType: "aip", version: "2601", modelContext: fixture.context)
            #expect(fixture.document(resolved.chart, version: resolved.version) != nil)
        }
        #expect(try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "chart").count == 1)
        #expect(try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "sup").count == 1)
    }

    @Test func airportListUsesCurrentPackageMembership() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let next = try fixture.package(version: "2602", date: "2602010000", icao: "ZSPD")
        try await fixture.store.importPackage(from: next, modelContext: fixture.context)
        #expect(try AIRACPackageStore.currentAirports(modelContext: fixture.context).map(\.icao) == ["ZSPD"])
    }

    @Test func clearRemovesVersionMarkersAndImportedDataButKeepsUserData() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        fixture.context.insert(PinnedChart(chartID: "chart_chart_one", displayName: "Saved", icao: "ZBAA", type: "SID", documentType: "chart", airacVersion: "2601"))
        fixture.context.insert(ChartAnnotation(chartID: "chart_chart_one", pageNumber: 0, pathsJSON: "[]", documentType: "chart"))
        try fixture.context.save()
        try await fixture.store.clearAll(modelContext: fixture.context)
        #expect(try fixture.context.fetch(FetchDescriptor<AIRACVersion>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<LocalChart>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<Airport>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<PinnedChart>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<ChartAnnotation>()).count == 1)
        #expect(try AIRACPackageStore.currentVersion(modelContext: fixture.context) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheRoot.appendingPathComponent("PDFCache").path))
    }

    @Test func failedClearRestoresFilesAndDatabase() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let failingStore = AIRACPackageStore(files: fixture.files) { _ in throw InjectedFailure.database }
        do {
            try await failingStore.clearAll(modelContext: fixture.context)
            Issue.record("Expected clear failure")
        } catch {}
        try fixture.expectCurrent("2601", pages: 1)
        #expect(try AIRACPackageStore.currentAirports(modelContext: fixture.context).count == 1)
    }

    @Test func failedCacheRemovalDoesNotDeleteMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        try Data("blocked".utf8).write(to: fixture.cacheRoot.appendingPathComponent(".AIRACTrash"))
        do {
            try await fixture.store.clearAll(modelContext: fixture.context)
            Issue.record("Expected file removal failure")
        } catch {}
        try fixture.expectCurrent("2601", pages: 1)
    }

    @Test func legacyRecordsAndFavoritesUpgradeOnReimport() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.context.insert(AIRACVersion(version: "2601", effectiveDate: Date(), isCurrent: true))
        let legacy = LocalChart(chartID: "aip_gen", documentID: "gen", nameEn: "Old", nameCn: "旧正文", chartType: "AIP", airacVersion: "2601", documentType: "aip")
        legacy.category = "GEN"
        fixture.context.insert(legacy)
        fixture.context.insert(PinnedChart(chartID: "aip_gen", displayName: "Old", icao: "", type: "aip", documentType: "aip", airacVersion: "2601"))
        try fixture.context.save()
        try await fixture.install(version: "2601", date: "2601010000")
        let aip = try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "aip")
        #expect(aip.count == 2)
        let pin = try #require(try fixture.context.fetch(FetchDescriptor<PinnedChart>()).first)
        #expect(pin.chartID == "aip_GEN_gen")
        #expect(pin.displayName == "GEN")
        let resolved = try AIRACPackageStore.resolveDocument(
            chartID: pin.chartID, documentType: pin.documentType, version: pin.airacVersion, modelContext: fixture.context)
        #expect(fixture.document(resolved.chart, version: resolved.version) != nil)
    }

    @Test func airportsWithoutTerminalChartsRemainInTheCurrentAirportList() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package(chartIDs: [])
        var airport = fixture.node("airport", "0", "ZBAA-Empty", "")
        airport["airporticao"] = "ZBAA"
        try fixture.writeJSON([airport], to: "AD.JSON", in: package)
        try await fixture.store.importPackage(from: package, modelContext: fixture.context)
        let airports = try AIRACPackageStore.currentAirports(modelContext: fixture.context)
        #expect(airports.count == 1)
        #expect(airports.first?.hasTerminalCharts == false)
        #expect(try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "ad").isEmpty)
    }

    @Test func optionalCacheFieldsMigrateWithoutLosingLegacyVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EAIPMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("legacy.store")
        do {
            let container = try ModelContainer(
                for: LegacySchema.AIRACVersion.self,
                configurations: ModelConfiguration(url: url))
            container.mainContext.insert(LegacySchema.AIRACVersion(version: "2601"))
            try container.mainContext.save()
        }
        let upgraded = try ModelContainer(
            for: AIRACVersion.self, configurations: ModelConfiguration(url: url))
        let version = try #require(try upgraded.mainContext.fetch(FetchDescriptor<AIRACVersion>()).first)
        #expect(version.version == "2601")
        #expect(version.isCurrent)
        #expect(version.cacheRevision == nil)
        #expect(version.serverURL == nil)
        #expect(version.airportICAOs == nil)
    }

    @Test func legacyMetadataAndUnescapedPDFRemainReadable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let version = AIRACVersion(version: "legacy", effectiveDate: Date(), isCurrent: true)
        let chart = LocalChart(chartID: "aip_1.2_中文", documentID: "1.2_中文", nameEn: "GEN", nameCn: "旧版", chartType: "AIP", airacVersion: "legacy", documentType: "aip")
        chart.category = "GEN"
        fixture.context.insert(version)
        fixture.context.insert(chart)
        try fixture.context.save()
        let directory = fixture.cacheRoot.appendingPathComponent("PDFCache/legacy")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Fixture.pdf().write(to: directory.appendingPathComponent("aip_1.2_中文.pdf"))
        let resolved = try AIRACPackageStore.resolveDocument(
            chartID: "aip_1.2_中文", documentType: "aip", version: nil, modelContext: fixture.context)
        #expect(fixture.files.loadPDF(version: "legacy", revision: nil, documentType: "aip", id: resolved.chart.documentID) != nil)
    }

    @Test func invalidEffectiveDatesAreRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for date in ["invalid", "2613320000", "2602300000", "2601012460", "260101000"] {
            let package = try fixture.package(date: date)
            do {
                _ = try LocalAIRACPackageParser.parse(folderURL: package)
                Issue.record("Accepted invalid date: \(date)")
            } catch { #expect(error.localizedDescription.contains("生效时间无效")) }
        }
    }

    @Test func cyclicAndDuplicateTreeNodesAreRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package()
        try fixture.writeJSON([
            fixture.node("root", "child", "EN-ROUTE CHARTS", ""),
            fixture.node("child", "root", "AREA", "")
        ], to: "ENR.JSON", in: package)
        do {
            _ = try LocalAIRACPackageParser.parse(folderURL: package)
            Issue.record("Accepted cyclic ENR tree")
        } catch { #expect(error.localizedDescription.contains("循环父子关系")) }
        try fixture.writeJSON([], to: "ENR.JSON", in: package)
        try fixture.writeJSON([
            fixture.node("same", "0", "GEN", ""), fixture.node("same", "0", "GEN", "")
        ], to: "GEN.JSON", in: package)
        do {
            _ = try LocalAIRACPackageParser.parse(folderURL: package)
            Issue.record("Accepted duplicate node ID")
        } catch { #expect(error.localizedDescription.contains("重复 ID")) }
    }

    @Test func deepTreesParseWithoutRecursiveTraversal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package()
        var nodes = [fixture.node("n0", "none", "EN-ROUTE CHARTS", "")]
        for index in 1...5_000 {
            nodes.append(fixture.node("n\(index)", "n\(index - 1)", "Section", ""))
        }
        try fixture.writeJSON(nodes, to: "ENR.JSON", in: package)
        let parsed = try LocalAIRACPackageParser.parse(folderURL: package)
        #expect(!parsed.charts.isEmpty)
    }

    @Test func emptyPackageIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package()
        for name in ["AD.JSON", "GEN.JSON", "ENR.JSON"] { try fixture.writeJSON([], to: name, in: package) }
        do {
            _ = try LocalAIRACPackageParser.parse(folderURL: package)
            Issue.record("Accepted empty package")
        } catch { #expect(error.localizedDescription.contains("没有可导入")) }
    }

    @Test func escapedAndSymlinkedPDFPathsCannotLeaveThePackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside.pdf")
        try Fixture.pdf().write(to: outside)
        for path in ["../../outside.pdf", "/Data/PDFs/escape.pdf"] {
            let package = try fixture.package()
            try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("Data/PDFs/escape.pdf"), withDestinationURL: outside)
            try fixture.writeJSON([fixture.node("escape", "0", "GEN", path)], to: "GEN.JSON", in: package)
            await fixture.expectFailure(package, message: "路径超出")
        }
        #expect(try AIRACPackageStore.currentVersion(modelContext: fixture.context) == nil)
    }

    @Test func customersAcceptsWhitespaceAndQuotedKeys() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package()
        try "var Customers = [{\"DataVersion\": \"2601\", 'EffectiveDate': '2601010000'}];".write(
            to: package.appendingPathComponent("Data/Customers.js"), atomically: true, encoding: .utf8)
        #expect(try LocalAIRACPackageParser.parse(folderURL: package).version == "2601")
    }

    @Test func cancellationBeforeCommitPreservesCurrentPackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let package = try fixture.package(version: "2602", date: "2602010000")
        let task = Task { @MainActor in
            try await fixture.store.importPackage(from: package, modelContext: fixture.context) { progress, _ in
                if progress == 0.9 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            try await task.value
            Issue.record("Cancelled import committed data")
        } catch { #expect(error is CancellationError) }
        try fixture.expectCurrent("2601", pages: 1)
    }

    @Test func zipPackageImportsFromRootOrWrappedDirectory() async throws {
        for keepParent in [false, true] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let package = try fixture.package(notam: true, pages: 2)
            let zip = try fixture.archive(package, keepParent: keepParent)
            var fractions: [Double] = []
            var messages: [String] = []
            try await fixture.store.importPackage(from: zip, isZIPArchive: true, modelContext: fixture.context) { fraction, message in
                fractions.append(fraction)
                messages.append(message)
            }
            try fixture.expectCurrent("2601", pages: 2)
            #expect(try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "notam").count == 1)
            #expect(messages.contains { $0.contains("解压") })
            #expect(fractions == fractions.sorted())
            #expect(fractions.last == 1)
            try fixture.expectNoExtractedFiles()
            #expect(FileManager.default.fileExists(atPath: zip.path))
        }
    }

    @Test func invalidZipPreservesCurrentPackageAndRemovesTemporaryFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let zip = fixture.root.appendingPathComponent("invalid.zip")
        try Data("This is not a ZIP".utf8).write(to: zip)
        do {
            try await fixture.store.importPackage(from: zip, isZIPArchive: true, modelContext: fixture.context)
            Issue.record("Accepted invalid ZIP")
        } catch { #expect(error.localizedDescription.contains("ZIP 解压失败")) }
        try fixture.expectCurrent("2601", pages: 1)
        try fixture.expectNoExtractedFiles()
    }

    @Test func failedZIPDatabaseCommitRemovesExtractionAndPreservesCurrentCycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let zip = try fixture.archive(fixture.package(version: "2602", date: "2602010000"))
        let failingStore = AIRACPackageStore(
            files: fixture.files, archiveExtractor: AIRACArchiveExtractor(temporaryDirectory: fixture.root)
        ) { _ in throw InjectedFailure.database }
        do {
            try await failingStore.importPackage(from: zip, isZIPArchive: true, modelContext: fixture.context)
            Issue.record("Expected database failure from ZIP import")
        } catch {}
        try fixture.expectCurrent("2601", pages: 1)
        try fixture.expectNoExtractedFiles()
        #expect(try fixture.context.fetch(FetchDescriptor<AIRACVersion>()).count == 1)
    }

    @Test func ZIPImportIgnoresMacMetadataWhenFindingThePackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package()
        let metadata = package.appendingPathComponent("__MACOSX/duplicate/Data/JsonPath")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try Data("metadata".utf8).write(to: metadata.deletingLastPathComponent().appendingPathComponent("Customers.js"))
        try await fixture.store.importPackage(
            from: fixture.archive(package), isZIPArchive: true, modelContext: fixture.context)
        try fixture.expectCurrent("2601", pages: 1)
        try fixture.expectNoExtractedFiles()
    }

    @Test func zipMissingPDFDoesNotActivateNewCycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let package = try fixture.package(version: "2602", date: "2602010000")
        try FileManager.default.removeItem(at: package.appendingPathComponent("Data/PDFs/chart_0.pdf"))
        let zip = try fixture.archive(package)
        do {
            try await fixture.store.importPackage(from: zip, isZIPArchive: true, modelContext: fixture.context)
            Issue.record("Accepted missing PDF from ZIP")
        } catch { #expect(error.localizedDescription.contains("缺少 PDF")) }
        try fixture.expectCurrent("2601", pages: 1)
        try fixture.expectNoExtractedFiles()
    }

    @Test func zipWithoutPackageIsRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folder = fixture.root.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("README".utf8).write(to: folder.appendingPathComponent("README.txt"))
        let zip = try fixture.archive(folder)
        do {
            try await fixture.store.importPackage(from: zip, isZIPArchive: true, modelContext: fixture.context)
            Issue.record("Accepted unrelated ZIP")
        } catch { #expect(error.localizedDescription.contains("未找到")) }
        try fixture.expectNoExtractedFiles()
    }

    @Test func zipWithMultiplePackagesIsRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let wrapper = fixture.root.appendingPathComponent("multiple")
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        for number in 1...2 {
            try FileManager.default.copyItem(at: fixture.package(), to: wrapper.appendingPathComponent("package\(number)"))
        }
        let zip = try fixture.archive(wrapper)
        do {
            try await fixture.store.importPackage(from: zip, isZIPArchive: true, modelContext: fixture.context)
            Issue.record("Accepted multiple AIRAC packages")
        } catch { #expect(error.localizedDescription.contains("多个 AIRAC")) }
        try fixture.expectNoExtractedFiles()
    }

    @Test func zipRejectsPathsOutsideExtractionDirectoryAndSymlinks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for (path, type) in [("../outside.txt", Entry.EntryType.file), ("/absolute.txt", .file), ("link", .symlink)] {
            let zip = fixture.root.appendingPathComponent("invalid-\(UUID().uuidString).zip")
            let archive = try Archive(url: zip, accessMode: .create)
            let payload = Data("outside".utf8)
            try archive.addEntry(with: path, type: type, uncompressedSize: Int64(payload.count)) { position, count in
                payload.subdata(in: Int(position)..<(Int(position) + count))
            }
            do {
                _ = try AIRACArchiveExtractor(temporaryDirectory: fixture.root).extract(at: zip, progress: Progress())
                Issue.record("Accepted unsupported ZIP path")
            } catch { #expect(error.localizedDescription.contains("不支持的路径或符号链接")) }
            #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("outside.txt").path))
            try fixture.expectNoExtractedFiles()
        }
    }

    @Test func corruptedZipChecksumIsRejectedAndCleanedUp() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try fixture.package()
        let zip = try fixture.archive(package, compression: .none)
        var bytes = try Data(contentsOf: zip)
        let contents = try Data(contentsOf: package.appendingPathComponent("Data/Customers.js"))
        let range = try #require(bytes.range(of: contents))
        bytes[range.lowerBound] ^= 1
        try bytes.write(to: zip)
        do {
            _ = try AIRACArchiveExtractor(temporaryDirectory: fixture.root).extract(at: zip, progress: Progress())
            Issue.record("Accepted corrupt ZIP checksum")
        } catch { #expect(error.localizedDescription.contains("ZIP 解压失败")) }
        try fixture.expectNoExtractedFiles()
    }

    @Test func failedZIPExtractionWriteKeepsCurrentCycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let zip = try fixture.archive(fixture.package(version: "2602", date: "2602010000"))
        let blocked = fixture.root.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocked)
        let store = AIRACPackageStore(files: fixture.files, archiveExtractor: AIRACArchiveExtractor(temporaryDirectory: blocked))
        do {
            try await store.importPackage(from: zip, isZIPArchive: true, modelContext: fixture.context)
            Issue.record("Accepted extraction write failure")
        } catch { #expect(error.localizedDescription.contains("ZIP 解压失败")) }
        try fixture.expectCurrent("2601", pages: 1)
        try fixture.expectNoExtractedFiles()
    }

    @Test func cancelledZIPImportCleansUpAndKeepsCurrentCycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let zip = try fixture.archive(fixture.package(version: "2602", date: "2602010000"))
        let task = Task { @MainActor in
            try await fixture.store.importPackage(from: zip, isZIPArchive: true, modelContext: fixture.context) { fraction, message in
                if fraction == 0, message.contains("解压") { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            try await task.value
            Issue.record("Cancelled ZIP import committed data")
        } catch { #expect(error is CancellationError) }
        try fixture.expectCurrent("2601", pages: 1)
        try fixture.expectNoExtractedFiles()
    }

    @MainActor
    final class Fixture {
        let root: URL
        let cacheRoot: URL
        let container: ModelContainer
        let files: AIRACFileStore
        let store: AIRACPackageStore
        var context: ModelContext { container.mainContext }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("EAIPTests-\(UUID().uuidString)")
            cacheRoot = root.appendingPathComponent("AppDocuments")
            try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            container = try ModelContainer(
                for: AIRACVersion.self, LocalChart.self, Airport.self, PinnedChart.self, ChartAnnotation.self, UserSettings.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            container.mainContext.autosaveEnabled = false
            files = AIRACFileStore(documentsDirectory: cacheRoot)
            store = AIRACPackageStore(files: files, archiveExtractor: AIRACArchiveExtractor(temporaryDirectory: root))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        func archive(_ folder: URL, keepParent: Bool = true, compression: CompressionMethod = .deflate) throws -> URL {
            let zip = root.appendingPathComponent("package-\(UUID().uuidString).zip")
            try FileManager.default.zipItem(at: folder, to: zip, shouldKeepParent: keepParent, compressionMethod: compression)
            return zip
        }

        func expectNoExtractedFiles() throws {
            let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            #expect(!contents.contains { $0.lastPathComponent.hasPrefix("AIRACImport-") })
        }

        func node(_ id: String, _ parent: String, _ name: String, _ path: String) -> [String: String] {
            ["id": id, "pId": parent, "name": name, "name_cn": name, "pdfPath": path]
        }

        func writeJSON(_ values: [[String: String]], to name: String, in package: URL) throws {
            try JSONSerialization.data(withJSONObject: values).write(to: package.appendingPathComponent("Data/JsonPath/\(name)"))
        }

        func package(
            version: String = "2601", date: String = "2601010000", airportName: String = "Original",
            chartIDs: [String] = ["chart_one"], chartName: String = "SID original", icao: String = "ZBAA",
            notam: Bool = false, pages: Int = 1
        ) throws -> URL {
            let package = root.appendingPathComponent("package-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: package.appendingPathComponent("Data/JsonPath"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: package.appendingPathComponent("Data/PDFs"), withIntermediateDirectories: true)
            try "var Customers=[{DataVersion:\"\(version)\",EffectiveDate:\"\(date)\"}];".write(
                to: package.appendingPathComponent("Data/Customers.js"), atomically: true, encoding: .utf8)
            var airport = node("airport", "0", "\(icao)-\(airportName)", "/Data/PDFs/ad.pdf")
            airport["airporticao"] = icao
            airport["Is_Modified"] = "Y"
            var ad = [airport, node("chart_section", "airport", "Charts related to an aerodrome", "")]
            for (index, id) in chartIDs.enumerated() {
                ad.append(node(id, "chart_section", "\(chartName) \(index)", "/Data/PDFs/chart_\(index).pdf"))
            }
            try writeJSON(ad, to: "AD.JSON", in: package)
            try writeJSON([node("gen", "0", "GEN", "/Data/PDFs/gen.pdf")], to: "GEN.JSON", in: package)
            try writeJSON([
                node("enr", "0", "ENR", "/Data/PDFs/enr.pdf"),
                node("routes", "0", "EN-ROUTE CHARTS", ""),
                node("route_one", "routes", "EN-ROUTE CHART", "/Data/PDFs/route.pdf")
            ], to: "ENR.JSON", in: package)
            if notam {
                try writeJSON([[
                    "SeriesName": "A_series", "Document": "/Data/PDFs/notam.pdf",
                    "GenerateTime": "2026/10/20 08:00", "GenerateTime_En": "20 October 2026"
                ]], to: "NOTAM.JSON", in: package)
            }
            let names = ["ad", "gen", "enr", "route", "notam"] + chartIDs.indices.map { "chart_\($0)" }
            let data = try Self.pdf(pages: pages)
            for name in names { try data.write(to: package.appendingPathComponent("Data/PDFs/\(name).pdf")) }
            return package
        }

        static func pdf(pages: Int = 1) throws -> Data {
            let data = NSMutableData()
            let consumer = try #require(CGDataConsumer(data: data))
            var box = CGRect(x: 0, y: 0, width: 200, height: 200)
            let drawing = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            for _ in 0..<pages {
                drawing.beginPDFPage(nil)
                drawing.fill(CGRect(x: 10, y: 10, width: 30, height: 30))
                drawing.endPDFPage()
            }
            drawing.closePDF()
            return data as Data
        }

        func install(version: String, date: String, pages: Int = 1) async throws {
            try await store.importPackage(from: package(version: version, date: date, pages: pages), modelContext: context)
        }

        func document(_ chart: LocalChart, version: AIRACVersion) -> PDFDocument? {
            files.loadPDF(version: version.version, revision: version.cacheRevision, documentType: chart.documentType, id: chart.cacheDocumentID)
        }

        func expectCurrent(_ expected: String, pages: Int) throws {
            let current = try #require(try AIRACPackageStore.currentVersion(modelContext: context))
            #expect(current.version == expected)
            let chart = try #require(try AIRACPackageStore.currentCharts(modelContext: context, documentType: "chart").first)
            #expect(document(chart, version: current)?.pageCount == pages)
        }

        func expectFailure(_ package: URL, using failingStore: AIRACPackageStore? = nil, message: String? = nil) async {
            do {
                try await (failingStore ?? store).importPackage(from: package, modelContext: context)
                Issue.record("Expected import failure")
            } catch {
                if let message { #expect(error.localizedDescription.contains(message)) }
            }
        }
    }

    enum LegacySchema {
        @Model
        final class AIRACVersion {
            @Attribute(.unique) var version: String
            var effectiveDate: Date
            var isCurrent: Bool = false
            var downloadedCharts: Int = 0
            var totalCharts: Int = 0
            var createdAt: Date = Date()
            var source: String = "local"

            init(version: String) {
                self.version = version
                effectiveDate = Date()
                isCurrent = true
            }
        }
    }
}
