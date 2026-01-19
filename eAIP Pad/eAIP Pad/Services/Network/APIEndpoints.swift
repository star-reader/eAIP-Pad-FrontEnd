import Foundation

// MARK: - 网络配置
struct NetworkConfig {
    static let environment = AppEnvironment.current
    
    static var baseURL: String {
        return environment.baseURL
    }
    
    static let apiVersion = "/eaip/v1"

    static var baseAPIURL: String {
        return baseURL + apiVersion
    }
    
    static var requestTimeout: TimeInterval {
        return environment.requestTimeout
    }
    
    #if DEBUG
    static let maxRetryCount: Int = 3
    #else
    static let maxRetryCount: Int = 3
    #endif
    
    static func retryDelay(for attempt: Int) -> TimeInterval {
        return environment.retryDelay(for: attempt)
    }
}

// MARK: - HTTP 方法
enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

// MARK: - API 端点
enum APIEndpoint {
    // 认证
    case appleLogin
    case refreshToken
    
    // 机场
    case airports
    case airport(icao: String)
    case airportCharts(icao: String)
    
    // 航图
    case chart(id: Int)
    case chartSignedURL(id: Int)
    case chartInfo(id: Int)
    
    // 航路图
    case enrouteCharts
    case enrouteChart(id: Int)
    case enrouteSignedURL(id: Int)
    
    // AIP 文档
    case aipDocuments
    case aipDocumentsByICAO(icao: String)
    
    // SUP/AMDT/NOTAM
    case supDocuments
    case amdtDocuments
    case notamDocuments
    
    // 通用文档
    case document(type: String, id: Int)
    case documentSignedURL(type: String, id: Int)
    
    // Pinboard
    case pinboard
    case addPin
    case removePin(type: String, id: Int)
    
    // 标注
    case annotations(type: String, id: Int)
    case saveAnnotation(type: String, id: Int)
    case deleteAnnotation(type: String, id: Int, page: Int)
    
    // AIRAC
    case currentAIRAC
    
    // IAP v2
    case iapVerify
    case iapSync
    case iapStatus
    
    // 天气
    case weatherMETAR(icao: String)
    case weatherTAF(icao: String)

    var path: String {
        switch self {
        case .appleLogin:
            return "/auth/apple"
        case .refreshToken:
            return "/auth/refresh"
        case .airports:
            return "/airports"
        case .airport(let icao):
            return "/airports/\(icao)"
        case .airportCharts(let icao):
            return "/airports/\(icao)/charts"
        case .chart(let id):
            return "/charts/\(id)"
        case .chartSignedURL(let id):
            return "/charts/\(id)/signed-url"
        case .chartInfo(let id):
            return "/charts/\(id)/info"
        case .enrouteCharts:
            return "/enroute"
        case .enrouteChart(let id):
            return "/enroute/\(id)"
        case .enrouteSignedURL(let id):
            return "/enroute/\(id)/signed-url"
        case .aipDocuments:
            return "/documents/aip"
        case .aipDocumentsByICAO(let icao):
            return "/documents/aip/ad/\(icao)"
        case .supDocuments:
            return "/documents/sup"
        case .amdtDocuments:
            return "/documents/amdt"
        case .notamDocuments:
            return "/documents/notam"
        case .document(let type, let id):
            return "/documents/\(type)/\(id)"
        case .documentSignedURL(let type, let id):
            return "/documents/\(type)/\(id)/signed-url"
        case .pinboard:
            return "/pinboard"
        case .addPin:
            return "/pinboard"
        case .removePin(let type, let id):
            return "/pinboard/\(type)/\(id)"
        case .annotations(let type, let id):
            return "/annotations/\(type)/\(id)"
        case .saveAnnotation(let type, let id):
            return "/annotations/\(type)/\(id)"
        case .deleteAnnotation(let type, let id, let page):
            return "/annotations/\(type)/\(id)/\(page)"
        case .currentAIRAC:
            return "/airac/current"
        case .iapVerify:
            return "/iap/v2/verify"
        case .iapSync:
            return "/iap/v2/sync"
        case .iapStatus:
            return "/iap/v2/status"
        case .weatherMETAR(let icao):
            return "/weather/metar/\(icao)"
        case .weatherTAF(let icao):
            return "/weather/taf/\(icao)"
        }
    }

    var url: URL {
        return URL(string: NetworkConfig.baseAPIURL + path)!
    }
}
