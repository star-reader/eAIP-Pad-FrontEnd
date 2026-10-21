import Foundation
import SwiftData
import SwiftUI

// MARK: - 机场列表视图
struct AirportListView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var airacService = AIRACService.shared
    @Environment(\.selectedAirportBinding) private var selectedAirportBinding
    @State private var searchText = ""
    @StateObject private var page = AIRACPageLoader(initialValue: [AirportResponse]())
    private var airports: [AirportResponse] { page.value }
    private var isLoading: Bool { page.isLoading }
    private var errorMessage: String? { page.errorMessage }

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
                .refreshable { await loadAirports() }
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
        .airacPageTask(key: "\(airacService.dataRevision)") {
            await loadAirports(force: false)
        }
    }

    private func loadAirports(force: Bool = true) async {
        await page.load(key: "\(airacService.dataRevision)", force: force, errorPrefix: "加载机场数据失败：") { [modelContext] in
            let loaded = try await AIRACPackageStore.loadAirports(modelContext: modelContext)
            return loaded.map { $0.toResponse() }
        }
    }
}

// MARK: - 机场行视图
struct AirportRowView: View {
    let airport: AirportResponse

    var body: some View {
        HStack(spacing: 12) {
            AppSymbolView(systemImage: AppSymbols.airport)

            VStack(alignment: .leading, spacing: 4) {
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
