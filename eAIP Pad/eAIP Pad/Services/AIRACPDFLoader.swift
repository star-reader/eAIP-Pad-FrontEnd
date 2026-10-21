import Foundation
import PDFKit

/// PDFKit 尚未声明 Sendable。后台完成初始化后只向阅读器移交一次，后台不再访问该对象。
nonisolated struct LoadedAIRACPDF: @unchecked Sendable {
    let document: PDFDocument
}

nonisolated enum AIRACPDFLoader {
    @concurrent
    static func decode(_ data: Data, id: String) async throws -> LoadedAIRACPDF {
        try Task.checkCancellation()
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw AIRACPackageError.invalidPDF(id)
        }
        try Task.checkCancellation()
        return LoadedAIRACPDF(document: document)
    }

    @concurrent
    static func load(
        version: String, revision: String?, documentType: String, id: String, legacyID: String,
        files: AIRACFileStore
    ) async throws -> LoadedAIRACPDF {
        try Task.checkCancellation()
        var document = files.loadPDF(version: version, revision: revision, documentType: documentType, id: id)
        if document == nil, revision == nil {
            document = files.loadPDF(version: version, revision: nil, documentType: documentType, id: legacyID)
        }
        try Task.checkCancellation()
        guard let document, document.pageCount > 0 else { throw AIRACPackageError.missingPDF(id) }
        return LoadedAIRACPDF(document: document)
    }
}
