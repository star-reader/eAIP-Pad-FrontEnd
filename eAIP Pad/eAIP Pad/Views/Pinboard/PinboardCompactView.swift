import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Pinboard 导航栏按钮
struct PinboardToolbarButton: View {
    @Query(sort: \PinnedChart.pinnedAt, order: .reverse) private var pinnedCharts: [PinnedChart]
    @State private var showingPinboard = false

    var body: some View {
        if !pinnedCharts.isEmpty {
            Button {
                showingPinboard = true
            } label: {
                // 使用 overlay 而不是 ZStack，确保角标不被裁剪
                Image(systemName: "pin.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.orange.gradient)
                    .imageScale(.medium)
                    .overlay(alignment: .topTrailing) {
                        if pinnedCharts.count > 0 {
                            Text("\(min(pinnedCharts.count, 99))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Circle().fill(.red))
                                .offset(x: 6, y: -6)
                        }
                    }
                    .padding(8)  // 增加内边距，给角标留出空间
            }
            .accessibilityLabel("快速访问，\(pinnedCharts.count) 个收藏")
            .sheet(isPresented: $showingPinboard) {
                PinboardCompactView()
            }
        }
    }
}

// MARK: - Pinboard 紧凑模式视图（可切换显示模式）
struct PinboardCompactView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PinnedChart.pinnedAt, order: .reverse) private var pinnedCharts: [PinnedChart]
    @Query private var userSettings: [UserSettings]

    private var selectedStyle: PinboardStyle {
        PinboardStyle(rawValue: userSettings.first?.pinboardStyle ?? "") ?? .compact
    }

    private var styleBinding: Binding<PinboardStyle> {
        Binding(get: { selectedStyle }, set: { style in
            let settings: UserSettings
            if let existing = userSettings.first { settings = existing }
            else { settings = UserSettings(); modelContext.insert(settings) }
            settings.pinboardStyle = style.rawValue
            try? modelContext.save()
        })
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Group {
                if pinnedCharts.isEmpty {
                    EmptyStateView(
                        title: "暂无收藏",
                        systemImage: "pin.slash",
                        description: "收藏的航图会显示在这里"
                    )
                } else {
                    // 根据选择的样式显示不同内容
                    switch selectedStyle {
                    case .compact:
                        compactListView
                    case .preview:
                        previewGridView
                    case .grid:
                        taskGridView
                    }
                }
            }
            .navigationTitle("快速访问")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("显示方式", selection: styleBinding) {
                            Label("紧凑列表", systemImage: "list.bullet")
                                .tag(PinboardStyle.compact)
                            Label("预览模式", systemImage: "square.grid.2x2")
                                .tag(PinboardStyle.preview)
                            Label("平铺模式", systemImage: "square.grid.3x3")
                                .tag(PinboardStyle.grid)
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
        }
    }

    // MARK: - 紧凑列表视图
    private var compactListView: some View {
        List {
            ForEach(pinnedCharts) { pin in
                NavigationLink {
                    PDFReaderView(
                        chartID: pin.chartID,
                        displayName: pin.displayName,
                        documentType: DocumentType(rawValue: pin.documentType) ?? .chart,
                        airacVersion: pin.airacVersion
                    )
                } label: {
                    PinCompactListRow(pin: pin)
                }
                .compactListRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("删除", systemImage: "trash") {
                        modelContext.delete(pin)
                        try? modelContext.save()
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 预览网格视图
    private var previewGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16
            ) {
                ForEach(pinnedCharts) { pin in
                    NavigationLink {
                        PDFReaderView(
                            chartID: pin.chartID,
                            displayName: pin.displayName,
                            documentType: DocumentType(rawValue: pin.documentType) ?? .chart,
                            airacVersion: pin.airacVersion
                        )
                    } label: {
                        PinPreviewCard(pin: pin)
                    }
                    .contextMenu {
                        Button("删除", systemImage: "trash", role: .destructive) {
                            modelContext.delete(pin)
                            try? modelContext.save()
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 任务平铺视图
    private var taskGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
                ), spacing: 12
            ) {
                ForEach(pinnedCharts) { pin in
                    NavigationLink {
                        PDFReaderView(
                            chartID: pin.chartID,
                            displayName: pin.displayName,
                            documentType: DocumentType(rawValue: pin.documentType) ?? .chart,
                            airacVersion: pin.airacVersion
                        )
                    } label: {
                        PinGridCard(pin: pin)
                    }
                    .contextMenu {
                        Button("删除", systemImage: "trash", role: .destructive) {
                            modelContext.delete(pin)
                            try? modelContext.save()
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - 紧凑列表行
struct PinCompactListRow: View {
    let pin: PinnedChart

    private var chartTypeColor: Color {
        ChartType(rawValue: pin.type)?.color ?? .gray
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧颜色边框
            Rectangle()
                .fill(chartTypeColor)
                .frame(width: 4)

            HStack(spacing: 12) {
                AppSymbolView(
                    systemImage: pin.documentSymbol, tint: pin.documentSymbolTint, size: .compact
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if !pin.icao.isEmpty {
                            Text(pin.icao)
                                .font(.caption)
                                .foregroundColor(chartTypeColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(chartTypeColor.opacity(0.15), in: Capsule())
                        }

                        Text(pin.type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.leading, 12)
        }
    }
}

// MARK: - Pinboard 完整视图
struct PinboardFullView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]
    @Query(sort: \PinnedChart.pinnedAt, order: .reverse) private var pinnedCharts: [PinnedChart]

    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }

    private var pinboardStyle: PinboardStyle {
        PinboardStyle(rawValue: currentSettings.pinboardStyle) ?? .compact
    }

    var body: some View {
        NavigationStack {
            VStack {
                if pinnedCharts.isEmpty {
                    EmptyStateView(
                        title: "暂无收藏",
                        systemImage: "pin.slash",
                        description: "在航图页面轻点图钉，\n即可将常用航图添加到快速访问。"
                    )
                } else {
                    // 根据样式显示内容
                    switch pinboardStyle {
                    case .compact:
                        PinboardListView(pins: pinnedCharts)
                    case .preview:
                        PinboardPreviewView(pins: pinnedCharts)
                    case .grid:
                        PinboardGridView(pins: pinnedCharts)
                    }
                }
            }
            .navigationTitle("快速访问")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(PinboardStyle.allCases, id: \.self) { style in
                            Button {
                                currentSettings.pinboardStyle = style.rawValue
                                try? modelContext.save()
                            } label: {
                                HStack {
                                    Text(style.displayName)
                                    if pinboardStyle == style {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

// MARK: - 列表样式
struct PinboardListView: View {
    let pins: [PinnedChart]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            ForEach(pins) { pin in
                NavigationLink {
                    PDFReaderView(
                        chartID: pin.chartID,
                        displayName: pin.displayName,
                        documentType: DocumentType(rawValue: pin.documentType) ?? .chart,
                        airacVersion: pin.airacVersion
                    )
                } label: {
                    PinListRow(pin: pin)
                }
                .compactListRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("删除", systemImage: "trash") {
                        modelContext.delete(pin)
                        try? modelContext.save()
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - 预览样式
struct PinboardPreviewView: View {
    let pins: [PinnedChart]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(pins) { pin in
                    NavigationLink {
                        PDFReaderView(
                            chartID: pin.chartID,
                            displayName: pin.displayName,
                            documentType: DocumentType(rawValue: pin.documentType) ?? .chart,
                            airacVersion: pin.airacVersion
                        )
                    } label: {
                        PinPreviewCard(pin: pin)
                    }
                    .contextMenu {
                        Button("移除收藏", systemImage: "pin.slash") {
                            modelContext.delete(pin)
                            try? modelContext.save()
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - 网格样式
struct PinboardGridView: View {
    let pins: [PinnedChart]
    @Environment(\.modelContext) private var modelContext

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(pins) { pin in
                    NavigationLink {
                        PDFReaderView(
                            chartID: pin.chartID,
                            displayName: pin.displayName,
                            documentType: DocumentType(rawValue: pin.documentType) ?? .chart,
                            airacVersion: pin.airacVersion
                        )
                    } label: {
                        PinGridCard(pin: pin)
                    }
                    .contextMenu {
                        Button("移除收藏", systemImage: "pin.slash") {
                            modelContext.delete(pin)
                            try? modelContext.save()
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - 列表行视图
struct PinListRow: View {
    let pin: PinnedChart

    private var chartTypeColor: Color {
        ChartType(rawValue: pin.type)?.color ?? .gray
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧颜色边框
            Rectangle()
                .fill(chartTypeColor)
                .frame(width: 4)

            HStack(spacing: 12) {
                AppSymbolView(systemImage: pin.documentSymbol, tint: pin.documentSymbolTint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    HStack {
                        if !pin.icao.isEmpty {
                            Text(pin.icao)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(chartTypeColor.opacity(0.2), in: Capsule())
                                .foregroundColor(chartTypeColor)
                        }

                        Text(DocumentType(rawValue: pin.documentType)?.displayName ?? pin.type)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(pin.pinnedAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.leading, 12)
        }
    }
}

// MARK: - 预览卡片视图
struct PinPreviewCard: View {
    let pin: PinnedChart

    private var chartTypeColor: Color {
        ChartType(rawValue: pin.type)?.color ?? .gray
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧颜色边框
            Rectangle()
                .fill(chartTypeColor)
                .frame(width: 4)

            HStack(spacing: 12) {
                // 小图标
                Group {
                    if let thumbnailData = pin.thumbnailData,
                        let uiImage = UIImage(data: thumbnailData)
                    {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    } else {
                        AppSymbolView(systemImage: pin.documentSymbol, tint: pin.documentSymbolTint)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        if !pin.icao.isEmpty {
                            Text(pin.icao)
                                .font(.caption)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(chartTypeColor.opacity(0.15), in: Capsule())
                                .foregroundColor(chartTypeColor)
                        }

                        Text(DocumentType(rawValue: pin.documentType)?.displayName ?? pin.type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(pin.pinnedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 76)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 网格卡片视图
struct PinGridCard: View {
    let pin: PinnedChart

    private var chartTypeColor: Color {
        ChartType(rawValue: pin.type)?.color ?? .gray
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部颜色边框
            Rectangle()
                .fill(chartTypeColor)
                .frame(height: 4)

            VStack(spacing: 8) {
                // 小图标区域
                Group {
                    if let thumbnailData = pin.thumbnailData,
                        let uiImage = UIImage(data: thumbnailData)
                    {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        AppSymbolView(
                            systemImage: pin.documentSymbol, tint: pin.documentSymbolTint, size: .large
                        )
                    }
                }

                VStack(alignment: .center, spacing: 6) {
                    Text(pin.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    if !pin.icao.isEmpty {
                        Text(pin.icao)
                            .font(.caption2)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(chartTypeColor.opacity(0.15), in: Capsule())
                            .foregroundColor(chartTypeColor)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 120, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Compact View") {
    PinboardCompactView()
}

#Preview("Full View") {
    PinboardFullView()
}
