import SwiftUI

struct SheetWideBottomInset<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    init(height: CGFloat = 50, @ViewBuilder content: @escaping () -> Content) {
        self.height = height
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Spacer(minLength: geometry.size.width * 0.1)

                content()
                    .frame(width: geometry.size.width * 0.8)

                Spacer(minLength: geometry.size.width * 0.1)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: height)
        .padding(.bottom, 8)
    }
}
