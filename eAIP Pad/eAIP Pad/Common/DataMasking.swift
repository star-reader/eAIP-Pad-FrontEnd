import Foundation

// MARK: - 数据脱敏工具
struct DataMasking {
    
    // MARK: - 脱敏 Token
    static func maskToken(_ token: String) -> String {
        guard token.count > 8 else { return "***" }
        let prefix = token.prefix(4)
        let suffix = token.suffix(4)
        return "\(prefix)...\(suffix)"
    }
    
    // MARK: - 脱敏 Apple User ID
    static func maskAppleUserId(_ userId: String) -> String {
        guard userId.count > 8 else { return "***" }
        let prefix = userId.prefix(4)
        let suffix = userId.suffix(4)
        return "\(prefix)...\(suffix)"
    }
    
    // MARK: - 脱敏 JWS（JSON Web Signature）
    static func maskJWS(_ jws: String) -> String {
        guard jws.count > 20 else { return "***" }
        let prefix = jws.prefix(10)
        let suffix = jws.suffix(10)
        return "\(prefix)...\(suffix)"
    }
    
    // MARK: - 脱敏邮箱地址
    static func maskEmail(_ email: String) -> String {
        let components = email.split(separator: "@")
        guard components.count == 2 else { return "***@***.***" }
        
        let username = String(components[0])
        let domain = String(components[1])
        
        let maskedUsername: String
        if username.count <= 2 {
            maskedUsername = String(repeating: "*", count: username.count)
        } else {
            maskedUsername = "\(username.prefix(1))\(String(repeating: "*", count: username.count - 2))\(username.suffix(1))"
        }
        
        return "\(maskedUsername)@\(domain)"
    }
    
    // MARK: - 脱敏手机号
    static func maskPhoneNumber(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 7 else { return "***" }
        
        let prefix = digits.prefix(3)
        let suffix = digits.suffix(4)
        return "\(prefix)****\(suffix)"
    }
    
    // MARK: - 脱敏 URL 中的敏感参数
    static func maskURLParameters(_ url: String, sensitiveKeys: [String] = ["token", "key", "secret", "password"]) -> String {
        guard var urlComponents = URLComponents(string: url) else { return url }
        
        if var queryItems = urlComponents.queryItems {
            queryItems = queryItems.map { item in
                if sensitiveKeys.contains(where: { item.name.lowercased().contains($0) }) {
                    return URLQueryItem(name: item.name, value: "***")
                }
                return item
            }
            urlComponents.queryItems = queryItems
        }
        
        return urlComponents.url?.absoluteString ?? url
    }
    
    // MARK: - 脱敏 JSON 中的敏感字段
    static func maskJSONSensitiveFields(_ jsonString: String, sensitiveKeys: [String] = ["token", "password", "secret", "key"]) -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return jsonString
        }
        
        let maskedJSON = maskDictionary(json, sensitiveKeys: sensitiveKeys)
        
        guard let maskedData = try? JSONSerialization.data(withJSONObject: maskedJSON, options: .prettyPrinted),
              let maskedString = String(data: maskedData, encoding: .utf8) else {
            return jsonString
        }
        
        return maskedString
    }
    
    // MARK: - 递归脱敏字典
    private static func maskDictionary(_ dict: [String: Any], sensitiveKeys: [String]) -> [String: Any] {
        var maskedDict = dict
        
        for (key, value) in dict {
            if sensitiveKeys.contains(where: { key.lowercased().contains($0) }) {
                maskedDict[key] = "***"
            } else if let nestedDict = value as? [String: Any] {
                maskedDict[key] = maskDictionary(nestedDict, sensitiveKeys: sensitiveKeys)
            } else if let nestedArray = value as? [[String: Any]] {
                maskedDict[key] = nestedArray.map { maskDictionary($0, sensitiveKeys: sensitiveKeys) }
            }
        }
        
        return maskedDict
    }
    
    // MARK: - 通用脱敏方法
    static func mask(_ value: String, type: MaskType) -> String {
        switch type {
        case .token:
            return maskToken(value)
        case .appleUserId:
            return maskAppleUserId(value)
        case .jws:
            return maskJWS(value)
        case .email:
            return maskEmail(value)
        case .phoneNumber:
            return maskPhoneNumber(value)
        case .url:
            return maskURLParameters(value)
        case .json:
            return maskJSONSensitiveFields(value)
        }
    }
}

// MARK: - 脱敏类型枚举
enum MaskType {
    case token
    case appleUserId
    case jws
    case email
    case phoneNumber
    case url
    case json
}

// MARK: - String 扩展：便捷脱敏方法
extension String {
    func masked(as type: MaskType) -> String {
        return DataMasking.mask(self, type: type)
    }
    
    var maskedToken: String {
        return DataMasking.maskToken(self)
    }
    
    var maskedAppleUserId: String {
        return DataMasking.maskAppleUserId(self)
    }
    
    var maskedJWS: String {
        return DataMasking.maskJWS(self)
    }
    
    var maskedEmail: String {
        return DataMasking.maskEmail(self)
    }
    
    var maskedPhoneNumber: String {
        return DataMasking.maskPhoneNumber(self)
    }
}
