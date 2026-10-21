import Foundation
import ZIPFoundation

nonisolated struct ExtractedAIRACPackage: Sendable {
    let workspaceURL: URL
    let packageURL: URL

    func remove() throws {
        try FileManager.default.removeItem(at: workspaceURL)
    }
}

/// ZIP 只是另一种输入形式；解压后仍交给相同的包解析和事务导入逻辑。
nonisolated struct AIRACArchiveExtractor: Sendable {
    var temporaryDirectory: URL = FileManager.default.temporaryDirectory

    func extract(at archiveURL: URL, progress: Progress) throws -> ExtractedAIRACPackage {
        let workspace = temporaryDirectory.appendingPathComponent("AIRACImport-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        do {
            try Task.checkCancellation()
            let archive = try Archive(url: archiveURL, accessMode: .read)
            for entry in archive {
                try Task.checkCancellation()
                let destination = workspace.appendingPathComponent(entry.path).standardizedFileURL
                guard !entry.path.hasPrefix("/"), !entry.path.contains("\\"),
                    destination.path.hasPrefix(workspace.path + "/"), entry.type != .symlink
                else {
                    throw AIRACPackageError.invalidPackage("ZIP 包含不支持的路径或符号链接：\(entry.path)")
                }
            }
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: archiveURL, to: workspace, progress: progress)
            try Task.checkCancellation()
            let root = try findPackageRoot(in: workspace)
            return ExtractedAIRACPackage(workspaceURL: workspace, packageURL: root)
        } catch {
            if fileManager.fileExists(atPath: workspace.path) { try? fileManager.removeItem(at: workspace) }
            if error is CancellationError || progress.isCancelled { throw CancellationError() }
            throw AIRACPackageError.invalidPackage("ZIP 解压失败：\(error.localizedDescription)")
        }
    }

    private func findPackageRoot(in workspace: URL) throws -> URL {
        let fileManager = FileManager.default
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: workspace, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumerationError = error
                return false
            })
        else { throw AIRACPackageError.invalidPackage("无法读取解压后的文件夹") }

        var roots: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            if url.lastPathComponent == "__MACOSX" {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent == "Data",
                try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            else { continue }
            if fileManager.fileExists(atPath: url.appendingPathComponent("Customers.js").path),
                fileManager.fileExists(atPath: url.appendingPathComponent("JsonPath").path) {
                roots.append(url.deletingLastPathComponent())
                enumerator.skipDescendants()
            }
        }
        if let enumerationError { throw enumerationError }
        guard roots.count == 1, let root = roots.first else {
            throw AIRACPackageError.invalidPackage(roots.isEmpty
                ? "ZIP 中未找到包含 Data/Customers.js 和 Data/JsonPath 的 Web 数据包"
                : "ZIP 中包含多个 AIRAC 数据包，请选择只包含一个周期的 ZIP 文件")
        }
        return root
    }
}
