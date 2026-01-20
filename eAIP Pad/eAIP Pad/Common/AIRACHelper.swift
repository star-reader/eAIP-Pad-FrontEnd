import Foundation
import SwiftData

@MainActor
class AIRACHelper {
    static let shared = AIRACHelper()
    
    private init() {}
    
    func getCurrentAIRACVersion(modelContext: ModelContext) async -> String? {
        if let cached = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) {
            return cached
        }
        
        do {
            let airacResponse = try await NetworkService.shared.getCurrentAIRAC()
            let version = airacResponse.version
            
            let newVersion = AIRACVersion(
                version: version,
                effectiveDate: ISO8601DateFormatter().date(from: airacResponse.effectiveDate) ?? Date(),
                isCurrent: true
            )
            modelContext.insert(newVersion)
            try? modelContext.save()
            
            return version
        } catch {
            LoggerService.shared.error(module: "AIRACHelper", message: "获取 AIRAC 版本失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    func loadCachedData<T: Codable>(_ type: T.Type, airacVersion: String, dataType: String) -> T? {
        return PDFCacheService.shared.loadCachedData(type, airacVersion: airacVersion, dataType: dataType)
    }
    
    func cacheData<T: Codable>(_ data: T, airacVersion: String, dataType: String) {
        try? PDFCacheService.shared.cacheData(data, airacVersion: airacVersion, dataType: dataType)
    }
}
