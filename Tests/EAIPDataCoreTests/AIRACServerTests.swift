import Foundation
import SwiftData
import Testing
@testable import EAIPDataCore

@Suite("AIRAC online import", .serialized)
@MainActor
struct AIRACServerTests {
    typealias Fixture = AIRACDataCoreTests.Fixture

    actor Server {
        var resources: [String: AIRACServerResponse]
        var requests: [String] = []
        var metadataReads = 0
        var metadataChange: (after: Int, data: Data)?
        var blockedPath: String?
        var pendingResponse: CheckedContinuation<Void, Never>?
        var blockObserver: CheckedContinuation<Void, Never>?
        init(resources: [String: AIRACServerResponse]) { self.resources = resources }
        func respond(_ url: URL) async -> AIRACServerResponse {
            if url.path == blockedPath {
                await withCheckedContinuation { continuation in
                    pendingResponse = continuation
                    blockObserver?.resume()
                    blockObserver = nil
                }
            }
            requests.append(url.path)
            if url.path.hasSuffix("/Data/Customers.js") {
                metadataReads += 1
                if let change = metadataChange, metadataReads >= change.after {
                    resources[url.path] = AIRACServerResponse(data: change.data, statusCode: 200)
                }
            }
            return resources[url.path] ?? AIRACServerResponse(data: Data(), statusCode: 404)
        }
        func set(_ path: String, data: Data = Data(), status: Int = 200) {
            resources["/packages/current/" + path] = AIRACServerResponse(data: data, statusCode: status)
        }
        func resetRequests() { requests = [] }
        func block(_ path: String) { blockedPath = "/packages/current/" + path }
        func waitUntilBlocked() async {
            if pendingResponse != nil { return }
            await withCheckedContinuation { blockObserver = $0 }
        }
        func release() {
            blockedPath = nil
            pendingResponse?.resume()
            pendingResponse = nil
        }
        func changeCycle(after read: Int) {
            metadataReads = 0
            metadataChange = (read, Data("var Customers=[{DataVersion:'2602',EffectiveDate:'2602010000'}];".utf8))
        }
    }

    func server(_ package: URL) throws -> (Server, AIRACServerClient) {
        var resources: [String: AIRACServerResponse] = [:]
        let enumerator = try #require(FileManager.default.enumerator(at: package, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(package.resolvingSymlinksInPath().path.count))
            resources["/packages/current" + path] = AIRACServerResponse(data: try Data(contentsOf: url), statusCode: 200)
        }
        let server = Server(resources: resources)
        return (server, AIRACServerClient { await server.respond($0) })
    }

    func configuration(_ mode: AIRACServerMode) throws -> AIRACServerConfiguration {
        try AIRACServerConfiguration(address: "https://example.com/packages/current", mode: mode)
    }

    @Test func serverAddressAndPathsPreservePackageRoot() throws {
        let config = try AIRACServerConfiguration(address: "  https://example.com/packages/current  ", mode: .request)
        #expect(config.rootURL.absoluteString == "https://example.com/packages/current/")
        #expect(try config.resourceURL("/Data/PDFs/a%20b.pdf").absoluteString == "https://example.com/packages/current/Data/PDFs/a%20b.pdf")
        for address in ["", "file:///tmp/data", "http://example.com/", "https://name:secret@example.com/", "https://example.com/?token=x", "https://example.com/?token=x#/eaip"] {
            #expect(throws: (any Error).self) { try AIRACServerConfiguration(address: address, mode: .copy) }
        }
        for path in ["../outside.pdf", "/Data/../../outside.pdf", "%2e%2e/outside.pdf", "//other.example/file.pdf", "https://other.example/file.pdf", "Data\\outside.pdf", ""] {
            #expect(throws: (any Error).self) { try config.resourceURL(path) }
        }
    }

    @Test(arguments: AIRACServerMode.allCases)
    func serverAddressesIgnoreHashRoutesAndNormalizeTrailingSlash(_ mode: AIRACServerMode) throws {
        for root in ["https://example.com", "https://example.com/packages/current"] {
            let expectedRoot = root + "/"
            for suffix in ["", "/", "#/eaip", "/#/eaip", "/#/eaip/", "/#/", "/#/ad", "/#", "/#/eaip?tab=AD"] {
                let configuration = try AIRACServerConfiguration(address: "  \(root)\(suffix)  ", mode: mode)
                #expect(configuration.rootURL.absoluteString == expectedRoot)
                #expect(try configuration.resourceURL("Data/Customers.js").absoluteString == expectedRoot + "Data/Customers.js")
                #expect(try configuration.resourceURL("/Data/PDFs/chart.pdf").absoluteString == expectedRoot + "Data/PDFs/chart.pdf")
            }
        }
        // %23 is part of a real path component, rather than a hash-router separator.
        let encoded = try AIRACServerConfiguration(address: "https://example.com/package%23archive/#/ad", mode: mode)
        #expect(encoded.rootURL.absoluteString == "https://example.com/package%23archive/")
    }

    @Test(arguments: AIRACServerMode.allCases)
    func hashRoutedServerImportPersistsNormalizedRootAndLoadsPDF(_ mode: AIRACServerMode) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let (server, client) = try server(fixture.package())
        let configuration = try AIRACServerConfiguration(
            address: "https://example.com/packages/current/#/eaip/", mode: mode)
        try await fixture.store.configureServer(configuration, modelContext: fixture.context, client: client)
        let reopened = ModelContext(fixture.container)
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: reopened))
        #expect(current.serverURL == "https://example.com/packages/current/")
        let charts = try await AIRACPackageStore.loadCharts(modelContext: reopened, documentType: "chart", client: client)
        let chart = try #require(charts.first)
        let loaded = try await AIRACPackageStore.loadDocument(
            chartID: chart.readerChartID, documentType: "chart", version: current.version,
            modelContext: reopened, client: client, files: fixture.files)
        #expect(loaded.document.pageCount == 1)
        let requests = await server.requests
        #expect(requests.allSatisfy { $0.hasPrefix("/packages/current/Data/") && !$0.contains("#") })
    }

    @Test func copyPersistsConfigurationAndAllPDFsWorkOffline() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let (_, client) = try server(fixture.package(notam: true, pages: 2))
        try await fixture.store.configureServer(configuration(.copy), modelContext: fixture.context, client: client)
        let reopened = ModelContext(fixture.container)
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: reopened))
        #expect(current.source == "serverCopy")
        #expect(current.serverURL == "https://example.com/packages/current/")
        #expect(current.downloadedCharts == current.totalCharts)
        let offline = AIRACServerClient { _ in throw URLError(.notConnectedToInternet) }
        let charts = try await AIRACPackageStore.loadCharts(modelContext: reopened, documentType: "notam", client: offline)
        let chart = try #require(charts.first)
        let document = try await AIRACPackageStore.loadDocument(chartID: chart.readerChartID, documentType: "notam",
            version: "2601", modelContext: reopened, client: offline, files: fixture.files)
        #expect(document.document.pageCount == 2)
    }

    @Test func requestStoresOnlyConnectionAndFetchesFreshLists() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let package = try fixture.package()
        let (server, client) = try server(package)
        try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
        #expect(try fixture.context.fetch(FetchDescriptor<LocalChart>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<Airport>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheRoot.appendingPathComponent("PDFCache").path))
        let reopened = ModelContext(fixture.container)
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: reopened))
        #expect(current.source == "serverRequest")
        #expect(current.serverURL != nil)
        #expect(current.downloadedCharts == 0)
        #expect(current.totalCharts == 5)
        await server.resetRequests()
        let airports = try await AIRACPackageStore.loadAirports(modelContext: reopened, client: client)
        #expect(airports.first?.nameCn == "Original")
        let requests = await server.requests
        #expect(requests.contains("/packages/current/Data/JsonPath/AD.JSON"))
        #expect(!requests.contains { $0.contains("GEN.JSON") || $0.hasSuffix(".pdf") })
        var modified = try String(contentsOf: package.appendingPathComponent("Data/JsonPath/AD.JSON"), encoding: .utf8)
        modified = modified.replacingOccurrences(of: "Original", with: "Updated")
        await server.set("Data/JsonPath/AD.JSON", data: Data(modified.utf8))
        let updated = try await AIRACPackageStore.loadAirports(modelContext: reopened, client: client)
        #expect(updated.first?.nameCn == "Updated")
        #expect(try reopened.fetch(FetchDescriptor<Airport>()).isEmpty)
        #expect(!reopened.hasChanges)
    }

    @Test func requestLoadsEveryPageTypeAndCompoundNotamPDF() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let package = try fixture.package(notam: true, pages: 2)
        try fixture.writeJSON([["Id": "sup_1", "Document": "/Data/PDFs/notam.pdf", "Serial": "001"]], to: "SUP.JSON", in: package)
        let (_, client) = try server(package)
        try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
        for type in ["chart", "ad", "aip", "enroute", "sup", "notam"] {
            let charts = try await AIRACPackageStore.loadCharts(modelContext: fixture.context, documentType: type, client: client)
            let chart = try #require(charts.first)
            let resolved = try await AIRACPackageStore.loadDocument(chartID: chart.readerChartID, documentType: type,
                version: "2601", modelContext: fixture.context, client: client, files: fixture.files)
            #expect(resolved.document.pageCount == 2)
            #expect(resolved.chart.readerChartID == chart.readerChartID)
        }
        #expect(try fixture.context.fetch(FetchDescriptor<LocalChart>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheRoot.appendingPathComponent("PDFCache").path))
    }

    @Test func failedRequiredIndexOrOptionalServerErrorPreservesLocalData() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        for (path, status) in [("Data/JsonPath/AD.JSON", 404), ("Data/JsonPath/SUP.JSON", 500)] {
            let (server, client) = try server(fixture.package(version: "2602", date: "2602010000"))
            await server.set(path, status: status)
            await #expect(throws: (any Error).self) {
                try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
            }
            try fixture.expectCurrent("2601", pages: 1)
        }
    }

    @Test func copyInvalidPDFRollsBackAndRemovesPartialRevision() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let previous = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context)?.cacheRevision)
        let (server, client) = try server(fixture.package())
        await server.set("Data/PDFs/gen.pdf", data: Data("<html>login</html>".utf8))
        await #expect(throws: (any Error).self) {
            try await fixture.store.configureServer(configuration(.copy), modelContext: fixture.context, client: client)
        }
        try fixture.expectCurrent("2601", pages: 1)
        #expect(try AIRACPackageStore.currentVersion(modelContext: fixture.context)?.source == "local")
        let directories = try FileManager.default.contentsOfDirectory(
            at: fixture.cacheRoot.appendingPathComponent("PDFCache/2601"), includingPropertiesForKeys: nil)
        #expect(directories.map(\.lastPathComponent) == [previous])
    }

    @Test func databaseFailureRollsBackBothServerModes() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let (_, client) = try server(fixture.package())
        let store = AIRACPackageStore(files: fixture.files) { _ in throw AIRACDataCoreTests.InjectedFailure.database }
        for mode in AIRACServerMode.allCases {
            await #expect(throws: (any Error).self) {
                try await store.configureServer(configuration(mode), modelContext: fixture.context, client: client)
            }
            try fixture.expectCurrent("2601", pages: 1)
            #expect(try AIRACPackageStore.currentVersion(modelContext: fixture.context)?.serverURL == nil)
        }
        let directories = try FileManager.default.contentsOfDirectory(
            at: fixture.cacheRoot.appendingPathComponent("PDFCache/2601"), includingPropertiesForKeys: nil)
        #expect(directories.count == 1)
    }

    @Test func cancelledCopyPreservesCurrentDataAndCleansFiles() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let (_, client) = try server(fixture.package(version: "2602", date: "2602010000"))
        let task = Task { @MainActor in
            try await fixture.store.configureServer(configuration(.copy), modelContext: fixture.context, client: client) { fraction, _ in
                if fraction > 0.1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        try fixture.expectCurrent("2601", pages: 1)
        let directory = fixture.cacheRoot.appendingPathComponent("PDFCache/2602")
        if FileManager.default.fileExists(atPath: directory.path) {
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    @Test func changedCycleAndUnreachableServerNeverFallBackToOldMetadata() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let (server, client) = try server(fixture.package())
        try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
        await server.set("Data/Customers.js", data: Data("var Customers=[{DataVersion:'2602',EffectiveDate:'2602010000'}];".utf8))
        await #expect(throws: (any Error).self) {
            try await AIRACPackageStore.loadCharts(modelContext: fixture.context, documentType: "chart", client: client)
        }
        let offline = AIRACServerClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) {
            try await AIRACPackageStore.loadAirports(modelContext: fixture.context, client: offline)
        }
        #expect(try AIRACPackageStore.currentVersion(modelContext: fixture.context)?.version == "2601")
    }

    @Test func requestMissingPDFReportsFailureWithoutCachingOrChangingSource() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let (server, client) = try server(fixture.package())
        try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
        for status in [404, 200] {
            await server.set("Data/PDFs/chart_0.pdf", data: Data("invalid".utf8), status: status)
            await #expect(throws: (any Error).self) {
                try await AIRACPackageStore.loadDocument(chartID: "chart_chart_one", documentType: "chart",
                    version: "2601", modelContext: fixture.context, client: client, files: fixture.files)
            }
        }
        #expect(try AIRACPackageStore.currentVersion(modelContext: fixture.context)?.source == "serverRequest")
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheRoot.appendingPathComponent("PDFCache").path))
    }

    @Test func serverChangesDuringCatalogOrCopyNeverActivateMixedCycle() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        for read in [2, 3] {
            let (server, client) = try server(fixture.package())
            await server.changeCycle(after: read)
            do {
                try await fixture.store.configureServer(configuration(.copy), modelContext: fixture.context, client: client)
                Issue.record("Activated mixed cycle")
            } catch { #expect(error.localizedDescription.contains(read == 2 ? "正在更新" : "周期已变更")) }
            try fixture.expectCurrent("2601", pages: 1)
        }
    }

    @Test func copyWriteFailureAndMissingDownloadPreservePreviousRevision() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.install(version: "2601", date: "2601010000")
        let (server, client) = try server(fixture.package())
        let failingFiles = AIRACFileStore(documentsDirectory: fixture.cacheRoot) { _, _ in
            throw AIRACDataCoreTests.InjectedFailure.write
        }
        let failingStore = AIRACPackageStore(files: failingFiles)
        do {
            try await failingStore.configureServer(configuration(.copy), modelContext: fixture.context, client: client)
            Issue.record("Accepted write failure")
        } catch { #expect(error.localizedDescription.contains("处理文件失败")) }
        await server.set("Data/PDFs/gen.pdf", status: 404)
        do {
            try await fixture.store.configureServer(configuration(.copy), modelContext: fixture.context, client: client)
            Issue.record("Accepted missing PDF")
        } catch { #expect(error.localizedDescription.contains("HTTP 404")) }
        try fixture.expectCurrent("2601", pages: 1)
        let directories = try FileManager.default.contentsOfDirectory(
            at: fixture.cacheRoot.appendingPathComponent("PDFCache/2601"), includingPropertiesForKeys: nil)
        #expect(directories.count == 1)
    }

    @Test func requestDoesNotShowPDFIfCycleChangesDuringDownload() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let (server, client) = try server(fixture.package())
        try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
        await server.changeCycle(after: 3)
        do {
            _ = try await AIRACPackageStore.loadDocument(chartID: "chart_chart_one", documentType: "chart",
                version: "2601", modelContext: fixture.context, client: client, files: fixture.files)
            Issue.record("Displayed PDF under stale cycle")
        } catch { #expect(error.localizedDescription.contains("周期已变更")) }
    }

    @Test func requestEmptyOptionalCategoryIsValid() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let (_, client) = try server(fixture.package())
        try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
        for type in ["sup", "notam"] {
            #expect(try await AIRACPackageStore.loadCharts(modelContext: fixture.context, documentType: type, client: client).isEmpty)
        }
    }

    @Test func inFlightRequestCannotPublishAfterSourceChanges() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let (server, client) = try server(fixture.package())
        try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
        await server.block("Data/JsonPath/AD.JSON")
        let pending = Task { @MainActor in
            try await AIRACPackageStore.loadAirports(modelContext: fixture.context, client: client)
        }
        await server.waitUntilBlocked()
        try await fixture.install(version: "2601", date: "2601010000")
        await server.release()
        do {
            _ = try await pending.value
            Issue.record("Published stale remote airports after source switch")
        } catch { #expect(error.localizedDescription.contains("数据源已更改")) }
        try fixture.expectCurrent("2601", pages: 1)
    }

    @Test func sameCycleSwitchToLocalClearsServerConfiguration() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let (_, client) = try server(fixture.package())
        try await fixture.store.configureServer(configuration(.request), modelContext: fixture.context, client: client)
        try await fixture.install(version: "2601", date: "2601010000")
        let current = try #require(try AIRACPackageStore.currentVersion(modelContext: fixture.context))
        #expect(current.source == "local")
        #expect(current.serverURL == nil)
        try fixture.expectCurrent("2601", pages: 1)
    }
}
