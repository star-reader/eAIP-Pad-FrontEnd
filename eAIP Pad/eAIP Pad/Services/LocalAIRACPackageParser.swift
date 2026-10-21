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
    static func parse(folderURL: URL) throws -> ParsedAIRACPackage {
        let dataURL = folderURL.appendingPathComponent("Data")
        let jsonPathURL = dataURL.appendingPathComponent("JsonPath")

        let customersURL = dataURL.appendingPathComponent("Customers.js")
        let customersRaw = try String(contentsOf: customersURL, encoding: .utf8)
        let customer = try parseCustomer(customersRaw)
        let version = customer.dataVersion
        guard let effectiveDate = parseEAIPDate(customer.effectiveDate) else {
            throw AIRACPackageError.invalidPackage("Customers.js 的生效时间无效，应为 yyMMddHHmm 格式（UTC）")
        }

        var pendingCharts: [ParsedAIRACPackage.Chart] = []
        var pendingAirports: [String: (nameEn: String, nameCn: String, isModified: Bool)] = [:]

        try parseAD(
            jsonPathURL.appendingPathComponent("AD.JSON"),
            charts: &pendingCharts,
            airports: &pendingAirports
        )
        try parseGEN(jsonPathURL.appendingPathComponent("GEN.JSON"), charts: &pendingCharts)
        try parseENR(jsonPathURL.appendingPathComponent("ENR.JSON"), charts: &pendingCharts)
        try parseSUP(jsonPathURL.appendingPathComponent("SUP.JSON"), charts: &pendingCharts)
        try parseNOTAM(jsonPathURL.appendingPathComponent("NOTAM.JSON"), charts: &pendingCharts)

        guard !pendingCharts.isEmpty else {
            throw AIRACPackageError.invalidPackage("数据包没有可导入的 PDF 文档")
        }
        var documentIDs = Set<String>()
        for chart in pendingCharts {
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

    private static func loadNodes(_ url: URL) throws -> [EAIPTreeNode] {
        let data = stripBOM(try Data(contentsOf: url))
        let nodes = try JSONDecoder().decode([EAIPTreeNode].self, from: data)
        var byID: [String: EAIPTreeNode] = [:]
        for node in nodes {
            guard !node.id.isEmpty, byID.updateValue(node, forKey: node.id) == nil else {
                throw AIRACPackageError.invalidPackage("\(url.lastPathComponent) 存在空节点 ID 或重复 ID：\(node.id)")
            }
        }
        // 迭代检查父链，避免循环关系导致无限遍历，深层目录也不会耗尽调用栈。
        var validated = Set<String>()
        for node in nodes where !validated.contains(node.id) {
            var path = Set<String>()
            var current = node.id
            while let ancestor = byID[current], !validated.contains(current) {
                guard path.insert(current).inserted else {
                    throw AIRACPackageError.invalidPackage("\(url.lastPathComponent) 存在循环父子关系：\(current)")
                }
                current = ancestor.pId
            }
            validated.formUnion(path)
        }
        return nodes
    }

    private static func parseAD(
        _ url: URL,
        charts: inout [ParsedAIRACPackage.Chart],
        airports: inout [String: (nameEn: String, nameCn: String, isModified: Bool)]
    ) throws {
        let nodes = try loadNodes(url)
        let byParent = Dictionary(grouping: nodes, by: { $0.pId })

        let airportRoots = nodes.filter { ($0.airporticao?.isEmpty == false) }
        for root in airportRoots {
            guard let icao = root.airporticao else { continue }

            let nameEn = stripIcaoPrefix(root.name, icao: icao)
            let nameCn = stripIcaoPrefix(root.nameCn, icao: icao)
            airports[icao] = (nameEn: nameEn, nameCn: nameCn, isModified: root.isModified == "Y")

            if !root.pdfPath.isEmpty {
                charts.append(
                    ParsedAIRACPackage.Chart(
                        documentID: root.id, nameEn: root.name,
                        nameCn: root.nameCn, chartType: "AD", documentType: "ad",
                        pdfPath: root.pdfPath, icao: icao, parentID: nil,
                        isModified: root.isModified == "Y", category: nil, serialNumber: nil,
                        subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
                        outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil,
                        generateTimeEn: nil))
            }

            let children = byParent[root.id] ?? []
            guard
                let chartSection = children.first(where: {
                    $0.name.localizedCaseInsensitiveContains("Charts related to an aerodrome")
                })
            else { continue }

            let chartLeaves = byParent[chartSection.id] ?? []
            for leaf in chartLeaves where !leaf.pdfPath.isEmpty {
                charts.append(
                    ParsedAIRACPackage.Chart(
                        documentID: leaf.id, nameEn: leaf.name,
                        nameCn: leaf.nameCn, chartType: EAIPChartClassifier.classify(name: leaf.name),
                        documentType: "chart", pdfPath: leaf.pdfPath, icao: icao, parentID: root.id,
                        isModified: leaf.isModified == "Y", category: nil, serialNumber: nil,
                        subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
                        outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil,
                        generateTimeEn: nil))
            }
        }
    }

    private static func stripIcaoPrefix(_ name: String, icao: String) -> String {
        let prefix = "\(icao)-"
        if name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }

    private static func parseGEN(_ url: URL, charts: inout [ParsedAIRACPackage.Chart]) throws {
        let nodes = try loadNodes(url)
        for node in nodes where !node.pdfPath.isEmpty {
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

    private static func parseENR(_ url: URL, charts: inout [ParsedAIRACPackage.Chart]) throws {
        let nodes = try loadNodes(url)
        let byParent = Dictionary(grouping: nodes, by: { $0.pId })

        guard
            let enrChartsRoot = nodes.first(where: {
                $0.name.localizedCaseInsensitiveContains("EN-ROUTE CHARTS")
            })
        else {
            for node in nodes where !node.pdfPath.isEmpty {
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
            return
        }

        var enrouteIds = Set<String>()
        var stack = [enrChartsRoot.id]
        while let current = stack.popLast() {
            for child in byParent[current] ?? [] {
                guard enrouteIds.insert(child.id).inserted else { continue }
                stack.append(child.id)
            }
        }

        for node in nodes where !node.pdfPath.isEmpty {
            if enrouteIds.contains(node.id) {
                let enrouteType = EAIPChartClassifier.classifyEnroute(name: node.name)
                charts.append(
                    ParsedAIRACPackage.Chart(
                        documentID: node.id, nameEn: node.name,
                        nameCn: node.nameCn, chartType: enrouteType, documentType: "enroute",
                        pdfPath: node.pdfPath, icao: nil, parentID: nil,
                        isModified: node.isModified == "Y", category: nil, serialNumber: nil,
                        subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
                        outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil,
                        generateTimeEn: nil))
            } else if node.id != enrChartsRoot.id {
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

    private static func parseSUP(_ url: URL, charts: inout [ParsedAIRACPackage.Chart]) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = stripBOM(try Data(contentsOf: url))
        let docs = try JSONDecoder().decode([EAIPFlatDocument].self, from: data)
        for doc in docs {
            charts.append(
                ParsedAIRACPackage.Chart(
                    documentID: doc.id,
                    nameEn: doc.subject ?? "", nameCn: doc.localSubject ?? "",
                    chartType: "SUP", documentType: "sup", pdfPath: doc.document,
                    icao: nil, parentID: nil, isModified: doc.isModified == "Y", category: nil,
                    serialNumber: doc.serial, subject: doc.subject, localSubject: doc.localSubject,
                    chapterType: doc.chapterType, effectiveTime: doc.effectiveTime,
                    outDate: doc.outDate, pubDate: doc.pubDate, seriesName: nil,
                    generateTime: nil, generateTimeEn: nil))
        }
    }

    private static func parseNOTAM(_ url: URL, charts: inout [ParsedAIRACPackage.Chart]) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = stripBOM(try Data(contentsOf: url))
        let docs = try JSONDecoder().decode([EAIPNotamDocument].self, from: data)
        for doc in docs {
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
