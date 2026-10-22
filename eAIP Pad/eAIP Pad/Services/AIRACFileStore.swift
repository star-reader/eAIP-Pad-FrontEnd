import Foundation
import PDFKit

nonisolated struct PreparedAIRACCache: Sendable {
    let version: String
    let revision: String
    let documentCount: Int
}

nonisolated struct QuarantinedAIRACCache: Sendable {
    let directory: URL
    let movedDirectories: [String]
}

/// 每次导入写入独立目录；数据库提交前，阅读器始终使用原来的缓存版本。
nonisolated final class AIRACFileStore: Sendable {
    static let shared = AIRACFileStore()

    let documentsDirectory: URL
    private let writePDF: @Sendable (Data, URL) throws -> Void
    private var fileManager: FileManager { .default }

    init(
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
        writePDF: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.documentsDirectory = documentsDirectory
        self.writePDF = writePDF
    }

    func cacheURL(version: String, revision: String?, documentType: String, id: String) -> URL {
        var directory = versionDirectory(version)
        if let revision { directory.appendPathComponent(AIRACDocumentIdentity.fileComponent(revision)) }
        let name = "\(documentType)_\(AIRACDocumentIdentity.fileComponent(id)).pdf"
        return directory.appendingPathComponent(name)
    }

    func loadPDF(version: String, revision: String?, documentType: String, id: String) -> PDFDocument? {
        let url = cacheURL(version: version, revision: revision, documentType: documentType, id: id)
        if let document = PDFDocument(url: url) { return document }
        guard revision == nil else { return nil }
        // 旧版的周期目录和文件名都没有转义，例如 2026-09.V1；仅兼容没有事务 revision 的缓存。
        let names = ["\(documentType)_\(AIRACDocumentIdentity.fileComponent(id)).pdf", "\(documentType)_\(id).pdf"]
        for directory in versionDirectories(version, root: "PDFCache") {
            for name in names {
                let candidate = directory.appendingPathComponent(name)
                guard isDirectChild(candidate, of: directory), fileManager.fileExists(atPath: candidate.path) else { continue }
                if let document = PDFDocument(url: candidate) { return document }
            }
        }
        return nil
    }

    func savePDF(_ data: Data, version: String, revision: String?, documentType: String, id: String) throws {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw AIRACPackageError.invalidPDF("\(documentType)_\(id)")
        }
        let destination = cacheURL(version: version, revision: revision, documentType: documentType, id: id)
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writePDF(data, destination)
        } catch {
            throw AIRACPackageError.fileOperation(destination.lastPathComponent, error.localizedDescription)
        }
    }

    func prepare(_ parsed: ParsedAIRACPackage, from folderURL: URL) throws -> PreparedAIRACCache {
        let prepared = PreparedAIRACCache(
            version: parsed.version, revision: UUID().uuidString, documentCount: parsed.charts.count)
        do {
            for chart in parsed.charts {
                try Task.checkCancellation()
                try autoreleasepool {
                    guard let path = chart.pdfPath, !path.isEmpty else {
                        throw AIRACPackageError.missingPDF(chart.readerID)
                    }
                    let source = try sourceURL(path, in: folderURL)
                    guard fileManager.fileExists(atPath: source.path) else {
                        throw AIRACPackageError.missingPDF(path)
                    }
                    let data: Data
                    do {
                        data = try Data(contentsOf: source, options: .mappedIfSafe)
                    } catch {
                        throw AIRACPackageError.fileOperation(path, error.localizedDescription)
                    }
                    try savePDF(
                        data, version: parsed.version, revision: prepared.revision,
                        documentType: chart.documentType, id: chart.cacheDocumentID)
                }
            }
            return prepared
        } catch {
            try? discard(prepared)
            throw error
        }
    }

    func discard(_ prepared: PreparedAIRACCache) throws {
        let directory = versionDirectory(prepared.version)
            .appendingPathComponent(AIRACDocumentIdentity.fileComponent(prepared.revision))
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
    }

    func removeVersion(_ version: String) throws {
        for root in ["PDFCache", "DataCache"] {
            for directory in versionDirectories(version, root: root) {
                if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
            }
        }
    }

    func removeRevision(version: String, revision: String) throws {
        try discard(PreparedAIRACCache(version: version, revision: revision, documentCount: 0))
    }

    /// 清理先移走文件，再提交数据库删除；数据库失败时可以原样移回。
    func quarantineAll() throws -> QuarantinedAIRACCache {
        try quarantine(paths: ["PDFCache", "DataCache"])
    }

    func quarantineVersions(_ versions: [String]) throws -> QuarantinedAIRACCache {
        let paths = ["PDFCache", "DataCache"].flatMap { root in
            versions.flatMap { version in
                versionDirectories(version, root: root).map { "\(root)/\($0.lastPathComponent)" }
            }
        }
        return try quarantine(paths: Array(Set(paths)).sorted())
    }

    private func quarantine(paths: [String]) throws -> QuarantinedAIRACCache {
        let directory = documentsDirectory.appendingPathComponent(".AIRACTrash")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var moved: [String] = []
        do {
            for name in paths {
                let source = documentsDirectory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: source.path) {
                    let destination = directory.appendingPathComponent(name)
                    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.moveItem(at: source, to: destination)
                    moved.append(name)
                }
            }
        } catch {
            let quarantine = QuarantinedAIRACCache(directory: directory, movedDirectories: moved)
            do { try restore(quarantine) }
            catch { throw AIRACPackageError.fileOperation("恢复缓存", error.localizedDescription) }
            throw error
        }
        return QuarantinedAIRACCache(directory: directory, movedDirectories: moved)
    }

    func restore(_ quarantine: QuarantinedAIRACCache) throws {
        for name in quarantine.movedDirectories {
            try fileManager.createDirectory(
                at: documentsDirectory.appendingPathComponent(name).deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try fileManager.moveItem(
                at: quarantine.directory.appendingPathComponent(name),
                to: documentsDirectory.appendingPathComponent(name))
        }
        try fileManager.removeItem(at: quarantine.directory)
    }

    func finishRemoval(_ quarantine: QuarantinedAIRACCache) throws {
        try fileManager.removeItem(at: quarantine.directory)
    }

    /// 扫描不创建目录；仅在后台读取文件大小，避免个人页阻塞主线程。
    func totalCacheSize() throws -> Int64 {
        var size: Int64 = 0
        for name in ["PDFCache", "DataCache"] {
            let root = documentsDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(at: root,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { continue }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values.isRegularFile == true { size += Int64(values.fileSize ?? 0) }
            }
        }
        return size
    }

    private func versionDirectory(_ version: String) -> URL {
        documentsDirectory.appendingPathComponent("PDFCache")
            .appendingPathComponent(AIRACDocumentIdentity.fileComponent(version))
    }

    private func versionDirectories(_ version: String, root name: String) -> [URL] {
        let root = documentsDirectory.appendingPathComponent(name)
        let current = root.appendingPathComponent(AIRACDocumentIdentity.fileComponent(version))
        let legacy = root.appendingPathComponent(version)
        guard legacy != current, isDirectChild(legacy, of: root) else { return [current] }
        return [current, legacy]
    }

    private func isDirectChild(_ url: URL, of directory: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL
            && url.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
                == directory.resolvingSymlinksInPath().standardizedFileURL
    }

    private func sourceURL(_ path: String, in folder: URL) throws -> URL {
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let source = root.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard source.path.hasPrefix(root.path + "/") else {
            throw AIRACPackageError.invalidPackage("PDF 路径超出所选数据包：\(path)")
        }
        return source
    }
}
