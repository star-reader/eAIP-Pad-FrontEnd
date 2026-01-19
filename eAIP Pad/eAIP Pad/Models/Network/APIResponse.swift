import Foundation

// MARK: - 通用 API 响应
struct APIResponse<T: Codable>: Codable {
    let message: String
    let data: T?
}
