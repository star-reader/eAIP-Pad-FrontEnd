import Foundation

// MARK: - AIP 文档响应
struct AIPDocumentResponse: Codable {
    let id: Int
    let documentId: String
    let parentId: String?
    let name: String
    let nameCn: String
    let category: String
    let airportIcao: String?
    let pdfPath: String?
    let htmlPath: String?
    let htmlEnPath: String?
    let airacVersion: String
    let isModified: Bool?
    let hasUpdate: Bool?
    let isOpened: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case parentId = "parent_id"
        case name
        case nameCn = "name_cn"
        case category
        case airportIcao = "airport_icao"
        case pdfPath = "pdf_path"
        case htmlPath = "html_path"
        case htmlEnPath = "html_en_path"
        case airacVersion = "airac_version"
        case isModified = "is_modified"
        case hasUpdate = "has_update"
        case isOpened = "is_opened"
    }
}

// MARK: - SUP 文档响应
struct SUPDocumentResponse: Codable {
    let id: Int
    let documentId: String
    let serial: String
    let subject: String
    let localSubject: String
    let chapterType: String
    let pdfPath: String?
    let effectiveTime: String?
    let outDate: String?
    let pubDate: String?
    let airacVersion: String
    let isModified: Bool?
    let hasUpdate: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case serial
        case subject
        case localSubject = "local_subject"
        case chapterType = "chapter_type"
        case pdfPath = "pdf_path"
        case effectiveTime = "effective_time"
        case outDate = "out_date"
        case pubDate = "pub_date"
        case airacVersion = "airac_version"
        case isModified = "is_modified"
        case hasUpdate = "has_update"
    }
}

// MARK: - AMDT 文档响应
struct AMDTDocumentResponse: Codable {
    let id: Int
    let documentId: String
    let serial: String
    let subject: String
    let localSubject: String
    let chapterType: String
    let pdfPath: String?
    let effectiveTime: String?
    let outDate: String?
    let pubDate: String?
    let airacVersion: String
    let isModified: Bool?
    let hasUpdate: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case serial
        case subject
        case localSubject = "local_subject"
        case chapterType = "chapter_type"
        case pdfPath = "pdf_path"
        case effectiveTime = "effective_time"
        case outDate = "out_date"
        case pubDate = "pub_date"
        case airacVersion = "airac_version"
        case isModified = "is_modified"
        case hasUpdate = "has_update"
    }
}

// MARK: - NOTAM 文档响应
struct NOTAMDocumentResponse: Codable {
    let id: Int
    let documentId: String
    let seriesName: String
    let pdfPath: String?
    let generateTime: String
    let generateTimeEn: String
    let airacVersion: String

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case seriesName = "series_name"
        case pdfPath = "pdf_path"
        case generateTime = "generate_time"
        case generateTimeEn = "generate_time_en"
        case airacVersion = "airac_version"
    }
}

// MARK: - 通用文档详情响应
struct DocumentDetailResponse: Codable {
    let id: Int
    let documentId: String
    let name: String
    let nameCn: String
    let type: String
    let airacVersion: String
    let isModified: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case name
        case nameCn = "name_cn"
        case type
        case airacVersion = "airac_version"
        case isModified = "is_modified"
    }
}
