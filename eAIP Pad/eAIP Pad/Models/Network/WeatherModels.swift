import Foundation

// MARK: - METAR 响应
struct METARResponse: Codable {
    let station: String?
    let observationTime: String?
    let windDirection: String?
    let windSpeed: String?
    let visibility: String?
    let temperature: String?
    let dewpoint: String?
    let qnh: String?
    let weather: String?
    let clouds: [String]?
    let trend: String?
    let raw: String?

    enum CodingKeys: String, CodingKey {
        case station
        case observationTime = "observation_time"
        case windDirection = "wind_direction"
        case windSpeed = "wind_speed"
        case visibility
        case temperature
        case dewpoint
        case qnh
        case weather
        case clouds
        case trend
        case raw
    }
}

// MARK: - TAF 响应
struct TAFResponse: Codable {
    let station: String?
    let issueTime: String?
    let validFrom: String?
    let validTo: String?
    let forecasts: [TAFPeriod]?
    let raw: String?

    enum CodingKeys: String, CodingKey {
        case station
        case issueTime = "issue_time"
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case forecasts
        case raw
    }
}

// MARK: - TAF 时段
struct TAFPeriod: Codable, Hashable, Identifiable {
    var id: String { (timeFrom ?? "") + "_" + (timeTo ?? UUID().uuidString) }
    let timeFrom: String?
    let timeTo: String?
    let wind: String?
    let visibility: String?
    let weather: String?
    let clouds: [String]?

    enum CodingKeys: String, CodingKey {
        case timeFrom = "time_from"
        case timeTo = "time_to"
        case wind
        case visibility
        case weather
        case clouds
    }
}
