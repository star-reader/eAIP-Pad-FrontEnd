import Foundation

struct ParsedAIRACPackage: Sendable {
    struct AirportInfo: Sendable {
        let icao: String
        let nameEn: String
        let nameCn: String
    }

    struct Chart: Sendable {
        let chartID: String
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
    }

    let version: String
    let effectiveDate: Date
    let airports: [AirportInfo]
    let charts: [Chart]
}

enum LocalAIRACPackageParser {
    static func parse(folderURL: URL) throws -> ParsedAIRACPackage {
        let dataURL = folderURL.appendingPathComponent("Data")
        let jsonPathURL = dataURL.appendingPathComponent("JsonPath")

        let customersURL = dataURL.appendingPathComponent("Customers.js")
        let customersRaw = try String(contentsOf: customersURL, encoding: .utf8)
        let customer = try parseCustomer(customersRaw)
        let version = customer.dataVersion
        let effectiveDate = parseEAIPDate(customer.effectiveDate) ?? Date()

        _ = try findPackageRoot(under: dataURL)

        var pendingCharts: [ParsedAIRACPackage.Chart] = []
        var pendingAirports: [String: (nameEn: String, nameCn: String)] = [:]

        try parseAD(
            jsonPathURL.appendingPathComponent("AD.JSON"),
            charts: &pendingCharts,
            airports: &pendingAirports
        )
        try parseGEN(jsonPathURL.appendingPathComponent("GEN.JSON"), charts: &pendingCharts)
        try parseENR(jsonPathURL.appendingPathComponent("ENR.JSON"), charts: &pendingCharts)
        try parseSUP(jsonPathURL.appendingPathComponent("SUP.JSON"), charts: &pendingCharts)
        try parseNOTAM(jsonPathURL.appendingPathComponent("NOTAM.JSON"), charts: &pendingCharts)

        let airports = pendingAirports.map { icao, info in
            ParsedAIRACPackage.AirportInfo(icao: icao, nameEn: info.nameEn, nameCn: info.nameCn)
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
            guard let keyRange = raw.range(of: "\(key):\"") else { return nil }
            let afterKey = raw[keyRange.upperBound...]
            guard let endQuote = afterKey.firstIndex(of: "\"") else { return nil }
            return String(afterKey[..<endQuote])
        }

        guard let dataVersion = extract("DataVersion"), !dataVersion.isEmpty,
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
        guard raw.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }

    private static func findPackageRoot(under dataURL: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: dataURL, includingPropertiesForKeys: [.isDirectoryKey])
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir && url.lastPathComponent != "JsonPath" {
                return url
            }
        }
        throw NSError(
            domain: "AIRACService", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "未找到航图数据目录"])
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
        return try JSONDecoder().decode([EAIPTreeNode].self, from: data)
    }

    private static func parseAD(
        _ url: URL,
        charts: inout [ParsedAIRACPackage.Chart],
        airports: inout [String: (nameEn: String, nameCn: String)]
    ) throws {
        let nodes = try loadNodes(url)
        let byParent = Dictionary(grouping: nodes, by: { $0.pId })

        let airportRoots = nodes.filter { ($0.airporticao?.isEmpty == false) }
        for root in airportRoots {
            guard let icao = root.airporticao else { continue }

            let nameEn = stripIcaoPrefix(root.name, icao: icao)
            let nameCn = stripIcaoPrefix(root.nameCn, icao: icao)
            airports[icao] = (nameEn: nameEn, nameCn: nameCn)

            charts.append(
                ParsedAIRACPackage.Chart(
                    chartID: "ad_\(root.id)", documentID: root.id, nameEn: root.name,
                    nameCn: root.nameCn, chartType: "AD", documentType: "ad",
                    pdfPath: root.pdfPath, icao: icao, parentID: nil,
                    isModified: root.isModified == "Y", category: nil, serialNumber: nil,
                    subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
                    outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil,
                    generateTimeEn: nil))

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
                        chartID: "chart_\(leaf.id)", documentID: leaf.id, nameEn: leaf.name,
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
                    chartID: "aip_\(node.id)", documentID: node.id, nameEn: node.name,
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
                        chartID: "aip_\(node.id)", documentID: node.id, nameEn: node.name,
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
                enrouteIds.insert(child.id)
                stack.append(child.id)
            }
        }

        for node in nodes where !node.pdfPath.isEmpty {
            if enrouteIds.contains(node.id) {
                let enrouteType = EAIPChartClassifier.classifyEnroute(name: node.name)
                charts.append(
                    ParsedAIRACPackage.Chart(
                        chartID: "enroute_\(node.id)", documentID: node.id, nameEn: node.name,
                        nameCn: node.nameCn, chartType: enrouteType, documentType: "enroute",
                        pdfPath: node.pdfPath, icao: nil, parentID: nil,
                        isModified: node.isModified == "Y", category: nil, serialNumber: nil,
                        subject: nil, localSubject: nil, chapterType: nil, effectiveTime: nil,
                        outDate: nil, pubDate: nil, seriesName: nil, generateTime: nil,
                        generateTimeEn: nil))
            } else if node.id != enrChartsRoot.id {
                charts.append(
                    ParsedAIRACPackage.Chart(
                        chartID: "aip_\(node.id)", documentID: node.id, nameEn: node.name,
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
                    chartID: "sup_\(doc.id)", documentID: doc.id,
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
                    chartID: "notam_\(stableID)", documentID: stableID,
                    nameEn: "NOTAM \(doc.seriesName)", nameCn: "NOTAM \(doc.seriesName)",
                    chartType: "NOTAM", documentType: "notam", pdfPath: doc.document,
                    icao: nil, parentID: nil, isModified: false, category: nil,
                    serialNumber: nil, subject: nil, localSubject: nil, chapterType: nil,
                    effectiveTime: nil, outDate: nil, pubDate: nil, seriesName: doc.seriesName,
                    generateTime: doc.generateTime, generateTimeEn: doc.generateTimeEn))
        }
    }
}
