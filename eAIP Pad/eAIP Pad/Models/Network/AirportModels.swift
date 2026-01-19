import Foundation

// MARK: - 机场响应
struct AirportResponse: Codable, Hashable, Identifiable {
    let icao: String
    let nameEn: String
    let nameCn: String
    let hasTerminalCharts: Bool
    let createdAt: String
    let isModified: Bool?

    var id: String { icao }

    enum CodingKeys: String, CodingKey {
        case icao
        case nameEn = "name_en"
        case nameCn = "name_cn"
        case hasTerminalCharts = "has_terminal_charts"
        case createdAt = "created_at"
        case isModified = "is_modified"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(icao)
    }

    static func == (lhs: AirportResponse, rhs: AirportResponse) -> Bool {
        return lhs.icao == rhs.icao
    }
}
