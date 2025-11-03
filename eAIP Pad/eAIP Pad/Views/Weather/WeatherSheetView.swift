import SwiftUI
import Foundation

struct WeatherSheetView: View {
    let icao: String
    let airportNameCn: String
    let airportNameEn: String
    
    @State private var selection: Int = 0 // 0: METAR, 1: TAF
    @State private var isLoadingMetar = true
    @State private var isLoadingTaf = true
    @State private var metarError: String?
    @State private var tafError: String?
    @State private var metar: METARResponse?
    @State private var taf: TAFResponse?
    
    var body: some View {
        VStack(spacing: 0) {
                header
                
                Picker("Weather", selection: $selection) {
                    Text("METAR").tag(0)
                    Text("TAF").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // 添加内容视图
                TabView(selection: $selection) {
                    metarView.tag(0)
                    tafView.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.default, value: selection)
        }
        .onAppear {
            Task { await loadMETAR() }
            Task { await loadTAF() }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var header: some View {
        HStack(alignment: .center) {
            // VStack(alignment: .leading, spacing: 4) {
            //     Text("\(airportNameCn) • \(icao)")
            //         .font(.headline)
            //     Text(airportNameEn)
            //         .font(.subheadline)
            //         .foregroundColor(.secondary)
            // }
            Spacer()
            Button {
                Task {
                    await loadMETAR()
                    await loadTAF()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoadingMetar || isLoadingTaf)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    private var metarView: some View {
        Group {
            if isLoadingMetar {
                ProgressView("加载 METAR...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if metarError != nil {
                EmptyStateView(title: "暂无 METAR 数据")
            } else if let metar = metar {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 主信息
                        VStack(alignment: .leading, spacing: 6) {
                            Text("METAR")
                                .font(.title3).bold()
                            if let obs = clean(metar.observationTime) {
                                Text("观测时间: \(obs)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        
                        // 详细列表
                        let baseItems: [(String, String?)] = [
                            ("风向", clean(metar.windDirection)),
                            ("风速", clean(metar.windSpeed)),
                            ("能见度", clean(metar.visibility)),
                            ("温度", clean(metar.temperature)),
                            ("露点", clean(metar.dewpoint)),
                            ("QNH", clean(metar.qnh)),
                            ("天气现象", clean(metar.weather))
                        ]
                        let cloudItems: [(String, String?)] = (metar.clouds ?? [])
                            .compactMap { clean($0) }
                            .enumerated()
                            .map { (idx, val) in ("云况\(idx+1)", val) }
                        let allItems = baseItems + cloudItems
                        if allItems.contains(where: { ($0.1 ?? "").isEmpty == false }) {
                            WeatherDetailList(items: allItems)
                        } else if clean(metar.raw) == nil {
                            EmptyStateView(title: "暂无 METAR 数据")
                                .padding(.horizontal)
                        }
                        
                        // 原始报文
                        if let raw = clean(metar.raw) {
                            WeatherRawSection(title: "原始报文", raw: raw)
                        }
                    }
                    .padding(.vertical, 12)
                }
            } else {
                EmptyStateView(title: "暂无 METAR 数据")
            }
        }
    }
    
    private var tafView: some View {
        Group {
            if isLoadingTaf {
                ProgressView("加载 TAF...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tafError != nil {
                EmptyStateView(title: "暂无 TAF 数据")
            } else if let taf = taf {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 主信息
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TAF")
                                .font(.title3).bold()
                            HStack(spacing: 12) {
                                if let issue = clean(taf.issueTime) {
                                    Text("发布时间: \(issue)")
                                }
                                if let vf = clean(taf.validFrom), let vt = clean(taf.validTo) {
                                    Text("有效: \(vf) → \(vt)")
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        // 分时段预报
                        if let forecasts = taf.forecasts, !forecasts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(forecasts, id: \.self) { period in
                                    let timeFrom = clean(period.timeFrom)
                                    let timeTo = clean(period.timeTo)
                                    let items: [(String, String?)] = [
                                        ("风", clean(period.wind)),
                                        ("能见度", clean(period.visibility)),
                                        ("天气现象", clean(period.weather))
                                    ] + (period.clouds ?? [])
                                        .compactMap { clean($0) }
                                        .enumerated()
                                        .map { (idx, val) in ("云况\(idx+1)", val) }
                                    let hasAny = items.contains { ($0.1 ?? "").isEmpty == false }
                                    if hasAny || timeFrom != nil || timeTo != nil {
                                    VStack(alignment: .leading, spacing: 6) {
                                            if let tf = timeFrom, let tt = timeTo {
                                                Text("\(tf) → \(tt)")
                                                    .font(.subheadline).bold()
                                            } else if let tf = timeFrom {
                                                Text(tf)
                                                    .font(.subheadline).bold()
                                            }
                                            if hasAny {
                                                WeatherDetailList(items: items)
                                            }
                                    }
                                    .padding()
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            .padding(.horizontal)
                        } else if clean(taf.raw) == nil {
                            EmptyStateView(title: "暂无 TAF 数据")
                                .padding(.horizontal)
                        }
                        
                        // 原始报文
                        if let raw = clean(taf.raw) {
                            WeatherRawSection(title: "原始报文", raw: raw)
                        }
                    }
                    .padding(.vertical, 12)
                }
            } else {
                EmptyStateView(title: "暂无 TAF 数据")
            }
        }
    }
    
    private func loadMETAR() async {
        await MainActor.run {
            isLoadingMetar = true
            metarError = nil
            metar = nil
        }
        do {
            let result = try await NetworkService.shared.getMETAR(icao: icao)
            await MainActor.run { self.metar = result }
        } catch {
            // 按需求：失败不展示错误，仅展示暂无数据
            await MainActor.run {
                self.metarError = "error"
                self.metar = nil
            }
        }
        await MainActor.run { self.isLoadingMetar = false }
    }
    
    private func loadTAF() async {
        await MainActor.run {
            isLoadingTaf = true
            tafError = nil
            taf = nil
        }
        do {
            let result = try await NetworkService.shared.getTAF(icao: icao)
            await MainActor.run { self.taf = result }
        } catch {
            // 按需求：失败不展示错误，仅展示暂无数据
            await MainActor.run {
                self.tafError = "error"
                self.taf = nil
            }
        }
        await MainActor.run { self.isLoadingTaf = false }
    }
}

// 清洗空字符串/N-A 等无效值
private func clean(_ value: String?) -> String? {
    guard let raw = value else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    let upper = trimmed.uppercased()
    if upper == "N/A" || upper == "NA" || trimmed == "-" { return nil }
    return trimmed
}

private struct WeatherDetailList: View {
    let items: [(String, String?)]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                let item = items[idx]
                if let value = item.1, !value.isEmpty {
                    HStack {
                        Text(item.0)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(value)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    if idx < items.count - 1 { Divider().padding(.leading) }
                }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

private struct EmptyStateView: View {
    let title: String
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cloud.fill").font(.largeTitle).foregroundColor(.secondary)
            Text(title).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct WeatherRawSection: View {
    let title: String
    let raw: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(raw)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal)
    }
}

private struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.bolt.rain.fill").font(.largeTitle).foregroundColor(.orange)
            Text(message).multilineTextAlignment(.center)
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}


