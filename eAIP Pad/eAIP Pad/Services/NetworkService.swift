import Foundation
import SwiftUI
import Combine

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
    case verifyIAP
    case subscriptionStatus
    case trialStart
    case currentAIRAC
    
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
        case .verifyIAP:
            return "/iap/verify"
        case .subscriptionStatus:
            return "/subscription/status"
        case .trialStart:
            return "/trial/start"
        case .currentAIRAC:
            return "/airac/current"
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
    let subscription: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case isNewUser = "is_new_user"
        case subscription
    }
}

// MARK: - 机场响应
struct AirportResponse: Codable {
    let icao: String
    let nameEn: String
    let nameCn: String
    let hasTerminalCharts: Bool
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case icao
        case nameEn = "name_en"
        case nameCn = "name_cn"
        case hasTerminalCharts = "has_terminal_charts"
        case createdAt = "created_at"
    }
}

// MARK: - 航图响应
struct ChartResponse: Codable {
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

// MARK: - 订阅状态响应
struct SubscriptionStatusResponse: Codable {
    let status: String
    let isTrial: Bool
    let trialEnd: String?
    let subscriptionEnd: String?
    let daysLeft: Int?
    
    enum CodingKeys: String, CodingKey {
        case status
        case isTrial = "is_trial"
        case trialEnd = "trial_end"
        case subscriptionEnd = "subscription_end"
        case daysLeft = "days_left"
    }
}

// MARK: - 试用期响应
struct TrialStartResponse: Codable {
    let message: String?
    let data: TrialData?
    let status: String? // 有些接口可能直接返回 status
    
    struct TrialData: Codable {
        let status: String? // trial_started, trial_used, trial_expired
        let trialEndDate: String?
        let daysLeft: Int?
        let message: String?
        
        enum CodingKeys: String, CodingKey {
            case status
            case trialEndDate = "trial_end_date"
            case daysLeft = "days_left"
            case message
        }
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
    let isModified: Bool?  // 改为可选，API返回的是has_update
    let hasUpdate: Bool?   // 新增字段，对应API的has_update
    let isOpened: Bool?    // 改为可选，因为API可能不返回此字段
    
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
    let pdfPath: String?  // 改为可选，API可能不返回
    let effectiveTime: String?
    let outDate: String?
    let pubDate: String?
    let airacVersion: String
    let isModified: Bool?  // 改为可选，API返回的是has_update
    let hasUpdate: Bool?   // 新增字段，对应API的has_update
    
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
    let pdfPath: String?  // 改为可选，API可能不返回
    let effectiveTime: String?
    let outDate: String?
    let pubDate: String?
    let airacVersion: String
    let isModified: Bool?  // 改为可选，API返回的是has_update
    let hasUpdate: Bool?   // 新增字段，对应API的has_update
    
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
    let pdfPath: String?  // 改为可选，API可能不返回
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

// MARK: - 网络服务
class NetworkService: ObservableObject {
    static let shared = NetworkService()
    
    private var accessToken: String?
    private var refreshToken: String?
    
    private init() {}
    
    // MARK: - 认证相关
    func setTokens(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
    
    func clearTokens() {
        self.accessToken = nil
        self.refreshToken = nil
    }
    
    func getCurrentAccessToken() -> String? {
        return accessToken
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
            
            try await refreshAccessToken()
            // 重新设置认证头并重试
            request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                  retryHttpResponse.statusCode == 200 else {
                logResponse(response: retryResponse as? HTTPURLResponse, data: retryData, error: NetworkError.unauthorized)
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
        let body = ["id_token": idToken]
        let bodyData = try JSONEncoder().encode(body)
        
        let response: AuthResponse = try await makeRequest(
            endpoint: .appleLogin,
            method: .POST,
            body: bodyData,
            requiresAuth: false
        )
        return response
    }
    
    func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw NetworkError.noRefreshToken
        }
        
        let body = ["refresh_token": refreshToken]
        let bodyData = try JSONEncoder().encode(body)
        
        let response: AuthResponse = try await makeRequest(
            endpoint: .refreshToken,
            method: .POST,
            body: bodyData,
            requiresAuth: false
        )
        
        setTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
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
    
    // MARK: - 订阅相关
    func getSubscriptionStatus() async throws -> SubscriptionStatusResponse {
        let response: SubscriptionStatusResponse = try await makeRequest(endpoint: .subscriptionStatus)
        return response
    }
    
    func verifyIAP(receipt: String) async throws -> SubscriptionStatusResponse {
        let body = ["receipt": receipt]
        let bodyData = try JSONEncoder().encode(body)
        
        let response: SubscriptionStatusResponse = try await makeRequest(
            endpoint: .verifyIAP,
            method: .POST,
            body: bodyData
        )
        return response
    }
    
    // MARK: - 试用期开始
    func startTrial(userId: String) async throws -> TrialStartResponse {
        let body = ["user_id": userId]
        let bodyData = try JSONEncoder().encode(body)
        
        var request = URLRequest(url: APIEndpoint.trialStart.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        // 打印原始响应用于调试
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📦 试用开始原始响应: \(jsonString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.serverError(httpResponse.statusCode)
        }
        
        // 尝试直接解析为 TrialStartResponse
        do {
            let response = try JSONDecoder().decode(TrialStartResponse.self, from: data)
            return response
        } catch {
            print("❌ 直接解析失败，尝试从 APIResponse 中提取")
            // 尝试从 APIResponse 包装中提取
            let apiResponse = try JSONDecoder().decode(APIResponse<TrialStartResponse>.self, from: data)
            guard let responseData = apiResponse.data else {
                throw NetworkError.noData
            }
            return responseData
        }
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
        let response: DocumentDetailResponse = try await makeRequest(endpoint: .document(type: type, id: id))
        return response
    }
    
    func getDocumentSignedURL(type: String, id: Int) async throws -> SignedURLResponse {
        let response: SignedURLResponse = try await makeRequest(endpoint: .documentSignedURL(type: type, id: id))
        return response
    }
    
    // MARK: - AIRAC相关
    func getCurrentAIRAC() async throws -> AIRACResponse {
        let response: AIRACResponse = try await makeRequest(endpoint: .currentAIRAC)
        return response
    }
    
    // MARK: - 日志记录方法
    private func logRequest(request: URLRequest, body: Data?) {
        print("\n===== 网络请求开始 =====")
        print("方法: \(request.httpMethod ?? "Unknown")")
        print("URL: \(request.url?.absoluteString ?? "Unknown")")
        
        // 记录请求头
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            print("请求头:")
            for (key, value) in headers {
                // 隐藏敏感信息
                if key.lowercased().contains("authorization") {
                    print("  \(key): Bearer ***")
                } else {
                    print("  \(key): \(value)")
                }
            }
        }
        
        // 记录请求体
        if let body = body {
            print("请求体大小: \(body.count) bytes")
            if let bodyString = String(data: body, encoding: .utf8) {
                // 隐藏敏感信息
                let sanitizedBody = bodyString
                    .replacingOccurrences(of: "\"id_token\":\"[^\"]*\"", with: "\"id_token\":\"***\"", options: .regularExpression)
                    .replacingOccurrences(of: "\"refresh_token\":\"[^\"]*\"", with: "\"refresh_token\":\"***\"", options: .regularExpression)
                print("请求体内容: \(sanitizedBody)")
            }
        }
        print("请求时间: \(Date())")
    }
    
    private func logResponse(response: HTTPURLResponse?, data: Data, error: Error?) {
        print("\n===== 网络响应 =====")
        
        if let response = response {
            print("状态码: \(response.statusCode)")
            print("URL: \(response.url?.absoluteString ?? "Unknown")")
            
            // 记录响应头
            
        }
        
        // 记录响应体
        print("响应体大小: \(data.count) bytes")
        if let responseString = String(data: data, encoding: .utf8) {
            // 限制日志长度，避免过长的响应
            let maxLength = 2000
            let truncatedResponse = responseString.count > maxLength 
                ? String(responseString.prefix(maxLength)) + "... (截断)"
                : responseString
            print("响应内容: \(truncatedResponse)")
        }
        
        // 记录错误
        if let error = error {
            print("错误: \(error.localizedDescription)")
        } else {
            print("请求成功")
        }
        
        print("响应时间: \(Date())")
        print("===== 网络响应结束 =====\n")
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
    case serverError(Int)
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
        case .serverError(let code):
            return "服务器错误: \(code)"
        case .noRefreshToken:
            return "没有刷新令牌"
        case .decodingError:
            return "数据解析错误"
        }
    }
}
