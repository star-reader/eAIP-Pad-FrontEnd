import Foundation

// MARK: - 航图响应
struct ChartResponse: Codable, Hashable, Identifiable {
    let id: String
    let documentId: String
    let parentId: String?
    let icao: String?
    let nameEn: String
    let nameCn: String
    let chartType: String
    let pdfPath: String?
    let htmlPath: String?
    let htmlEnPath: String?
    let airacVersion: String
    let isModified: Bool
    let isOpened: Bool?
    // 文档来源决定缓存路径；chartType 仅用于列表分类，OTHERS 也可能是航路图。
    var documentType: DocumentType? = nil

    var readerDocumentType: DocumentType {
        if let documentType { return documentType }

        // 兼容没有来源字段的旧数据。新导入数据始终保留 documentType。
        switch chartType {
        case "AD": return .ad
        case "AIP": return .aip
        case "ENROUTE", "AREA": return .enroute
        case "SUP": return .sup
        case "AIC": return .aic
        case "AMDT": return .amdt
        case "NOTAM": return .notam
        default: return .chart
        }
    }

    var readerChartID: String {
        "\(readerDocumentType.rawValue)_\(id)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case parentId = "parent_id"
        case icao
        case nameEn = "name_en"
        case nameCn = "name_cn"
        case chartType = "chart_type"
        case pdfPath = "pdf_path"
        case htmlPath = "html_path"
        case htmlEnPath = "html_en_path"
        case airacVersion = "airac_version"
        case isModified = "is_modified"
        case isOpened = "is_opened"
        case documentType = "document_type"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(readerChartID)
        hasher.combine(airacVersion)
    }

    static func == (lhs: ChartResponse, rhs: ChartResponse) -> Bool {
        return lhs.readerChartID == rhs.readerChartID && lhs.airacVersion == rhs.airacVersion
    }
}
