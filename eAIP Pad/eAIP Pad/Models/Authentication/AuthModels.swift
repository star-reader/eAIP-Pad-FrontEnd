import Foundation

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

// MARK: - 认证用户模型
struct AuthenticatedUser {
    let accessToken: String
    let isNewUser: Bool
    let authenticatedAt: Date

    init(accessToken: String, isNewUser: Bool = false) {
        self.accessToken = accessToken
        self.isNewUser = isNewUser
        self.authenticatedAt = Date()
    }
}

// MARK: - 认证状态枚举
enum AuthenticationState: Equatable {
    case notAuthenticated
    case authenticating
    case authenticated
    case error(String)
}
