import PDFKit

/// 每个阅读器保存自己的原始页面方向，旋转量只作为相对于原始 PDF 的增量。
@MainActor
final class PDFDocumentRotation {
    private weak var document: PDFDocument?
    private var originalAngles: [Int] = []
    private var appliedOffset = 0

    @discardableResult
    func apply(_ offset: Int, to document: PDFDocument) -> Bool {
        if self.document !== document {
            self.document = document
            originalAngles = (0..<document.pageCount).map { document.page(at: $0)?.rotation ?? 0 }
            appliedOffset = 0
        }
        let normalized = (offset % 360 + 360) % 360
        guard normalized != appliedOffset else { return false }
        for (index, angle) in originalAngles.enumerated() {
            document.page(at: index)?.rotation = ((angle + normalized) % 360 + 360) % 360
        }
        appliedOffset = normalized
        return true
    }
}
