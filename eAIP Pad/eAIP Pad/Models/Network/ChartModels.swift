import Foundation

// MARK: - 航图响应
struct ChartResponse: Codable, Hashable, Identifiable {
    let id: Int
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
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChartResponse, rhs: ChartResponse) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - 签名 URL 响应
struct SignedURLResponse: Codable {
    let url: String
    let expiresIn: Int
    let expire: Int64

    enum CodingKeys: String, CodingKey {
        case url
        case expiresIn = "expires_in"
        case expire
    }
}
