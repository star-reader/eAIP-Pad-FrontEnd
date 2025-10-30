import SwiftUI
import SwiftData
import Foundation

// MARK: - 用户收藏的航图
@Model
final class PinnedChart {
    @Attribute(.unique) var chartID: String
    var displayName: String
    var icao: String
    var type: String // SID, STAR, APP, APT, OTHERS
    var pinnedAt: Date = Date()
    var thumbnailData: Data? // 预览图缓存
    var documentType: String // chart, enroute, aip, sup, amdt, notam
    var airacVersion: String
    
    init(chartID: String, displayName: String, icao: String, type: String, documentType: String, airacVersion: String) {
        self.chartID = chartID
        self.displayName = displayName
        self.icao = icao
        self.type = type
        self.documentType = documentType
        self.airacVersion = airacVersion
    }
}

// MARK: - 航图标注数据
@Model
final class ChartAnnotation {
    @Attribute(.unique) var compositeID: String // "chartID_page"
    var chartID: String
    var pageNumber: Int
    var pathsJSON: String // 矢量路径 JSON 字符串
    var updatedAt: Date = Date()
    var documentType: String // chart, enroute, aip, sup, amdt, notam
    
    init(chartID: String, pageNumber: Int, pathsJSON: String, documentType: String) {
        self.chartID = chartID
        self.pageNumber = pageNumber
        self.pathsJSON = pathsJSON
        self.documentType = documentType
        self.compositeID = "\(chartID)_\(pageNumber)"
    }
}

// MARK: - AIRAC 版本管理
@Model
final class AIRACVersion {
    @Attribute(.unique) var version: String // "2510"
    var effectiveDate: Date
    var isCurrent: Bool = false
    var downloadedCharts: Int = 0
    var totalCharts: Int = 0
    var createdAt: Date = Date()
    
    init(version: String, effectiveDate: Date, isCurrent: Bool = false) {
        self.version = version
        self.effectiveDate = effectiveDate
        self.isCurrent = isCurrent
    }
}

// MARK: - 用户设置
@Model
final class UserSettings {
    @Attribute(.unique) var id: String = "singleton"
    var isDarkMode: Bool = true
    var pinboardStyle: String = "compact" // compact, preview, grid
    var lastSyncDate: Date?
    var isFirstLaunch: Bool = true
    var subscriptionStatus: String = "trial" // trial, active, expired, inactive
    var trialEndDate: Date?
    var subscriptionEndDate: Date?
    
    init() {
        // 单例模式，默认设置
    }
}

// MARK: - 本地航图元数据
@Model
final class LocalChart {
    @Attribute(.unique) var chartID: String
    var documentID: String
    var parentID: String?
    var icao: String?
    var nameEn: String
    var nameCn: String
    var chartType: String
    var pdfPath: String?
    var htmlPath: String?
    var htmlEnPath: String?
    var airacVersion: String
    var isModified: Bool = false
    var isOpened: Bool = false
    var documentType: String // chart, enroute, aip, sup, amdt, notam
    var category: String? // 用于 AIP 文档分类
    var serialNumber: String? // 用于 SUP/AMDT
    var subject: String? // 用于 SUP/AMDT
    var localSubject: String? // 用于 SUP/AMDT 中文主题
    var chapterType: String? // 用于 SUP/AMDT
    var effectiveTime: String? // 用于 SUP/AMDT
    var outDate: String? // 用于 SUP/AMDT
    var pubDate: String? // 用于 SUP/AMDT
    var seriesName: String? // 用于 NOTAM
    var generateTime: String? // 用于 NOTAM
    var generateTimeEn: String? // 用于 NOTAM
    var createdAt: Date = Date()
    
    // 机场关联关系
    @Relationship var airport: Airport?
    
    init(chartID: String, documentID: String, nameEn: String, nameCn: String, 
         chartType: String, airacVersion: String, documentType: String) {
        self.chartID = chartID
        self.documentID = documentID
        self.nameEn = nameEn
        self.nameCn = nameCn
        self.chartType = chartType
        self.airacVersion = airacVersion
        self.documentType = documentType
    }
}

// MARK: - 机场信息
@Model
final class Airport {
    @Attribute(.unique) var icao: String
    var nameEn: String
    var nameCn: String
    var hasTerminalCharts: Bool = true
    var createdAt: Date = Date()
    
    // 关联的航图
    @Relationship(deleteRule: .cascade, inverse: \LocalChart.airport)
    var charts: [LocalChart] = []
    
    init(icao: String, nameEn: String, nameCn: String, hasTerminalCharts: Bool = true) {
        self.icao = icao
        self.nameEn = nameEn
        self.nameCn = nameCn
        self.hasTerminalCharts = hasTerminalCharts
    }
}

// 注意：@Relationship 必须在 @Model 类内部定义，不能在扩展中使用

// MARK: - Pinboard 样式枚举
enum PinboardStyle: String, CaseIterable {
    case compact = "compact"
    case preview = "preview"
    case grid = "grid"
    
    var displayName: String {
        switch self {
        case .compact: return "紧凑模式"
        case .preview: return "预览图模式"
        case .grid: return "任务平铺"
        }
    }
}

// MARK: - 文档类型枚举
enum DocumentType: String, CaseIterable {
    case chart = "chart"
    case enroute = "enroute"
    case aip = "aip"
    case sup = "sup"
    case amdt = "amdt"
    case notam = "notam"
    
    var displayName: String {
        switch self {
        case .chart: return "机场航图"
        case .enroute: return "航路图"
        case .aip: return "AIP文档"
        case .sup: return "SUP文档"
        case .amdt: return "AMDT文档"
        case .notam: return "NOTAM文档"
        }
    }
}

// MARK: - 订阅状态枚举
enum SubscriptionStatus: String, CaseIterable {
    case trial = "trial"
    case active = "active"
    case expired = "expired"
    case inactive = "inactive"
    
    var displayName: String {
        switch self {
        case .trial: return "试用期"
        case .active: return "已订阅"
        case .expired: return "已过期"
        case .inactive: return "未订阅"
        }
    }
    
    var isValid: Bool {
        return self == .trial || self == .active
    }
}
