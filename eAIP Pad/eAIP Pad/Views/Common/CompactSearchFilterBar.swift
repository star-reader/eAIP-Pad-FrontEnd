import SwiftUI

struct CompactSearchFilterBar<SortOption: Hashable>: View {
    @Binding var searchText: String
    @Binding var selectedSort: SortOption

    let searchPlaceholder: String
    let sortOptions: [SortOption]
    let sortTitle: String
    let sortLabel: (SortOption) -> String

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField(searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Menu {
                Picker(sortTitle, selection: $selectedSort) {
                    ForEach(sortOptions, id: \.self) { option in
                        Text(sortLabel(option)).tag(option)
                    }
                }
            } label: {
                toolbarChip(
                    systemImage: "arrow.up.arrow.down.circle",
                    text: sortLabel(selectedSort)
                )
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func toolbarChip(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
