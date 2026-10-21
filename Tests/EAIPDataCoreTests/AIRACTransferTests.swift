import Foundation
import Testing
@testable import EAIPDataCore

@Suite("Bounded AIRAC downloads and retries", .serialized)
@MainActor
struct AIRACTransferTests {
    actor Probe {
        var active = 0
        var peak = 0
        var attempts = 0
        func downloaded(_ url: URL, server: AIRACServerTests.Server) async throws -> AIRACServerResponse {
            guard url.path.hasSuffix(".pdf") else { return await server.respond(url) }
            active += 1
            peak = max(peak, active)
            defer { active -= 1 }
            try await Task.sleep(nanoseconds: 20_000_000)
            return await server.respond(url)
        }
        func transientResponse() throws -> AIRACServerResponse {
            attempts += 1
            if attempts == 1 { return AIRACServerResponse(data: Data(), statusCode: 503) }
            if attempts == 2 { throw URLError(.timedOut) }
            return AIRACServerResponse(data: Data("success".utf8), statusCode: 200)
        }
        func status(_ code: Int) -> AIRACServerResponse {
            attempts += 1
            return AIRACServerResponse(data: Data(), statusCode: code)
        }
    }

    @Test func parallelCopyIsBoundedAndMakesEveryPDFAvailableOffline() async throws {
        let fixture = try AIRACDataCoreTests.Fixture(); defer { fixture.remove() }
        let serverTests = AIRACServerTests()
        let package = try fixture.package(chartIDs: (0..<12).map { "chart_\($0)" })
        let (server, _) = try serverTests.server(package)
        let probe = Probe()
        let client = AIRACServerClient(retryDelayNanoseconds: 0) { try await probe.downloaded($0, server: server) }
        try await fixture.store.configureServer(serverTests.configuration(.copy), modelContext: fixture.context, client: client)
        #expect(await probe.peak > 1)
        #expect(await probe.peak <= 4)
        #expect(await probe.active == 0)
        try fixture.expectCurrent("2601", pages: 1)
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context))
        #expect(current.downloadedCharts == 16)
        let offline = AIRACServerClient { _ in throw URLError(.notConnectedToInternet) }
        let charts = try await AIRACPackageStore.loadCharts(modelContext: fixture.context, documentType: "chart", client: offline)
        #expect(charts.count == 12)
        for chart in charts {
            let loaded = try await AIRACPackageStore.loadDocument(chartID: chart.readerChartID, documentType: "chart",
                version: "2601", modelContext: fixture.context, client: offline, files: fixture.files)
            #expect(loaded.document.pageCount == 1)
        }
    }

    @Test func transientHTTPAndNetworkErrorsAreRetried() async throws {
        let probe = Probe()
        let client = AIRACServerClient(retryDelayNanoseconds: 0) { _ in try await probe.transientResponse() }
        let config = try AIRACServerTests().configuration(.copy)
        #expect(try await client.fetch("Data/PDFs/test.pdf", from: config) == Data("success".utf8))
        #expect(await probe.attempts == 3)
    }

    @Test(arguments: [401, 403, 404])
    func permanentHTTPFailuresAreNotRetried(_ status: Int) async throws {
        let probe = Probe()
        let client = AIRACServerClient(retryDelayNanoseconds: 0) { _ in await probe.status(status) }
        let config = try AIRACServerTests().configuration(.copy)
        await #expect(throws: (any Error).self) { try await client.fetch("Data/PDFs/test.pdf", from: config) }
        #expect(await probe.attempts == 1)
    }

    @Test func missingOptionalIndexIsNotRetried() async throws {
        let probe = Probe()
        let client = AIRACServerClient(retryDelayNanoseconds: 0) { _ in await probe.status(404) }
        let config = try AIRACServerTests().configuration(.request)
        #expect(try await client.fetch("Data/JsonPath/AIC.JSON", from: config, optional: true) == nil)
        #expect(await probe.attempts == 1)
    }

    @Test func exhaustedRetriesDrainDownloadsAndKeepPreviousRevision() async throws {
        let fixture = try AIRACDataCoreTests.Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let original = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context)?.cacheRevision)
        let serverTests = AIRACServerTests()
        let (server, _) = try serverTests.server(fixture.package())
        await server.set("Data/PDFs/gen.pdf", status: 503)
        let probe = Probe()
        let client = AIRACServerClient(retryDelayNanoseconds: 0) { try await probe.downloaded($0, server: server) }
        await #expect(throws: (any Error).self) {
            try await fixture.store.configureServer(serverTests.configuration(.copy), modelContext: fixture.context, client: client)
        }
        #expect(await probe.active == 0)
        #expect(await server.requests.filter { $0.hasSuffix("/gen.pdf") }.count == 3)
        try fixture.expectCurrent("2601", pages: 1)
        let directories = try FileManager.default.contentsOfDirectory(
            at: fixture.cacheRoot.appendingPathComponent("PDFCache/2601"), includingPropertiesForKeys: nil)
        #expect(directories.map(\.lastPathComponent) == [original])
    }
}
