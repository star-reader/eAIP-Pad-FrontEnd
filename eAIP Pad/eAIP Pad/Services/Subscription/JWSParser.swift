import Foundation
import StoreKit

// MARK: - JWS 解析工具
struct JWSParser {
    
    /// 从 VerificationResult 获取原始 JWS 字符串
    nonisolated static func getJWSString(from result: VerificationResult<StoreKit.Transaction>) -> String? {
        return result.jwsRepresentation
    }
    
    /// 从 JWS 中提取环境信息
    static func extractEnvironment(from jws: String) -> String? {
        let parts = jws.split(separator: ".")
        guard parts.count >= 2 else {
            return defaultEnvironment()
        }

        let payloadString = String(parts[1])
        let base64 = payloadString.base64URLDecoded

        guard let payloadData = Data(base64Encoded: base64),
            let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let environment = payload["environment"] as? String
        else {
            return defaultEnvironment()
        }

        return normalizeEnvironment(environment)
    }
    
    /// 标准化环境字符串
    private static func normalizeEnvironment(_ environment: String) -> String {
        switch environment.lowercased() {
        case "production":
            return "Production"
        case "sandbox":
            return "Sandbox"
        case "xcode":
            return "Sandbox"
        default:
            return environment.capitalized
        }
    }
    
    /// 获取默认环境（基于编译配置）
    private static func defaultEnvironment() -> String {
        #if DEBUG
            return "Sandbox"
        #else
            return "Production"
        #endif
    }
}
