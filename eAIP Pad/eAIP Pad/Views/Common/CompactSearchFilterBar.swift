import SwiftUI

// 胶囊背景按内容收紧，44pt 点击区域放在背景外，避免把可见控件撑高。
struct CompactCapsuleButtonStyle: ButtonStyle {
    var isSelected = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(
                isSelected ? Color.accentColor : Color.accentColor.opacity(0.12),
                in: Capsule()
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct CompactSearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($isFocused)
                .accessibilityLabel(placeholder)
                .padding(.trailing, text.isEmpty ? 0 : 28)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: Capsule())
        .overlay(alignment: .trailing) {
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}

struct CompactSearchFilterBar<SortOption: Hashable>: View {
    @Binding var searchText: String
    @Binding var selectedSort: SortOption

    let searchPlaceholder: String
    let sortOptions: [SortOption]
    let sortTitle: String
    let sortLabel: (SortOption) -> String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))

        layout {
            CompactSearchField(text: $searchText, placeholder: searchPlaceholder)

            Menu {
                Picker(sortTitle, selection: $selectedSort) {
                    ForEach(sortOptions, id: \.self) { option in
                        Text(sortLabel(option)).tag(option)
                    }
                }
            } label: {
                Label(sortLabel(selectedSort), systemImage: "arrow.up.arrow.down")
                    .font(.subheadline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(minHeight: 34)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                    .background(.thinMaterial, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sortTitle)
            .accessibilityValue(sortLabel(selectedSort))
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
