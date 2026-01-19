import Foundation
import Combine

// MARK: - 基础网络客户端
/// 提供可复用的网络请求基础设施，包括重试、取消、日志等功能
class BaseNetworkClient {
    
    // MARK: - 属性
    private var activeTasks: [UUID: Task<Any, Error>] = [:]
    private let taskLock = NSLock()
    
    // MARK: - 初始化
    init() {
        LoggerService.shared.info(module: "BaseNetworkClient", message: "网络客户端初始化")
    }
    
    deinit {
        cancelAllRequests()
    }
    
    // MARK: - 请求取消管理
    func cancelAllRequests() {
        taskLock.lock()
        defer { taskLock.unlock() }
        
        LoggerService.shared.info(module: "BaseNetworkClient", message: "取消所有网络请求 (\(activeTasks.count) 个)")
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
    }
    
    private func registerTask<T>(_ task: Task<T, Error>) -> UUID {
        let taskId = UUID()
        taskLock.lock()
        defer { taskLock.unlock() }
        activeTasks[taskId] = task as? Task<Any, Error>
        return taskId
    }
    
    private func unregisterTask(_ taskId: UUID) {
        taskLock.lock()
        defer { taskLock.unlock() }
        activeTasks.removeValue(forKey: taskId)
    }
    
    // MARK: - 通用请求方法（带重试）
    func makeRequest<T: Codable>(
        endpoint: APIEndpoint,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        requiresAuth: Bool = true,
        accessToken: String? = nil,
        maxRetries: Int = 3
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await performRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    requiresAuth: requiresAuth,
                    accessToken: accessToken
                )
            } catch {
                lastError = error
                
                let shouldRetry = shouldRetryRequest(error: error, attempt: attempt, maxRetries: maxRetries)
                
                if shouldRetry && attempt < maxRetries - 1 {
                    let delay = NetworkConfig.retryDelay(for: attempt)
                    LoggerService.shared.warning(
                        module: "BaseNetworkClient",
                        message: "请求失败，\(delay)秒后重试 (尝试 \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)"
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    break
                }
            }
        }
        
        throw lastError ?? NetworkError.unknown(NSError(domain: "BaseNetworkClient", code: -1))
    }
    
    // MARK: - 执行单次请求
    private func performRequest<T: Codable>(
        endpoint: APIEndpoint,
        method: HTTPMethod,
        body: Data?,
        requiresAuth: Bool,
        accessToken: String?
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = NetworkConfig.requestTimeout
        
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
        
        // 记录响应
        logResponse(response: httpResponse, data: data, error: nil)
        
        // 处理错误状态码
        guard httpResponse.statusCode == 200 else {
            let error = NetworkError.serverError(httpResponse.statusCode)
            throw error
        }
        
        // 解析响应
        let apiResponse = try JSONDecoder().decode(APIResponse<T>.self, from: data)
        guard let responseData = apiResponse.data else {
            throw NetworkError.noData
        }
        
        return responseData
    }
    
    // MARK: - 判断是否应该重试
    private func shouldRetryRequest(error: Error, attempt: Int, maxRetries: Int) -> Bool {
        if attempt >= maxRetries - 1 {
            return false
        }
        
        if let networkError = error as? NetworkError {
            switch networkError {
            case .timeout, .noConnection:
                return true
            case .serverError(let code, _):
                return code >= 500 && code < 600
            case .unauthorized, .noRefreshToken, .invalidURL, .invalidResponse, .noData, .decodingError:
                return false
            case .unknown:
                return true
            }
        }
        
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                return true
            default:
                return false
            }
        }
        
        return false
    }
    
    // MARK: - 日志记录
    private func logRequest(request: URLRequest, body: Data?) {
        LoggerService.shared.info(module: "BaseNetworkClient", message: "===== 网络请求开始 =====")
        LoggerService.shared.info(
            module: "BaseNetworkClient", message: "方法: \(request.httpMethod ?? "Unknown")")
        
        let urlString = request.url?.absoluteString ?? "Unknown"
        let maskedURL = DataMasking.maskURLParameters(urlString)
        LoggerService.shared.info(
            module: "BaseNetworkClient", message: "URL: \(maskedURL)")
        
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            for (key, value) in headers {
                if key.lowercased().contains("authorization") {
                    let maskedValue = value.hasPrefix("Bearer ") 
                        ? "Bearer \(String(value.dropFirst(7)).maskedToken)"
                        : value.maskedToken
                    LoggerService.shared.info(
                        module: "BaseNetworkClient", message: "  \(key): \(maskedValue)")
                } else {
                    LoggerService.shared.info(
                        module: "BaseNetworkClient", message: "  \(key): \(value)")
                }
            }
        }
        
        if let body = body {
            LoggerService.shared.info(
                module: "BaseNetworkClient", message: "请求体大小: \(body.count) bytes")
            if let bodyString = String(data: body, encoding: .utf8) {
                let maskedBody = DataMasking.maskJSONSensitiveFields(
                    bodyString, 
                    sensitiveKeys: ["token", "password", "secret", "key", "id_token", "refresh_token", "access_token"]
                )
                LoggerService.shared.info(module: "BaseNetworkClient", message: "请求体内容: \(maskedBody)")
            }
        }
    }
    
    private func logResponse(response: HTTPURLResponse?, data: Data, error: Error?) {
        LoggerService.shared.info(module: "BaseNetworkClient", message: "===== 网络响应 =====")
        
        if let response = response {
            LoggerService.shared.info(
                module: "BaseNetworkClient", message: "状态码: \(response.statusCode)")
            
            let urlString = response.url?.absoluteString ?? "Unknown"
            let maskedURL = DataMasking.maskURLParameters(urlString)
            LoggerService.shared.info(
                module: "BaseNetworkClient", message: "URL: \(maskedURL)")
        }
        
        LoggerService.shared.info(module: "BaseNetworkClient", message: "响应体大小: \(data.count) bytes")
        if let responseString = String(data: data, encoding: .utf8) {
            let maxLength = 2000
            let truncatedResponse =
                responseString.count > maxLength
                ? String(responseString.prefix(maxLength)) + "... (截断)"
                : responseString
            
            let maskedResponse = DataMasking.maskJSONSensitiveFields(
                truncatedResponse,
                sensitiveKeys: ["token", "password", "secret", "key", "access_token", "refresh_token", "id_token", "transaction_jws"]
            )
            LoggerService.shared.info(
                module: "BaseNetworkClient", message: "响应内容: \(maskedResponse)")
        }
        
        if let error = error {
            LoggerService.shared.error(
                module: "BaseNetworkClient", message: "错误: \(error.localizedDescription)")
        } else {
            LoggerService.shared.info(module: "BaseNetworkClient", message: "请求成功")
        }
        
        LoggerService.shared.info(module: "BaseNetworkClient", message: "===== 网络响应结束 =====")
    }
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
    case timeout
    case noConnection
    case unknown(Error)

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
        case .timeout:
            return "请求超时"
        case .noConnection:
            return "网络连接失败"
        case .unknown(let error):
            return "未知错误: \(error.localizedDescription)"
        }
    }
}
