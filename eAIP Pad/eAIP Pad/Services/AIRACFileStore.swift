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
        // 升级前的文件名没有转义，兼容其中的句点、空格和中文。
        let legacy = versionDirectory(version).appendingPathComponent("\(documentType)_\(id).pdf")
        guard legacy.standardizedFileURL.deletingLastPathComponent() == versionDirectory(version).standardizedFileURL else {
            return nil
        }
        return PDFDocument(url: legacy)
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
            let directory = documentsDirectory.appendingPathComponent(root)
                .appendingPathComponent(AIRACDocumentIdentity.fileComponent(version))
            if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
        }
    }

    func removeRevision(version: String, revision: String) throws {
        try discard(PreparedAIRACCache(version: version, revision: revision, documentCount: 0))
    }

    /// 清理先移走文件，再提交数据库删除；数据库失败时可以原样移回。
    func quarantineAll() throws -> QuarantinedAIRACCache {
        let directory = documentsDirectory.appendingPathComponent(".AIRACTrash")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var moved: [String] = []
        do {
            for name in ["PDFCache", "DataCache"] {
                let source = documentsDirectory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.moveItem(at: source, to: directory.appendingPathComponent(name))
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
            try fileManager.moveItem(
                at: quarantine.directory.appendingPathComponent(name),
                to: documentsDirectory.appendingPathComponent(name))
        }
        try fileManager.removeItem(at: quarantine.directory)
    }

    func finishRemoval(_ quarantine: QuarantinedAIRACCache) throws {
        try fileManager.removeItem(at: quarantine.directory)
    }

    private func versionDirectory(_ version: String) -> URL {
        documentsDirectory.appendingPathComponent("PDFCache")
            .appendingPathComponent(AIRACDocumentIdentity.fileComponent(version))
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
