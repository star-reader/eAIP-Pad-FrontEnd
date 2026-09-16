import Foundation
import SwiftData

@MainActor
class AIRACHelper {
    static let shared = AIRACHelper()

    static let missingDataErrorDomain = "AIRACHelper"
    static let missingDataErrorCode = -1001
    static let missingDataMessage = "暂无本地 AIRAC 数据，请先在「个人」中导入数据包"

    private init() {}

    /// 返回本地已导入的当前 AIRAC 版本；没有导入过数据时返回 nil（不再联网获取）
    func getCurrentAIRACVersion(modelContext: ModelContext) async -> String? {
        return PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext)
    }

    func hasLocalAIRACData(modelContext: ModelContext) -> Bool {
        PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) != nil
    }

    static func makeMissingDataError() -> NSError {
        NSError(
            domain: missingDataErrorDomain,
            code: missingDataErrorCode,
            userInfo: [NSLocalizedDescriptionKey: missingDataMessage]
        )
    }

    static func isMissingDataError(_ message: String) -> Bool {
        message.contains(missingDataMessage)
    }
}
