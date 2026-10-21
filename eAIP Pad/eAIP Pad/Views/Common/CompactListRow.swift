import SwiftUI

// 列表行统一保留充足留白；文字变大时内边距随动态字体缩放。
private struct CompactListRowModifier: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var verticalInset = 12

    func body(content: Content) -> some View {
        content.listRowInsets(
            EdgeInsets(top: verticalInset, leading: 20, bottom: verticalInset, trailing: 20)
        )
    }
}

extension View {
    func compactListRow() -> some View {
        modifier(CompactListRowModifier())
    }
}
