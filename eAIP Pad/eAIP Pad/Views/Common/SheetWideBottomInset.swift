import SwiftUI

struct SheetWideBottomInset<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .containerRelativeFrame(.horizontal) { width, _ in
                min(width * 0.8, 440)
            }
            .frame(maxWidth: .infinity)
            .font(.headline)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
}
