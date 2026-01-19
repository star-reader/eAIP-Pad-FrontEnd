import Foundation
import Security

// MARK: - Keychain 错误
enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidItemFormat
    case unexpectedStatus(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain 中未找到该项"
        case .duplicateItem:
            return "Keychain 中已存在该项"
        case .invalidItemFormat:
            return "无效的数据格式"
        case .unexpectedStatus(let status):
            return "Keychain 操作失败，状态码: \(status)"
        }
    }
}

// MARK: - Keychain 服务
class KeychainService {
    static let shared = KeychainService()
    
    private init() {}
    
    // MARK: - 保存数据
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidItemFormat
        }
        
        try save(key: key, data: data)
    }
    
    func save(key: String, data: Data) throws {
        // 先删除已存在的项
        try? delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        
        LoggerService.shared.info(module: "KeychainService", message: "成功保存项: \(key)")
    }
    
    // MARK: - 读取数据
    func load(key: String) throws -> String {
        let data = try loadData(key: key)
        
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidItemFormat
        }
        
        return string
    }
    
    func loadData(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidItemFormat
        }
        
        return data
    }
    
    // MARK: - 删除数据
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        
        LoggerService.shared.info(module: "KeychainService", message: "成功删除项: \(key)")
    }
    
    // MARK: - 更新数据
    func update(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidItemFormat
        }
        
        try update(key: key, data: data)
    }
    
    func update(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                // 如果不存在，则创建
                try save(key: key, data: data)
                return
            }
            throw KeychainError.unexpectedStatus(status)
        }
        
        LoggerService.shared.info(module: "KeychainService", message: "成功更新项: \(key)")
    }
    
    // MARK: - 检查是否存在
    func exists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - 清除所有数据
    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        
        LoggerService.shared.info(module: "KeychainService", message: "已清除所有 Keychain 数据")
    }
}

// MARK: - Keychain Keys 常量
extension KeychainService {
    enum Keys {
        static let accessToken = "com.usagijin.eaip.accessToken"
        static let refreshToken = "com.usagijin.eaip.refreshToken"
        static let appleUserId = "com.usagijin.eaip.appleUserId"
    }
}
