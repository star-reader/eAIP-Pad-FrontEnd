import Foundation
import SwiftData
import Testing
@testable import EAIPDataCore

@Suite("ENR area chart classification", .serialized)
@MainActor
struct EAIPChartClassificationTests {
    typealias Fixture = AIRACDataCoreTests.Fixture

    @Test(arguments: [
        "ENR 6.3.1 ARC Beijing", "ENR 6.3.2 ARC Guangzhou", "ENR 6.3.3 ARC Shanghai",
        "ENR 6.3.1 arc Beijing", "ARC-Beijing", "ENR 6.3.1 (ARC) Beijing", "AREA CHART Beijing"
    ])
    func recognizesAreaChartNames(_ name: String) {
        #expect(EAIPChartClassifier.classifyEnroute(name: name) == "AREA")
    }

    @Test func chineseNameProvidesAreaChartFallback() {
        #expect(EAIPChartClassifier.classifyEnroute(name: "ENR 6.3.1 Beijing", nameCn: "ENR 6.3.1 区域图-北京") == "AREA")
        #expect(EAIPChartClassifier.classifyEnroute(name: "ENR 6.3.1 區域圖-北京") == "AREA")
    }

    @Test(arguments: ["SEARCH AND RESCUE CHART", "ARCHIVE INDEX", "ARCTIC CHART", "ENR 6 Other chart"])
    func doesNotMatchARCInsideOtherWords(_ name: String) {
        #expect(EAIPChartClassifier.classifyEnroute(name: name) == "OTHERS")
    }

    @Test func existingEnrouteAndKnownTypesArePreserved() {
        #expect(EAIPChartClassifier.classifyEnroute(name: "ENR 6.2 EN-ROUTE CHART") == "ENROUTE")
        #expect(EAIPChartClassifier.classifyEnroute(name: "ENR 6.1 List of EN-ROUTE charts") == "ENROUTE")
        let airportChart = LocalChart(chartID: "terminal", documentID: "terminal", nameEn: "ARC Beijing", nameCn: "区域图-北京",
            chartType: "OTHERS", airacVersion: "2601", documentType: "chart")
        #expect(airportChart.toChartResponse().chartType == "OTHERS")
        let knownArea = LocalChart(chartID: "known", documentID: "known", nameEn: "Custom title", nameCn: "",
            chartType: "AREA", airacVersion: "2601", documentType: "enroute")
        #expect(knownArea.toChartResponse().chartType == "AREA")
    }

    func package(_ fixture: Fixture) throws -> URL {
        let package = try fixture.package(pages: 2)
        var nodes = [
            fixture.node("enr", "0", "ENR", "/Data/PDFs/enr.pdf"),
            fixture.node("routes", "0", "EN-ROUTE CHARTS", ""),
            fixture.node("route_one", "routes", "ENR 6.2 EN-ROUTE CHART", "/Data/PDFs/route.pdf"),
            fixture.node("other", "routes", "SEARCH AND RESCUE CHART", "/Data/PDFs/route.pdf")
        ]
        for (index, names) in [("Beijing", "北京"), ("Guangzhou", "广州"), ("Shanghai", "上海")].enumerated() {
            var node = fixture.node("area_\(index)", "routes", "ENR 6.3.\(index + 1) ARC \(names.0)", "/Data/PDFs/route.pdf")
            node["name_cn"] = "ENR 6.3.\(index + 1) 区域图-\(names.1)"
            nodes.append(node)
        }
        try fixture.writeJSON(nodes, to: "ENR.JSON", in: package)
        return package
    }

    func expectCategories(_ charts: [ChartResponse]) {
        #expect(Set(charts.filter { $0.chartType == "AREA" }.map(\.documentId)) == ["area_0", "area_1", "area_2"])
        #expect(charts.filter { $0.chartType == "ENROUTE" }.map(\.documentId) == ["route_one"])
        #expect(charts.filter { $0.chartType == "OTHERS" }.map(\.documentId) == ["other"])
    }

    @Test func localImportAndLegacyStoredClassificationsWorkWithoutReimport() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.store.importPackage(from: package(fixture), modelContext: fixture.context)
        let stored = try AIRACPackageStore.currentCharts(modelContext: fixture.context, documentType: "enroute")
        expectCategories(stored.map { $0.toChartResponse() })
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context))
        let revision = current.cacheRevision
        for chart in stored where chart.documentID.hasPrefix("area_") { chart.chartType = "OTHERS" }
        try fixture.context.save()
        let loaded = try await AIRACPackageStore.loadCharts(modelContext: fixture.context, documentType: "enroute")
        expectCategories(loaded.map { $0.toChartResponse() })
        #expect(!fixture.context.hasChanges)
        #expect(current.cacheRevision == revision)
        let document = try await AIRACPackageStore.loadDocument(chartID: "enroute_area_0", documentType: "enroute",
            version: "2601", modelContext: fixture.context, files: fixture.files)
        #expect(document.chart.effectiveChartType == "AREA")
        #expect(document.document.pageCount == 2)
    }

    @Test func serverCopyAndRequestUseTheSameAreaClassification() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let helpers = AIRACServerTests()
        let (_, client) = try helpers.server(package(fixture))
        for mode in AIRACServerMode.allCases {
            try await fixture.store.configureServer(helpers.configuration(mode), modelContext: fixture.context, client: client)
            let charts = try await AIRACPackageStore.loadCharts(modelContext: fixture.context, documentType: "enroute", client: client)
            expectCategories(charts.map { $0.toChartResponse() })
        }
    }
}
