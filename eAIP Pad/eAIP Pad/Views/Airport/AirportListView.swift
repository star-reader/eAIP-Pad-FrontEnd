import Foundation
import SwiftData
import SwiftUI

// MARK: - 机场列表视图
struct AirportListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectedAirportBinding) private var selectedAirportBinding
    @Query private var localAirports: [Airport]
    @State private var searchText = ""
    @State private var airports: [AirportResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // 过滤后的机场列表
    private var filteredAirports: [AirportResponse] {
        if searchText.isEmpty {
            return airports
        } else {
            return airports.filter { airport in
                airport.icao.localizedCaseInsensitiveContains(searchText)
                    || airport.nameEn.localizedCaseInsensitiveContains(searchText)
                    || airport.nameCn.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            LoadingStateView(
                isLoading: isLoading,
                errorMessage: errorMessage,
                loadingMessage: "加载机场数据...",
                retryAction: { await loadAirports() }
            ) {
                List {
                    ForEach(filteredAirports, id: \.icao) { airport in
                        if let binding = selectedAirportBinding {
                            Button {
                                binding.wrappedValue = airport
                            } label: {
                                AirportRowView(airport: airport)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                AirportDetailView(airport: airport)
                            } label: {
                                AirportRowView(airport: airport)
                            }
                        }
                    }
                    .compactListRow()
                }
                .scrollContentBackground(filteredAirports.isEmpty ? .hidden : .automatic)
                .overlay {
                    if filteredAirports.isEmpty {
                        SearchEmptyStateView(
                            searchText: $searchText,
                            title: "暂无机场数据",
                            systemImage: "airplane",
                            description: "当前数据包中没有机场信息。"
                        )
                    }
                }
                .searchable(text: $searchText, prompt: "搜索机场 ICAO 或名称")
            }
            .navigationTitle("机场")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        PinboardToolbarButton()

                        Button {
                            Task {
                                await loadAirports()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .task {
            await loadAirports()
        }
    }

    private func loadAirports() async {
        isLoading = true
        errorMessage = nil

        do {
            guard
                await AIRACHelper.shared.getCurrentAIRACVersion(modelContext: modelContext) != nil
            else {
                throw AIRACHelper.makeMissingDataError()
            }

            let descriptor = FetchDescriptor<Airport>(
                sortBy: [SortDescriptor(\.icao)])
            let localAirports = try modelContext.fetch(descriptor)
            airports = localAirports.map { $0.toResponse() }
        } catch {
            errorMessage = "加载机场数据失败: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - 机场行视图
struct AirportRowView: View {
    let airport: AirportResponse

    var body: some View {
        HStack(spacing: 12) {
            AppSymbolView(systemImage: AppSymbols.airport)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(airport.icao)
                        .font(.headline)
                        .fontWeight(.semibold)

                    // 更新提示 - 橙色小圆点
                    if airport.isModified == true {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                    }
                }

                Text(airport.nameCn)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Text(airport.nameEn)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        AirportListView()
    }
    .modelContainer(for: Airport.self, inMemory: true)
}
