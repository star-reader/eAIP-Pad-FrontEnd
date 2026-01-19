import Foundation

// MARK: - AIRAC 版本响应
struct AIRACResponse: Codable {
    let version: String
    let effectiveDate: String
    let isCurrent: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case version
        case effectiveDate = "effective_date"
        case isCurrent = "is_current"
        case createdAt = "created_at"
    }
}
