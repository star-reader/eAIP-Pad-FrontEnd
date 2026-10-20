import SwiftUI

// 列表卡片只保留必要留白；文字变大时由内容自然撑高。
private struct CompactListRowModifier: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var verticalInset = 6

    func body(content: Content) -> some View {
        content.listRowInsets(
            EdgeInsets(top: verticalInset, leading: 16, bottom: verticalInset, trailing: 16)
        )
    }
}

extension View {
    func compactListRow() -> some View {
        modifier(CompactListRowModifier())
    }
}
