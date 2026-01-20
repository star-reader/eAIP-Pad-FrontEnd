import Foundation
import SwiftData
import SwiftUI

// MARK: - 机场列表视图
struct AirportListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectedAirportBinding) private var selectedAirportBinding
    @ObservedObject private var authService = AuthenticationService.shared
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
                if filteredAirports.isEmpty {
                    EmptyStateView(
                        title: "暂无机场数据",
                        systemImage: "airplane.circle",
                        description: "没有找到相关机场"
                    )
                } else {
                    List(filteredAirports, id: \.icao) { airport in
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
                    .searchable(text: $searchText, prompt: "搜索机场 ICAO 或名称")
                }
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
            if authService.authenticationState == .authenticated {
                await loadAirports()
            }
        }
        .onChange(of: authService.authenticationState) { _, newValue in
            if newValue == .authenticated {
                Task { await loadAirports() }
            }
        }
    }

    private func loadAirports() async {
        guard authService.authenticationState == .authenticated else { return }
        isLoading = true
        errorMessage = nil

        do {
            guard let airacVersion = await AIRACHelper.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "AirportListView", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }

            if let cached = AIRACHelper.shared.loadCachedData([AirportResponse].self, airacVersion: airacVersion, dataType: PDFCacheService.DataType.airports) {
                airports = cached
                syncAirportsToLocal(cached)
                isLoading = false
                return
            }

            let response = try await NetworkService.shared.getAirports(search: searchText.isEmpty ? nil : searchText)

            if searchText.isEmpty {
                AIRACHelper.shared.cacheData(response, airacVersion: airacVersion, dataType: PDFCacheService.DataType.airports)
            }

            airports = response
            syncAirportsToLocal(response)
        } catch {
            errorMessage = "加载机场数据失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func syncAirportsToLocal(_ airports: [AirportResponse]) {
        for airportResponse in airports {
            // 检查是否已存在
            let existingAirports = try? modelContext.fetch(
                FetchDescriptor<Airport>(
                    predicate: #Predicate { $0.icao == airportResponse.icao }
                )
            )

            if existingAirports?.isEmpty ?? true {
                let airport = Airport(
                    icao: airportResponse.icao,
                    nameEn: airportResponse.nameEn,
                    nameCn: airportResponse.nameCn,
                    hasTerminalCharts: airportResponse.hasTerminalCharts,
                    isModified: airportResponse.isModified ?? false
                )
                modelContext.insert(airport)
            }
        }

        try? modelContext.save()
    }
}

// MARK: - 机场行视图
struct AirportRowView: View {
    let airport: AirportResponse

    var body: some View {
        HStack {
            // 机场图标
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: "airplane")
                    .foregroundColor(.orange)
                    .font(.title3)
            }

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
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AirportListView()
    }
    .modelContainer(for: Airport.self, inMemory: true)
}
