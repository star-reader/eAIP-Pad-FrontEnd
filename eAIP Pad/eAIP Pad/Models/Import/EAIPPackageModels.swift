import Foundation

// MARK: - EAIP 官方 Web 包数据模型
// 对应从 eAIP China 官网下载的 "Full Package (Web)" 解压后的 Data/ 目录结构。

/// Data/Customers.js 里的 AIRAC 版本元信息（文件本身是 `var Customers=[{...}];`，需要先剥掉变量声明再当 JSON 解析）
struct EAIPCustomer: Codable {
    let dataName: String
    let dataVersion: String
    let effectiveDate: String
    let deadline: String
    let publishDate: String

    enum CodingKeys: String, CodingKey {
        case dataName = "DataName"
        case dataVersion = "DataVersion"
        case effectiveDate = "EffectiveDate"
        case deadline = "Deadline"
        case publishDate = "PublishDate"
    }
}

/// Data/JsonPath/{AD,GEN,ENR}.JSON 里的树形节点（父子关系通过 id/pId 串联）
struct EAIPTreeNode: Codable {
    let id: String
    let pId: String
    let name: String
    let airporticao: String?
    let nameCn: String
    let pdfPath: String
    let isModified: String?

    enum CodingKeys: String, CodingKey {
        case id
        case pId
        case name
        case airporticao
        case nameCn = "name_cn"
        case pdfPath
        case isModified = "Is_Modified"
    }
}

/// Data/JsonPath/{SUP,AIC}.JSON 里的平铺文档记录
struct EAIPFlatDocument: Codable {
    let id: String
    let document: String
    let chapterType: String?
    let serial: String?
    let subject: String?
    let localSubject: String?
    let isModified: String?
    let effectiveTime: String?
    let outDate: String?
    let pubDate: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case document = "Document"
        case chapterType = "CHAPTER_TYPE"
        case serial = "Serial"
        case subject = "Subject"
        case localSubject = "Local_Subject"
        case isModified = "IS_MODIFIED"
        case effectiveTime = "Effective_Time"
        case outDate = "Out_Date"
        case pubDate = "Pub_Date"
    }
}

/// Data/JsonPath/NOTAM.JSON 里的平铺文档记录
struct EAIPNotamDocument: Codable {
    let seriesName: String
    let document: String
    let generateTime: String
    let generateTimeEn: String

    enum CodingKeys: String, CodingKey {
        case seriesName = "SeriesName"
        case document = "Document"
        case generateTime = "GenerateTime"
        case generateTimeEn = "GenerateTime_En"
    }
}

// MARK: - 航图类型关键字分类
enum EAIPChartClassifier {
    /// 根据航图名称里的关键字，映射到 App 已有的 SID/STAR/APP/APT/OTHERS 分类
    static func classify(name: String) -> String {
        let upper = name.uppercased()
        if upper.contains("SID") { return "SID" }
        if upper.contains("STAR") { return "STAR" }
        if upper.contains("IAC") || upper.contains("ILS") || upper.contains("VOR")
            || upper.contains("RNP") && upper.contains("APCH")
        {
            return "APP"
        }
        if upper.contains("ADC") || upper.contains("APDC") || upper.contains("AOC")
            || upper.contains("GMC") || upper.contains("PATC") || upper.contains("FDA")
            || upper.contains("WAYPOINT") || upper.contains("CODING TABLE")
        {
            return "APT"
        }
        return "OTHERS"
    }

    /// ENR 6 航路图小节的分类（ENROUTE/AREA/OTHERS）
    static func classifyEnroute(name: String) -> String {
        let upper = name.uppercased()
        if upper.contains("AREA") { return "AREA" }
        if upper.contains("EN-ROUTE CHART") || upper.contains("ENROUTE CHART") { return "ENROUTE" }
        return "OTHERS"
    }
}
