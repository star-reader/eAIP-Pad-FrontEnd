import Combine
import Foundation
import SwiftUI

// MARK: - 网络配置
struct NetworkConfig {
    static let baseURL = "https://api.usagi-jin.top"
    static let apiVersion = "/eaip/v1"

    static var baseAPIURL: String {
        return baseURL + apiVersion
    }
}

// MARK: - API 端点
enum APIEndpoint {
    case appleLogin
    case refreshToken
    case airports
    case airport(icao: String)
    case airportCharts(icao: String)
    case chart(id: Int)
    case chartSignedURL(id: Int)
    case chartInfo(id: Int)
    case enrouteCharts
    case enrouteChart(id: Int)
    case enrouteSignedURL(id: Int)
    case aipDocuments
    case aipDocumentsByICAO(icao: String)
    case supDocuments
    case amdtDocuments
    case notamDocuments
    case document(type: String, id: Int)
    case documentSignedURL(type: String, id: Int)
    case pinboard
    case addPin
    case removePin(type: String, id: Int)
    case annotations(type: String, id: Int)
    case saveAnnotation(type: String, id: Int)
    case deleteAnnotation(type: String, id: Int, page: Int)
    case currentAIRAC
    // IAP v2 API
    case iapVerify
    case iapSync
    case iapStatus
    // Weather
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

// MARK: - 网络响应模型
struct APIResponse<T: Codable>: Codable {
    let message: String
    let data: T?
}

// MARK: - 认证响应
struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let isNewUser: Bool

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case isNewUser = "is_new_user"
    }
}

// MARK: - 机场响应
struct AirportResponse: Codable, Hashable, Identifiable {
    let icao: String
    let nameEn: String
    let nameCn: String
    let hasTerminalCharts: Bool
    let createdAt: String
    let isModified: Bool?

    var id: String { icao }  // 使用 ICAO 作为唯一标识

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
    let isOpened: Bool?  // 改为可选，因为API可能不返回此字段

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

// MARK: - 签名URL响应
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

// MARK: - AIRAC版本响应
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

// MARK: - AIP文档响应
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

// MARK: - SUP文档响应
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

// MARK: - AMDT文档响应
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

// MARK: - NOTAM文档响应
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

// MARK: - 天气响应
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

// MARK: - IAP 请求模型
struct VerifyJWSRequest: Codable {
    let transactionJWS: String
    let appleUserId: String
    let environment: String?

    enum CodingKeys: String, CodingKey {
        case transactionJWS = "transaction_jws"
        case appleUserId = "apple_user_id"
        case environment
    }
}

struct SyncSubscriptionRequest: Codable {
    let transactionJWSList: [String]
    let appleUserId: String
    let environment: String?

    enum CodingKeys: String, CodingKey {
        case transactionJWSList = "transaction_jws_list"
        case appleUserId = "apple_user_id"
        case environment
    }
}

// MARK: - IAP 响应模型
struct VerifyJWSResponse: Codable {
    let status: String
    let subscriptionStatus: String?
    let subscriptionStartDate: String?
    let subscriptionEndDate: String?
    let trialStartDate: String?
    let autoRenew: Bool?
    let productId: String?
    let originalTransactionId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case subscriptionStatus = "subscription_status"
        case subscriptionStartDate = "subscription_start_date"
        case subscriptionEndDate = "subscription_end_date"
        case trialStartDate = "trial_start_date"
        case autoRenew = "auto_renew"
        case productId = "product_id"
        case originalTransactionId = "original_transaction_id"
        case message
    }
}

struct SyncSubscriptionResponse: Codable {
    let status: String
    let subscriptionStatus: String?
    let subscriptionStartDate: String?
    let subscriptionEndDate: String?
    let trialStartDate: String?
    let autoRenew: Bool?
    let productId: String?
    let syncedCount: Int?
    let totalCount: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case subscriptionStatus = "subscription_status"
        case subscriptionStartDate = "subscription_start_date"
        case subscriptionEndDate = "subscription_end_date"
        case trialStartDate = "trial_start_date"
        case autoRenew = "auto_renew"
        case productId = "product_id"
        case syncedCount = "synced_count"
        case totalCount = "total_count"
        case message
    }
}

struct SubscriptionStatusResponse: Codable {
    let status: String
    let subscriptionStartDate: String?
    let subscriptionEndDate: String?
    let trialStartDate: String?
    let autoRenew: Bool?
    let productId: String?
    let originalTransactionId: String?
    let environment: String?
    let daysLeft: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case subscriptionStartDate = "subscription_start_date"
        case subscriptionEndDate = "subscription_end_date"
        case trialStartDate = "trial_start_date"
        case autoRenew = "auto_renew"
        case productId = "product_id"
        case originalTransactionId = "original_transaction_id"
        case environment
        case daysLeft = "days_left"
    }
}

// MARK: - 网络服务
class NetworkService: ObservableObject {
    static let shared = NetworkService()

    private var accessToken: String?
    private var refreshToken: String?

    private init() {
        LoggerService.shared.info(module: "NetworkService", message: "网络服务初始化")
    }

    // MARK: - 认证相关
    func setTokens(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        // 避免将空字符串当作有效 refresh token 存入
        self.refreshToken = refreshToken.isEmpty ? nil : refreshToken
        // 加密记录 token（敏感信息）
        LoggerService.shared.info(
            module: "NetworkService", message: "设置 Access Token: \(accessToken)")
        if !refreshToken.isEmpty {
            LoggerService.shared.info(
                module: "NetworkService", message: "设置 Refresh Token: \(refreshToken)")
        }
    }

    func clearTokens() {
        LoggerService.shared.info(module: "NetworkService", message: "清除 Tokens")
        self.accessToken = nil
        self.refreshToken = nil
    }

    func getCurrentAccessToken() -> String? {
        return accessToken
    }

    func getCurrentRefreshToken() -> String? {
        return refreshToken
    }

    // MARK: - 通用请求方法
    private func makeRequest<T: Codable>(
        endpoint: APIEndpoint,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 添加认证头
        if requiresAuth, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 添加请求体
        if let body = body {
            request.httpBody = body
        }

        // 记录请求日志
        logRequest(request: request, body: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logResponse(response: nil, data: data, error: NetworkError.invalidResponse)
            throw NetworkError.invalidResponse
        }

        // 处理401错误，尝试刷新token
        if httpResponse.statusCode == 401 && requiresAuth {
            logResponse(response: httpResponse, data: data, error: nil)

            // 若无 refresh token，直接返回未授权，避免抛出“没有刷新令牌”误导性错误
            guard let currentRefreshToken = self.refreshToken, !currentRefreshToken.isEmpty else {
                throw NetworkError.unauthorized
            }

            try await refreshAccessToken()
            // 重新设置认证头并重试
            request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                retryHttpResponse.statusCode == 200
            else {
                logResponse(
                    response: retryResponse as? HTTPURLResponse, data: retryData,
                    error: NetworkError.unauthorized)
                throw NetworkError.unauthorized
            }
            logResponse(response: retryHttpResponse, data: retryData, error: nil)
            return try JSONDecoder().decode(APIResponse<T>.self, from: retryData).data!
        }

        guard httpResponse.statusCode == 200 else {
            let error = NetworkError.serverError(httpResponse.statusCode)
            logResponse(response: httpResponse, data: data, error: error)
            throw error
        }

        // 记录成功响应
        logResponse(response: httpResponse, data: data, error: nil)

        let apiResponse = try JSONDecoder().decode(APIResponse<T>.self, from: data)
        guard let responseData = apiResponse.data else {
            throw NetworkError.noData
        }

        return responseData
    }

    // MARK: - 认证方法
    func appleLogin(idToken: String) async throws -> AuthResponse {
        LoggerService.shared.info(module: "NetworkService", message: "开始 Apple 登录")
        // 加密记录 idToken（敏感信息）
        LoggerService.shared.info(module: "NetworkService", message: "ID Token: \(idToken)")

        let body = ["id_token": idToken]
        let bodyData = try JSONEncoder().encode(body)

        let response: AuthResponse = try await makeRequest(
            endpoint: .appleLogin,
            method: .POST,
            body: bodyData,
            requiresAuth: false
        )
        LoggerService.shared.info(module: "NetworkService", message: "Apple 登录成功")
        return response
    }

    func refreshAccessToken() async throws {
        LoggerService.shared.info(module: "NetworkService", message: "开始刷新 Access Token")
        guard let refreshToken = refreshToken, !refreshToken.isEmpty else {
            LoggerService.shared.error(module: "NetworkService", message: "刷新失败：缺少 Refresh Token")
            throw NetworkError.noRefreshToken
        }

        // 加密记录 refreshToken
        LoggerService.shared.info(
            module: "NetworkService", message: "使用 Refresh Token: \(refreshToken)")

        let body = ["refresh_token": refreshToken]
        let bodyData = try JSONEncoder().encode(body)

        let response: AuthResponse = try await makeRequest(
            endpoint: .refreshToken,
            method: .POST,
            body: bodyData,
            requiresAuth: false
        )

        setTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
        LoggerService.shared.info(module: "NetworkService", message: "Access Token 刷新成功")
    }

    // MARK: - 机场相关
    func getAirports(search: String? = nil) async throws -> [AirportResponse] {
        let endpoint = APIEndpoint.airports
        // 注意：这里简化处理，实际应该构造带参数的URL
        let response: [AirportResponse] = try await makeRequest(endpoint: endpoint)
        return response
    }

    func getAirport(icao: String) async throws -> AirportResponse {
        let response: AirportResponse = try await makeRequest(endpoint: .airport(icao: icao))
        return response
    }

    func getAirportCharts(icao: String) async throws -> [ChartResponse] {
        let response: [ChartResponse] = try await makeRequest(endpoint: .airportCharts(icao: icao))
        return response
    }

    // MARK: - 航图相关
    func getChart(id: Int) async throws -> ChartResponse {
        let response: ChartResponse = try await makeRequest(endpoint: .chart(id: id))
        return response
    }

    func getChartSignedURL(id: Int) async throws -> SignedURLResponse {
        let response: SignedURLResponse = try await makeRequest(endpoint: .chartSignedURL(id: id))
        return response
    }

    // MARK: - 航路图相关
    func getEnrouteCharts(type: String? = nil) async throws -> [ChartResponse] {
        let endpoint = APIEndpoint.enrouteCharts
        if let type = type, !type.isEmpty {
            // 添加类型参数
            var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "type", value: type)]
        }
        let response: [ChartResponse] = try await makeRequest(endpoint: endpoint)
        return response
    }

    func getEnrouteChart(id: Int) async throws -> ChartResponse {
        let response: ChartResponse = try await makeRequest(endpoint: .enrouteChart(id: id))
        return response
    }

    func getEnrouteSignedURL(id: Int) async throws -> SignedURLResponse {
        let response: SignedURLResponse = try await makeRequest(endpoint: .enrouteSignedURL(id: id))
        return response
    }

    // MARK: - 文档相关
    func getAIPDocuments(category: String? = nil) async throws -> [AIPDocumentResponse] {
        let endpoint = APIEndpoint.aipDocuments
        if let category = category, !category.isEmpty {
            var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "category", value: category)]
        }
        let response: [AIPDocumentResponse] = try await makeRequest(endpoint: endpoint)
        return response
    }

    func getAIPDocumentsByICAO(icao: String) async throws -> [AIPDocumentResponse] {
        let endpoint = APIEndpoint.aipDocumentsByICAO(icao: icao)
        let response: [AIPDocumentResponse] = try await makeRequest(endpoint: endpoint)
        return response
    }

    func getSUPDocuments(chapterType: String? = nil) async throws -> [SUPDocumentResponse] {
        let endpoint = APIEndpoint.supDocuments
        if let chapterType = chapterType, !chapterType.isEmpty {
            var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "chapter_type", value: chapterType)]
        }
        let response: [SUPDocumentResponse] = try await makeRequest(endpoint: endpoint)
        return response
    }

    func getAMDTDocuments(chapterType: String? = nil) async throws -> [AMDTDocumentResponse] {
        let endpoint = APIEndpoint.amdtDocuments
        if let chapterType = chapterType, !chapterType.isEmpty {
            var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "chapter_type", value: chapterType)]
        }
        let response: [AMDTDocumentResponse] = try await makeRequest(endpoint: endpoint)
        return response
    }

    func getNOTAMDocuments(series: String? = nil) async throws -> [NOTAMDocumentResponse] {
        let endpoint = APIEndpoint.notamDocuments
        if let series = series, !series.isEmpty {
            var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "series", value: series)]
        }
        let response: [NOTAMDocumentResponse] = try await makeRequest(endpoint: endpoint)
        return response
    }

    func getDocument(type: String, id: Int) async throws -> DocumentDetailResponse {
        let response: DocumentDetailResponse = try await makeRequest(
            endpoint: .document(type: type, id: id))
        return response
    }

    func getDocumentSignedURL(type: String, id: Int) async throws -> SignedURLResponse {
        let response: SignedURLResponse = try await makeRequest(
            endpoint: .documentSignedURL(type: type, id: id))
        return response
    }

    // MARK: - 天气相关
    func getMETAR(icao: String) async throws -> METARResponse {
        struct MetarAPIModel: Codable {
            let icaoId: String?
            let obsTime: Int?
            let reportTime: String?
            let temp: Double?
            let dewp: Double?
            let wdir: Int?
            let wspd: Double?
            let visib: String?
            let altim: Double?
            let metarType: String?
            let rawOb: String?
            let cover: String?
            let clouds: [String]?
            let fltCat: String?
        }

        let apiModel: MetarAPIModel = try await makeRequest(endpoint: .weatherMETAR(icao: icao))

        let station = apiModel.icaoId
        let observationTime =
            apiModel.reportTime
            ?? (apiModel.obsTime.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }.map {
                ISO8601DateFormatter().string(from: $0)
            })
        let windDirection = apiModel.wdir.map { "\($0)°" }
        let windSpeed = apiModel.wspd.map { String(format: "%.0f MPS", $0) }
        let visibility = apiModel.visib
        let temperature = apiModel.temp.map { String(format: "%.0f℃", $0) }
        let dewpoint = apiModel.dewp.map { String(format: "%.0f℃", $0) }
        let qnh = apiModel.altim.map { String(format: "%.0f hPa", $0) }
        let weather = apiModel.cover ?? apiModel.fltCat
        let clouds = apiModel.clouds
        let trend = apiModel.metarType
        let raw = apiModel.rawOb

        return METARResponse(
            station: station,
            observationTime: observationTime,
            windDirection: windDirection,
            windSpeed: windSpeed,
            visibility: visibility,
            temperature: temperature,
            dewpoint: dewpoint,
            qnh: qnh,
            weather: weather,
            clouds: clouds,
            trend: trend,
            raw: raw
        )
    }

    func getTAF(icao: String) async throws -> TAFResponse {
        struct TAFForecastAPI: Codable {
            let timeFrom: Int?
            let timeTo: Int?
            let timeBec: Int?
            let fcstChange: String?
            let probability: Int?
            let wdir: Int?
            let wspd: Double?
            let wxString: String?
            let visib: Int?
            let altim: Double?
            let clouds: [TAFCloudAPI]?
        }

        struct TAFCloudAPI: Codable {
            let cover: String?
            let base: Int?
            let type: String?
        }

        struct TAFAPIModel: Codable {
            let icaoId: String?
            let bulletinTime: String?
            let issueTime: String?
            let validTimeFrom: Int?
            let validTimeTo: Int?
            let rawTAF: String?
            let fcsts: [TAFForecastAPI]?
        }

        func formatEpoch(_ epoch: Int?) -> String? {
            guard let epoch = epoch else { return nil }
            return ISO8601DateFormatter().string(
                from: Date(timeIntervalSince1970: TimeInterval(epoch)))
        }

        func formatWind(dir: Int?, spd: Double?) -> String? {
            guard let dir = dir, let spd = spd else { return nil }
            return "\(dir)° \(Int(spd)) MPS"
        }

        func formatVisibility(_ vis: Int?) -> String? {
            guard let vis = vis else { return nil }
            if vis == 0 { return "CAVOK" }
            return "\(vis) m"
        }

        func mapClouds(_ clouds: [TAFCloudAPI]?) -> [String]? {
            guard let clouds = clouds, !clouds.isEmpty else { return nil }
            return clouds.map { cloud in
                let cover = cloud.cover ?? ""
                if let base = cloud.base, base > 0 {
                    return "\(cover) \(base)ft"
                } else {
                    return cover
                }
            }
        }

        let apiModel: TAFAPIModel = try await makeRequest(endpoint: .weatherTAF(icao: icao))

        let periods: [TAFPeriod]? = apiModel.fcsts?.map { f in
            let wind = formatWind(dir: f.wdir, spd: f.wspd)
            let visibility = formatVisibility(f.visib)
            let weather = f.wxString
            let clouds = mapClouds(f.clouds)
            return TAFPeriod(
                timeFrom: formatEpoch(f.timeFrom),
                timeTo: formatEpoch(f.timeTo),
                wind: wind,
                visibility: visibility,
                weather: weather,
                clouds: clouds
            )
        }

        return TAFResponse(
            station: apiModel.icaoId,
            issueTime: apiModel.issueTime ?? apiModel.bulletinTime,
            validFrom: formatEpoch(apiModel.validTimeFrom),
            validTo: formatEpoch(apiModel.validTimeTo),
            forecasts: periods,
            raw: apiModel.rawTAF
        )
    }

    // MARK: - AIRAC相关
    func getCurrentAIRAC() async throws -> AIRACResponse {
        let response: AIRACResponse = try await makeRequest(endpoint: .currentAIRAC)
        return response
    }

    // MARK: - IAP 相关方法
    /// 验证 JWS 凭证
    func verifyJWS(transactionJWS: String, appleUserId: String, environment: String? = nil)
        async throws -> VerifyJWSResponse
    {
        LoggerService.shared.info(module: "NetworkService", message: "开始验证 JWS")
        // 加密记录敏感信息
        LoggerService.shared.info(
            module: "NetworkService", message: "Transaction JWS: \(transactionJWS)")
        LoggerService.shared.info(
            module: "NetworkService", message: "Apple User ID: \(appleUserId)")
        LoggerService.shared.info(
            module: "NetworkService", message: "Environment: \(environment ?? "nil")")

        let request = VerifyJWSRequest(
            transactionJWS: transactionJWS,
            appleUserId: appleUserId,
            environment: environment
        )
        let bodyData = try JSONEncoder().encode(request)

        // IAP API 可能返回直接响应或 APIResponse 包装
        var urlRequest = URLRequest(url: APIEndpoint.iapVerify.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = bodyData

        if let token = accessToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        logRequest(request: urlRequest, body: bodyData)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            logResponse(response: nil, data: data, error: NetworkError.invalidResponse)
            throw NetworkError.invalidResponse
        }

        // 处理401错误
        if httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            urlRequest.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: urlRequest)
            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                retryHttpResponse.statusCode == 200
            else {
                throw NetworkError.unauthorized
            }
            logResponse(response: retryHttpResponse, data: retryData, error: nil)

            // 尝试直接解析或 APIResponse 格式
            do {
                return try JSONDecoder().decode(VerifyJWSResponse.self, from: retryData)
            } catch {
                let apiResponse = try JSONDecoder().decode(
                    APIResponse<VerifyJWSResponse>.self, from: retryData)
                guard let responseData = apiResponse.data else {
                    throw NetworkError.noData
                }
                return responseData
            }
        }

        guard httpResponse.statusCode == 200 else {
            let error = NetworkError.serverError(httpResponse.statusCode)
            logResponse(response: httpResponse, data: data, error: error)
            throw error
        }

        logResponse(response: httpResponse, data: data, error: nil)

        do {
            return try JSONDecoder().decode(VerifyJWSResponse.self, from: data)
        } catch {
            let apiResponse = try JSONDecoder().decode(
                APIResponse<VerifyJWSResponse>.self, from: data)
            guard let responseData = apiResponse.data else {
                throw NetworkError.noData
            }
            return responseData
        }
    }

    /// 批量同步订阅
    func syncSubscriptions(
        transactionJWSList: [String], appleUserId: String, environment: String? = nil
    ) async throws -> SyncSubscriptionResponse {
        LoggerService.shared.info(module: "NetworkService", message: "开始批量同步订阅")
        // 加密记录敏感信息
        LoggerService.shared.info(
            module: "NetworkService",
            message:
                "Transaction JWS List (\(transactionJWSList.count) 个): \(transactionJWSList.joined(separator: ","))"
        )
        LoggerService.shared.info(
            module: "NetworkService", message: "Apple User ID: \(appleUserId)")
        LoggerService.shared.info(
            module: "NetworkService", message: "Environment: \(environment ?? "nil")")

        let request = SyncSubscriptionRequest(
            transactionJWSList: transactionJWSList,
            appleUserId: appleUserId,
            environment: environment
        )
        let bodyData = try JSONEncoder().encode(request)

        var urlRequest = URLRequest(url: APIEndpoint.iapSync.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = bodyData

        if let token = accessToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        logRequest(request: urlRequest, body: bodyData)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            logResponse(response: nil, data: data, error: NetworkError.invalidResponse)
            throw NetworkError.invalidResponse
        }

        // 处理401错误
        if httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            urlRequest.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: urlRequest)
            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                retryHttpResponse.statusCode == 200
            else {
                throw NetworkError.unauthorized
            }
            logResponse(response: retryHttpResponse, data: retryData, error: nil)

            do {
                return try JSONDecoder().decode(SyncSubscriptionResponse.self, from: retryData)
            } catch {
                let apiResponse = try JSONDecoder().decode(
                    APIResponse<SyncSubscriptionResponse>.self, from: retryData)
                guard let responseData = apiResponse.data else {
                    throw NetworkError.noData
                }
                return responseData
            }
        }

        guard httpResponse.statusCode == 200 else {
            let error = NetworkError.serverError(httpResponse.statusCode)
            logResponse(response: httpResponse, data: data, error: error)
            throw error
        }

        logResponse(response: httpResponse, data: data, error: nil)

        do {
            return try JSONDecoder().decode(SyncSubscriptionResponse.self, from: data)
        } catch {
            let apiResponse = try JSONDecoder().decode(
                APIResponse<SyncSubscriptionResponse>.self, from: data)
            guard let responseData = apiResponse.data else {
                throw NetworkError.noData
            }
            return responseData
        }
    }

    /// 查询订阅状态
    func getSubscriptionStatus(appleUserId: String) async throws -> SubscriptionStatusResponse {
        LoggerService.shared.info(module: "NetworkService", message: "开始查询订阅状态")
        // 加密记录敏感信息
        LoggerService.shared.info(
            module: "NetworkService", message: "Apple User ID: \(appleUserId)")

        var components = URLComponents(
            url: APIEndpoint.iapStatus.url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "apple_user_id", value: appleUserId)]

        guard let finalURL = components.url else {
            LoggerService.shared.error(module: "NetworkService", message: "查询订阅状态失败：无效的 URL")
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        logRequest(request: request, body: nil)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logResponse(response: nil, data: data, error: NetworkError.invalidResponse)
            throw NetworkError.invalidResponse
        }

        // 处理401错误
        if httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                retryHttpResponse.statusCode == 200
            else {
                throw NetworkError.unauthorized
            }
            logResponse(response: retryHttpResponse, data: retryData, error: nil)

            do {
                return try JSONDecoder().decode(SubscriptionStatusResponse.self, from: retryData)
            } catch {
                let apiResponse = try JSONDecoder().decode(
                    APIResponse<SubscriptionStatusResponse>.self, from: retryData)
                guard let responseData = apiResponse.data else {
                    throw NetworkError.noData
                }
                return responseData
            }
        }

        guard httpResponse.statusCode == 200 else {
            let error = NetworkError.serverError(httpResponse.statusCode)
            logResponse(response: httpResponse, data: data, error: error)
            throw error
        }

        logResponse(response: httpResponse, data: data, error: nil)

        do {
            return try JSONDecoder().decode(SubscriptionStatusResponse.self, from: data)
        } catch {
            let apiResponse = try JSONDecoder().decode(
                APIResponse<SubscriptionStatusResponse>.self, from: data)
            guard let responseData = apiResponse.data else {
                throw NetworkError.noData
            }
            return responseData
        }
    }

    // MARK: - 日志记录方法
    private func logRequest(request: URLRequest, body: Data?) {
        LoggerService.shared.info(module: "NetworkService", message: "===== 网络请求开始 =====")
        LoggerService.shared.info(
            module: "NetworkService", message: "方法: \(request.httpMethod ?? "Unknown")")
        LoggerService.shared.info(
            module: "NetworkService", message: "URL: \(request.url?.absoluteString ?? "Unknown")")

        // 记录请求头
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            for (key, value) in headers {
                // 敏感信息加密记录
                if key.lowercased().contains("authorization") {
                    LoggerService.shared.info(
                        module: "NetworkService", message: "[Authorization] \(key): \(value)")
                } else {
                    LoggerService.shared.info(
                        module: "NetworkService", message: "  \(key): \(value)")
                }
            }
        }

        // 记录请求体
        if let body = body {
            LoggerService.shared.info(
                module: "NetworkService", message: "请求体大小: \(body.count) bytes")
            if let bodyString = String(data: body, encoding: .utf8) {
                // 加密记录完整请求体（可能包含敏感信息）
                LoggerService.shared.info(module: "NetworkService", message: "请求体内容: \(bodyString)")
            }
        }
        LoggerService.shared.info(module: "NetworkService", message: "请求时间: \(Date())")
    }

    private func logResponse(response: HTTPURLResponse?, data: Data, error: Error?) {
        LoggerService.shared.info(module: "NetworkService", message: "===== 网络响应 =====")

        if let response = response {
            LoggerService.shared.info(
                module: "NetworkService", message: "状态码: \(response.statusCode)")
            LoggerService.shared.info(
                module: "NetworkService",
                message: "URL: \(response.url?.absoluteString ?? "Unknown")")
        }

        // 记录响应体
        LoggerService.shared.info(module: "NetworkService", message: "响应体大小: \(data.count) bytes")
        if let responseString = String(data: data, encoding: .utf8) {
            // 限制日志长度，避免过长的响应
            let maxLength = 2000
            let truncatedResponse =
                responseString.count > maxLength
                ? String(responseString.prefix(maxLength)) + "... (截断)"
                : responseString
            // 响应可能包含敏感信息，加密记录
            LoggerService.shared.info(
                module: "NetworkService", message: "响应内容: \(truncatedResponse)")
        }

        // 记录错误
        if let error = error {
            LoggerService.shared.error(
                module: "NetworkService", message: "错误: \(error.localizedDescription)")
        } else {
            LoggerService.shared.info(module: "NetworkService", message: "请求成功")
        }

        LoggerService.shared.info(module: "NetworkService", message: "响应时间: \(Date())")
        LoggerService.shared.info(module: "NetworkService", message: "===== 网络响应结束 =====")
    }
}

// MARK: - HTTP方法枚举
enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

// MARK: - 网络错误
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case unauthorized
    case serverError(Int, message: String? = nil)
    case noRefreshToken
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .invalidResponse:
            return "无效的响应"
        case .noData:
            return "没有数据"
        case .unauthorized:
            return "未授权访问"
        case .serverError(let code, let message):
            if let message = message {
                return "服务器错误 \(code): \(message)"
            }
            return "服务器错误: \(code)"
        case .noRefreshToken:
            return "没有刷新令牌"
        case .decodingError:
            return "数据解析错误"
        }
    }
}
