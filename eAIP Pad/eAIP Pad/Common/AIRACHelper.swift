import Foundation
import SwiftData

@MainActor
class AIRACHelper {
    static let shared = AIRACHelper()

    static let missingDataErrorDomain = "AIRACHelper"
    static let missingDataErrorCode = -1001
    static let missingDataMessage = "暂无 AIRAC 数据，请先在「个人」中导入数据包或配置在线服务器"

    private init() {}

    /// 返回已启用的数据源周期；尚未导入或配置时返回 nil
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
