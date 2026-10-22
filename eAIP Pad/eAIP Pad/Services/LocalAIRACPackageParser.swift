import Foundation

nonisolated struct ParsedAIRACPackage: Sendable {
    nonisolated struct AirportInfo: Sendable {
        let icao: String
        let nameEn: String
        let nameCn: String
        let isModified: Bool
    }

    nonisolated struct Chart: Sendable {
        let documentID: String
        let nameEn: String
        let nameCn: String
        let chartType: String
        let documentType: String
        let pdfPath: String?
        let icao: String?
        let parentID: String?
        let isModified: Bool
        let category: String?
        let serialNumber: String?
        let subject: String?
        let localSubject: String?
        let chapterType: String?
        let effectiveTime: String?
        let outDate: String?
        let pubDate: String?
        let seriesName: String?
        let generateTime: String?
        let generateTimeEn: String?

        var cacheDocumentID: String {
            AIRACDocumentIdentity.cacheID(
                documentID: documentID, documentType: documentType, category: category)
        }

        var readerID: String { "\(documentType)_\(cacheDocumentID)" }
    }

    let version: String
    let effectiveDate: Date
    let airports: [AirportInfo]
    let charts: [Chart]
}

nonisolated enum LocalAIRACPackageParser {
    static let requiredSections = ["AD", "GEN", "ENR"]
    static let optionalSections = ["SUP", "AIC", "AMDT", "NOTAM"]
    static var allSections: [String] { requiredSections + optionalSections }

    static func parse(folderURL: URL) throws -> ParsedAIRACPackage {
        let dataURL = folderURL.appendingPathComponent("Data")
        let jsonPathURL = dataURL.appendingPathComponent("JsonPath")

        let customers = try Data(contentsOf: dataURL.appendingPathComponent("Customers.js"))
        var indexes: [String: Data] = [:]
        for name in allSections {
            let url = jsonPathURL.appendingPathComponent("\(name).JSON")
            if optionalSections.contains(name), !FileManager.default.fileExists(atPath: url.path) { continue }
            indexes[name] = try Data(contentsOf: url)
        }
        return try parse(customers: customers, indexes: indexes)
    }

    static func metadata(_ data: Data) throws -> (version: String, effectiveDate: Date) {
        guard let raw = String(data: data, encoding: .utf8) else {
            throw AIRACPackageError.invalidPackage("Customers.js 不是有效的 UTF-8 文本")
        }
        let customer = try parseCustomer(raw)
        guard let date = parseEAIPDate(customer.effectiveDate) else {
            throw AIRACPackageError.invalidPackage("Customers.js 的生效时间无效，应为 yyMMddHHmm 格式（UTC）")
        }
        return (customer.dataVersion, date)
    }

    /// 本地包和在线目录使用同一套解析与校验，按需请求允许只传入本页所需的索引。
    static func parse(customers: Data, indexes: [String: Data], requireDocuments: Bool = true) throws -> ParsedAIRACPackage {
        let (version, effectiveDate) = try metadata(customers)
        var pendingCharts: [ParsedAIRACPackage.Chart] = []
        var pendingAirports: [String: (nameEn: String, nameCn: String, isModified: Bool)] = [:]
        if let data = indexes["AD"] { try parseAD(data, charts: &pendingCharts, airports: &pendingAirports) }
        if let data = indexes["GEN"] { try parseGEN(data, charts: &pendingCharts) }
        if let data = indexes["ENR"] { try parseENR(data, charts: &pendingCharts) }
        for section in ["SUP", "AIC"] {
            if let data = indexes[section] { try parseFlatDocuments(data, section: section, charts: &pendingCharts) }
        }
        if let data = indexes["AMDT"] { try parseAmendments(data, charts: &pendingCharts) }
        if let data = indexes["NOTAM"] { try parseNOTAM(data, charts: &pendingCharts) }

        guard !requireDocuments || !pendingCharts.isEmpty else {
            throw AIRACPackageError.invalidPackage("数据包没有可导入的 PDF 文档")
        }
        var documentIDs = Set<String>()
        for chart in pendingCharts {
            try Task.checkCancellation()
            guard !chart.documentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                documentIDs.insert(chart.readerID).inserted
            else {
                throw AIRACPackageError.invalidPackage("文档标识为空或重复：\(chart.readerID)")
            }
            guard let path = chart.pdfPath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIRACPackageError.missingPDF(chart.readerID)
            }
        }

        let airports = pendingAirports.map { icao, info in
            ParsedAIRACPackage.AirportInfo(
                icao: icao, nameEn: info.nameEn, nameCn: info.nameCn, isModified: info.isModified)
        }.sorted { $0.icao < $1.icao }

        return ParsedAIRACPackage(
            version: version,
            effectiveDate: effectiveDate,
            airports: airports,
            charts: pendingCharts
        )
    }

    private static func parseCustomer(_ raw: String) throws -> EAIPCustomer {
        func extract(_ key: String) -> String? {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let pattern = "(?:^|[\\s,{])(?:[\"']?\(escapedKey)[\"']?)\\s*:\\s*([\"'])(.*?)\\1"
            guard let expression = try? NSRegularExpression(pattern: pattern),
                let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                let range = Range(match.range(at: 2), in: raw)
            else { return nil }
            return String(raw[range])
        }

        guard let dataVersion = extract("DataVersion"),
            !dataVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let effectiveDate = extract("EffectiveDate"), !effectiveDate.isEmpty
        else {
            throw NSError(
                domain: "AIRACService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法解析 Customers.js 中的 AIRAC 版本信息"])
        }

        return EAIPCustomer(
            dataName: extract("DataName") ?? dataVersion,
            dataVersion: dataVersion,
            effectiveDate: effectiveDate,
            deadline: extract("Deadline") ?? "",
            publishDate: extract("PublishDate") ?? "")
    }

    private static func parseEAIPDate(_ raw: String) -> Date? {
        guard raw.count == 10, raw.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyMMddHHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.isLenient = false
        formatter.twoDigitStartDate = Date(timeIntervalSince1970: 946_684_800)
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
        return date
    }

    private static func stripBOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.starts(with: bom) {
            return data.dropFirst(bom.count)
        }
        return data
    }

    private static func decodeIndex<T: Decodable>(_ type: T.Type, from raw: Data, name: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: stripBOM(raw))
        } catch let error as DecodingError {
            let context: DecodingError.Context
            let reason: String
            switch error {
            case .keyNotFound(let key, let details):
                context = details
                reason = "缺少字段 \(key.stringValue)"
            case .valueNotFound(_, let details):
                context = details
                reason = "必填字段为空"
            case .typeMismatch(_, let details):
                context = details
                reason = "字段类型不正确"
            case .dataCorrupted(let details):
                context = details
                reason = "JSON 内容无效"
            @unknown default:
                throw AIRACPackageError.invalidPackage("无法解析 \(name)：索引格式无效")
            }
            let location = context.codingPath.map { key in
                key.intValue.map { "第 \($0 + 1) 条" } ?? key.stringValue
            }.joined(separator: ".")
            throw AIRACPackageError.invalidPackage("无法解析 \(name)\(location.isEmpty ? "" : "（\(location)）")：\(reason)")
        }
    }

    private static func loadNodes(_ raw: Data, name: String) throws -> [EAIPTreeNode] {
        let nodes = try decodeIndex([EAIPTreeNode].self, from: raw, name: name)
        try validateNodes(nodes, name: name)
        return nodes
    }

    private static func validateNodes(_ nodes: [EAIPTreeNode], name: String) throws {
        var byID: [String: EAIPTreeNode] = [:]
        for node in nodes {
            try Task.checkCancellation()
            guard !node.id.isEmpty, byID.updateValue(node, forKey: node.id) == nil else {
                throw AIRACPackageError.invalidPackage("\(name) 存在空节点 ID 或重复 ID：\(node.id)")
            }
        }
        // 迭代检查父链，避免循环关系导致无限遍历，深层目录也不会耗尽调用栈。
        var validated = Set<String>()
        for node in nodes where !validated.contains(node.id) {
            try Task.checkCancellation()
            var path = Set<String>()
            var current = node.id
            while let ancestor = byID[current], !validated.contains(current) {
                guard path.insert(current).inserted else {
                    throw AIRACPackageError.invalidPackage("\(name) 存在循环父子关系：\(current)")
                }
                current = ancestor.pId
            }
            validated.formUnion(path)
        }
    }

    private static func parseAD(
        _ raw: Data,
        charts: inout [ParsedAIRACPackage.Chart],
        airports: inout [String: (nameEn: String, nameCn: String, isModified: Bool)]
    ) throws {
        let nodes = try loadNodes(raw, name: "AD.JSON")
        let byParent = Dictionary(grouping: nodes, by: { $0.pId })

        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        // 沿目录树传递所属机场和航图分组，任意深度的 PDF 都必须进入目录。
        typealias Owner = (icao: String, rootID: String)
        var stack: [(node: EAIPTreeNode, owner: Owner?, isChart: Bool)] = nodes
            .filter { byID[$0.pId] == nil }.reversed().map { ($0, nil, false) }
        while let item = stack.popLast() {
            try Task.checkCancellation()
            let node = item.node
            var owner = item.owner
            var isChart = item.isChart
            if let code = node.airporticao, !code.isEmpty, owner?.icao != code {
                owner = (code, node.id)
                isChart = false
                airports[code] = (stripIcaoPrefix(node.name, icao: code),
                    stripIcaoPrefix(node.nameCn, icao: code), node.isModified == "Y")
            }
            if owner != nil,
                node.name.localizedCaseInsensitiveContains("Charts related to an aerodrome")
                    || node.nameCn.contains("机场航图") || node.nameCn.contains("机场有关的航图")
                    || node.nameCn.contains("机场相关航图") {
                isChart = true
            }
            if !node.pdfPath.isEmpty {
                let documentType = owner == nil ? "aip" : isChart ? "chart" : "ad"
                charts.append(treeChart(node, documentType: documentType,
                    chartType: owner == nil ? "AIP" : isChart ? EAIPChartClassifier.classify(name: node.name) : "AD",
                    icao: owner?.icao, parentID: node.id == owner?.rootID ? nil : owner?.rootID,
                    category: owner == nil ? "AD" : nil))
            }
            for child in (byParent[node.id] ?? []).reversed() {
                stack.append((child, owner, isChart))
            }
        }
    }

    private static func treeChart(
        _ node: EAIPTreeNode, documentType: String, chartType: String,
        icao: String? = nil, parentID: String? = nil, category: String? = nil
    ) -> ParsedAIRACPackage.Chart {
        ParsedAIRACPackage.Chart(documentID: node.id, nameEn: node.name, nameCn: node.nameCn,
            chartType: chartType, documentType: documentType, pdfPath: node.pdfPath,
            icao: icao, parentID: parentID, isModified: node.isModified == "Y", category: category,
            serialNumber: nil, subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
            outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil, generateTimeEn: nil)
    }

    private static func stripIcaoPrefix(_ name: String, icao: String) -> String {
        let prefix = "\(icao)-"
        if name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }

    private static func parseGEN(_ raw: Data, charts: inout [ParsedAIRACPackage.Chart]) throws {
        let nodes = try loadNodes(raw, name: "GEN.JSON")
        for node in nodes where !node.pdfPath.isEmpty {
            try Task.checkCancellation()
            charts.append(
                ParsedAIRACPackage.Chart(
                    documentID: node.id, nameEn: node.name,
                    nameCn: node.nameCn, chartType: "AIP", documentType: "aip",
                    pdfPath: node.pdfPath, icao: nil, parentID: nil,
                    isModified: node.isModified == "Y", category: "GEN", serialNumber: nil,
                    subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
                    outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil,
                    generateTimeEn: nil))
        }
    }

    private static func parseENR(_ raw: Data, charts: inout [ParsedAIRACPackage.Chart]) throws {
        let nodes = try loadNodes(raw, name: "ENR.JSON")
        let byParent = Dictionary(grouping: nodes, by: { $0.pId })

        let chartRoots = nodes.filter { $0.name.localizedCaseInsensitiveContains("EN-ROUTE CHARTS") }
        var enrouteIds = Set(chartRoots.map(\.id))
        var stack = chartRoots.map(\.id)
        while let current = stack.popLast() {
            for child in byParent[current] ?? [] {
                guard enrouteIds.insert(child.id).inserted else { continue }
                stack.append(child.id)
            }
        }

        for node in nodes where !node.pdfPath.isEmpty {
            try Task.checkCancellation()
            if enrouteIds.contains(node.id) {
                let enrouteType = EAIPChartClassifier.classifyEnroute(name: node.name, nameCn: node.nameCn)
                charts.append(
                    ParsedAIRACPackage.Chart(
                        documentID: node.id, nameEn: node.name,
                        nameCn: node.nameCn, chartType: enrouteType, documentType: "enroute",
                        pdfPath: node.pdfPath, icao: nil, parentID: nil,
                        isModified: node.isModified == "Y", category: nil, serialNumber: nil,
                        subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
                        outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil,
                        generateTimeEn: nil))
            } else {
                charts.append(
                    ParsedAIRACPackage.Chart(
                        documentID: node.id, nameEn: node.name,
                        nameCn: node.nameCn, chartType: "AIP", documentType: "aip",
                        pdfPath: node.pdfPath, icao: nil, parentID: nil,
                        isModified: node.isModified == "Y", category: "ENR", serialNumber: nil,
                        subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
                        outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil,
                        generateTimeEn: nil))
            }
        }
    }

    private static func parseFlatDocuments(_ raw: Data, section: String, charts: inout [ParsedAIRACPackage.Chart]) throws {
        let docs = try decodeIndex([EAIPFlatDocument].self, from: raw, name: "\(section).JSON")
        try appendFlatDocuments(docs, section: section, charts: &charts)
    }

    private static func parseAmendments(_ raw: Data, charts: inout [ParsedAIRACPackage.Chart]) throws {
        let records = try decodeIndex([EAIPAmendmentRecord].self, from: raw, name: "AMDT.JSON")
        let nodes = records.compactMap { record -> EAIPTreeNode? in
            if case .tree(let node) = record { return node }
            return nil
        }
        try validateNodes(nodes, name: "AMDT.JSON")
        for node in nodes where !node.pdfPath.isEmpty {
            try Task.checkCancellation()
            charts.append(treeChart(node, documentType: "amdt", chartType: "AMDT"))
        }
        let documents = records.compactMap { record -> EAIPFlatDocument? in
            if case .flat(let document) = record { return document }
            return nil
        }
        try appendFlatDocuments(documents, section: "AMDT", charts: &charts)
    }

    private static func appendFlatDocuments(
        _ docs: [EAIPFlatDocument], section: String, charts: inout [ParsedAIRACPackage.Chart]
    ) throws {
        for doc in docs {
            try Task.checkCancellation()
            charts.append(
                ParsedAIRACPackage.Chart(
                    documentID: doc.id,
                    nameEn: doc.subject ?? doc.localSubject ?? doc.serial ?? section,
                    nameCn: doc.localSubject ?? doc.subject ?? doc.serial ?? section,
                    chartType: section, documentType: section.lowercased(), pdfPath: doc.document,
                    icao: nil, parentID: nil, isModified: doc.isModified == "Y", category: nil,
                    serialNumber: doc.serial, subject: doc.subject, localSubject: doc.localSubject,
                    chapterType: doc.chapterType, effectiveTime: doc.effectiveTime,
                    outDate: doc.outDate, pubDate: doc.pubDate, seriesName: nil,
                    generateTime: nil, generateTimeEn: nil))
        }
    }

    private static func parseNOTAM(_ raw: Data, charts: inout [ParsedAIRACPackage.Chart]) throws {
        let docs = try decodeIndex([EAIPNotamDocument].self, from: raw, name: "NOTAM.JSON")
        for doc in docs {
            try Task.checkCancellation()
            let stableID = "\(doc.seriesName)_\(doc.generateTime)"
            charts.append(
                ParsedAIRACPackage.Chart(
                    documentID: stableID,
                    nameEn: "NOTAM \(doc.seriesName)", nameCn: "NOTAM \(doc.seriesName)",
                    chartType: "NOTAM", documentType: "notam", pdfPath: doc.document,
                    icao: nil, parentID: nil, isModified: false, category: nil,
                    serialNumber: nil, subject: nil, localSubject: nil, chapterType: nil,
                    effectiveTime: nil, outDate: nil, pubDate: nil, seriesName: doc.seriesName,
                    generateTime: doc.generateTime, generateTimeEn: doc.generateTimeEn))
        }
    }
}
