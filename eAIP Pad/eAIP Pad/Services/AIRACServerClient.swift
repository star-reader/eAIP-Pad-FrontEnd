import Foundation

nonisolated enum AIRACServerMode: String, CaseIterable, Sendable {
    case copy
    case request

    var source: String { self == .copy ? "serverCopy" : "serverRequest" }
    var title: String { self == .copy ? "复制" : "请求" }
}

nonisolated struct AIRACServerConfiguration: Equatable, Sendable {
    let rootURL: URL
    let mode: AIRACServerMode

    init(address: String, mode: AIRACServerMode) throws {
        guard var components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil
        else {
            throw AIRACPackageError.invalidPackage("请输入有效的 HTTPS 数据包根目录地址，不包含账号或查询参数")
        }
        components.scheme = "https"
        // # 后的内容属于 Web 前端路由，不参与数据包路径解析或服务器请求。
        components.fragment = nil
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let url = components.url else {
            throw AIRACPackageError.invalidPackage("服务器地址无效")
        }
        self.rootURL = url
        self.mode = mode
    }

    /// 官方包的 /Data 路径仍相对于用户填写的包根目录，而不是服务器域名根目录。
    func resourceURL(_ path: String) throws -> URL {
        guard let decoded = path.removingPercentEncoding,
            !decoded.hasPrefix("//"), !decoded.contains(":"), !decoded.contains("\\"),
            !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw AIRACPackageError.invalidPackage("服务器数据中包含无效文件路径：\(path)") }
        let parts = decoded.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(".."), !parts.contains("."), parts.contains(where: { !$0.isEmpty }) else {
            throw AIRACPackageError.invalidPackage("服务器文件路径超出数据包：\(path)")
        }
        return parts.filter { !$0.isEmpty }.reduce(rootURL) { $0.appendingPathComponent(String($1)) }
    }
}

nonisolated struct AIRACServerResponse: Sendable {
    let data: Data
    let statusCode: Int
}

/// 在线请求禁用持久缓存；复制模式通过 AIRACFileStore 写入事务独立目录。
nonisolated final class AIRACServerClient: Sendable {
    typealias Transport = @Sendable (URL) async throws -> AIRACServerResponse
    static let shared = AIRACServerClient()
    private let transport: Transport
    private let retryDelayNanoseconds: UInt64

    init(retryDelayNanoseconds: UInt64 = 300_000_000, transport: Transport? = nil) {
        self.retryDelayNanoseconds = retryDelayNanoseconds
        if let transport { self.transport = transport }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.timeoutIntervalForRequest = 45
            let session = URLSession(configuration: configuration)
            self.transport = { url in
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, http.url?.scheme == "https" else {
                    throw AIRACPackageError.invalidPackage("服务器未返回有效的 HTTPS 响应")
                }
                return AIRACServerResponse(data: data, statusCode: http.statusCode)
            }
        }
    }

    func fetch(_ path: String, from configuration: AIRACServerConfiguration, optional: Bool = false) async throws -> Data? {
        let url = try configuration.resourceURL(path)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let response: AIRACServerResponse
            do {
                response = try await transport(url)
            } catch {
                try Task.checkCancellation()
                let transientCodes: Set<URLError.Code> = [
                    .timedOut, .networkConnectionLost, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet
                ]
                guard attempt < 2, let error = error as? URLError,
                    transientCodes.contains(error.code) else { throw error }
                try await retryDelay(attempt)
                continue
            }
            try Task.checkCancellation()
            if optional, response.statusCode == 404 { return nil }
            if response.statusCode == 200 { return response.data }
            guard attempt < 2, [408, 429, 500, 502, 503, 504].contains(response.statusCode) else {
                throw AIRACPackageError.invalidPackage("请求 \(path) 失败（HTTP \(response.statusCode)）")
            }
            try await retryDelay(attempt)
        }
        throw AIRACPackageError.invalidPackage("请求 \(path) 失败")
    }

    private func retryDelay(_ attempt: Int) async throws {
        try await Task.sleep(nanoseconds: retryDelayNanoseconds * UInt64(1 << attempt))
    }

    /// 仅保留有限份 PDF 在内存中；任务组退出前等待所有写入结束，失败时可安全回收整批文件。
    @concurrent
    func copyPDFs(
        _ parsed: ParsedAIRACPackage, from configuration: AIRACServerConfiguration,
        to files: AIRACFileStore, revision: String, maximumConcurrentDownloads: Int = 4,
        progress: (@MainActor (Int) async -> Void)? = nil
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = parsed.charts.makeIterator()
            func enqueue(_ chart: ParsedAIRACPackage.Chart) {
                group.addTask {
                    guard let path = chart.pdfPath,
                        let data = try await self.fetch(path, from: configuration) else {
                        throw AIRACPackageError.missingPDF(chart.readerID)
                    }
                    try Task.checkCancellation()
                    try files.savePDF(data, version: parsed.version, revision: revision,
                        documentType: chart.documentType, id: chart.cacheDocumentID)
                }
            }
            for _ in 0..<max(1, maximumConcurrentDownloads) {
                if let chart = pending.next() { enqueue(chart) }
            }
            var completed = 0
            while try await group.next() != nil {
                try Task.checkCancellation()
                completed += 1
                await progress?(completed)
                if let chart = pending.next() { enqueue(chart) }
            }
        }
    }

    func metadata(from configuration: AIRACServerConfiguration) async throws -> (version: String, effectiveDate: Date) {
        let data = try await fetch("Data/Customers.js", from: configuration)!
        return try LocalAIRACPackageParser.metadata(data)
    }

    func catalog(
        from configuration: AIRACServerConfiguration,
        sections: [String] = LocalAIRACPackageParser.allSections,
        expectedVersion: String? = nil, expectedDate: Date? = nil,
        requireDocuments: Bool = true
    ) async throws -> ParsedAIRACPackage {
        let customers = try await fetch("Data/Customers.js", from: configuration)!
        let metadata = try LocalAIRACPackageParser.metadata(customers)
        if let expectedVersion, metadata.version != expectedVersion {
            throw AIRACPackageError.invalidPackage("服务器的 AIRAC 周期已变更，请重新配置在线服务器")
        }
        if let expectedDate, metadata.effectiveDate != expectedDate {
            throw AIRACPackageError.invalidPackage("服务器的生效时间已变更，请重新配置在线服务器")
        }
        var indexes: [String: Data] = [:]
        for section in sections {
            indexes[section] = try await fetch(
                "Data/JsonPath/\(section).JSON", from: configuration,
                optional: LocalAIRACPackageParser.optionalSections.contains(section))
        }
        let parseTask = Task.detached(priority: .userInitiated) { [indexes] in
            try LocalAIRACPackageParser.parse(
                customers: customers, indexes: indexes, requireDocuments: requireDocuments)
        }
        let parsed = try await withTaskCancellationHandler {
            try await parseTask.value
        } onCancel: { parseTask.cancel() }
        try Task.checkCancellation()
        for chart in parsed.charts { _ = try configuration.resourceURL(chart.pdfPath ?? "") }
        // 阻止服务器在读取目录的过程中切换周期，避免新旧索引混用。
        let latest = try await fetch("Data/Customers.js", from: configuration)!
        guard latest == customers else {
            throw AIRACPackageError.invalidPackage("服务器数据正在更新，请稍后重试")
        }
        return parsed
    }

    static func sections(for documentType: String) -> [String] {
        switch documentType {
        case "chart", "ad": return ["AD"]
        case "enroute": return ["ENR"]
        case "aip": return ["GEN", "ENR", "AD"]
        case "sup": return ["SUP"]
        case "aic": return ["AIC"]
        case "amdt": return ["AMDT"]
        case "notam": return ["NOTAM"]
        default: return []
        }
    }
}
