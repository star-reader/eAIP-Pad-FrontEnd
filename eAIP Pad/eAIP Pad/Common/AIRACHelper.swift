import Foundation
import SwiftData

@MainActor
class AIRACHelper {
    static let shared = AIRACHelper()
    
    private init() {}
    
    /// 返回本地已导入的当前 AIRAC 版本；没有导入过数据时返回 nil（不再联网获取）
    func getCurrentAIRACVersion(modelContext: ModelContext) async -> String? {
        return PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext)
    }
}
