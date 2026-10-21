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
            components.query == nil, components.fragment == nil
        else {
            throw AIRACPackageError.invalidPackage("请输入有效的 HTTPS 数据包根目录地址，不包含账号、查询参数或片段")
        }
        components.scheme = "https"
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

    init(transport: Transport? = nil) {
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
        try Task.checkCancellation()
        let response = try await transport(configuration.resourceURL(path))
        try Task.checkCancellation()
        if optional, response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else {
            throw AIRACPackageError.invalidPackage("请求 \(path) 失败（HTTP \(response.statusCode)）")
        }
        return response.data
    }

    func metadata(from configuration: AIRACServerConfiguration) async throws -> (version: String, effectiveDate: Date) {
        let data = try await fetch("Data/Customers.js", from: configuration)!
        return try LocalAIRACPackageParser.metadata(data)
    }

    func catalog(
        from configuration: AIRACServerConfiguration,
        sections: [String] = ["AD", "GEN", "ENR", "SUP", "NOTAM"],
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
                optional: section == "SUP" || section == "NOTAM")
        }
        let parsed = try LocalAIRACPackageParser.parse(
            customers: customers, indexes: indexes, requireDocuments: requireDocuments)
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
        case "aip": return ["GEN", "ENR"]
        case "sup", "amdt": return ["SUP"]
        case "notam": return ["NOTAM"]
        default: return []
        }
    }
}
