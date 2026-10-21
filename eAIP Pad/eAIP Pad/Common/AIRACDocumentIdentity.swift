import Foundation

/// 文档的展示标识与数据库主键分开：展示标识跨周期稳定，主键包含周期。
nonisolated enum AIRACDocumentIdentity {
    static func documentID(from chartID: String, documentType: String) -> String {
        let prefix = "\(documentType)_"
        return chartID.hasPrefix(prefix) ? String(chartID.dropFirst(prefix.count)) : chartID
    }

    static func cacheID(documentID: String, documentType: String, category: String?) -> String {
        // GEN 与 ENR 都显示为 AIP，但原始节点 ID 属于各自的索引文件。
        if documentType == "aip", let category, !category.isEmpty {
            return "\(category)_\(documentID)"
        }
        return documentID
    }

    static func storageID(version: String, readerID: String) -> String {
        "\(version.utf8.count):\(version)\(readerID.utf8.count):\(readerID)"
    }

    static func fileComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

nonisolated enum AIRACPackageError: LocalizedError {
    case missingLocalData
    case invalidPackage(String)
    case missingPDF(String)
    case invalidPDF(String)
    case fileOperation(String, String)

    var errorDescription: String? {
        switch self {
        case .missingLocalData: return "暂无本地 AIRAC 数据，请先在「个人」中导入数据包"
        case .invalidPackage(let message): return message
        case .missingPDF(let path): return "数据包缺少 PDF：\(path)"
        case .invalidPDF(let path): return "PDF 无法读取或没有页面：\(path)"
        case .fileOperation(let path, let reason): return "处理文件失败：\(path)（\(reason)）"
        }
    }
}
