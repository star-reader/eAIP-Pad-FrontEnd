import SwiftUI
import SwiftData
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pinboard 紧凑模式视图（iPhone 底部悬浮条）
struct PinboardCompactView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PinnedChart.pinnedAt, order: .reverse) private var pinnedCharts: [PinnedChart]
    @State private var showingFullPinboard = false
    
    var body: some View {
        if !pinnedCharts.isEmpty {
            VStack {
                Spacer()
                
                HStack {
                    // 左侧快速访问按钮
                    Button {
                        showingFullPinboard = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pin.fill")
                                .foregroundColor(.orange)
                            Text("快速访问")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("(\(pinnedCharts.count))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                    }
                    
                    // 右侧横向滚动的收藏项目
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(pinnedCharts.prefix(5)) { pin in
                                NavigationLink {
                                    PDFReaderView(
                                        chartID: pin.chartID,
                                        displayName: pin.displayName,
                                        documentType: DocumentType(rawValue: pin.documentType) ?? .chart
                                    )
                                } label: {
                                    PinCompactCard(pin: pin)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $showingFullPinboard) {
                PinboardFullView()
            }
        }
    }
}

// MARK: - 紧凑模式收藏卡片
struct PinCompactCard: View {
    let pin: PinnedChart
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 4) {
            // 文档类型图标
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconForDocumentType(pin.documentType))
                    .foregroundColor(.orange)
                    .font(.title3)
            }
            
            // 显示名称
            Text(pin.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 60)
            
            // ICAO 代码
            if !pin.icao.isEmpty {
                Text(pin.icao)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 70)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("移除收藏", systemImage: "pin.slash") {
                modelContext.delete(pin)
                try? modelContext.save()
            }
        }
    }
    
    private func iconForDocumentType(_ type: String) -> String {
        switch type {
        case "chart": return "airplane"
        case "enroute": return "map"
        case "aip": return "doc.text"
        case "sup": return "exclamationmark.triangle"
        case "amdt": return "pencil.and.outline"
        case "notam": return "bell"
        default: return "doc"
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
                    // 空状态
                    VStack(spacing: 16) {
                        Image(systemName: "pin")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("暂无收藏")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("在航图页面点击收藏按钮来添加快速访问")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        documentType: DocumentType(rawValue: pin.documentType) ?? .chart
                    )
                } label: {
                    PinListRow(pin: pin)
                }
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
                            documentType: DocumentType(rawValue: pin.documentType) ?? .chart
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
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(pins) { pin in
                    NavigationLink {
                        PDFReaderView(
                            chartID: pin.chartID,
                            displayName: pin.displayName,
                            documentType: DocumentType(rawValue: pin.documentType) ?? .chart
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
    
    var body: some View {
        HStack {
            // 文档类型图标
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconForDocumentType(pin.documentType))
                    .foregroundColor(.orange)
                    .font(.title3)
            }
            
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
                            .background(.orange.opacity(0.2), in: Capsule())
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
        .padding(.vertical, 4)
    }
    
    private func iconForDocumentType(_ type: String) -> String {
        switch type {
        case "chart": return "airplane"
        case "enroute": return "map"
        case "aip": return "doc.text"
        case "sup": return "exclamationmark.triangle"
        case "amdt": return "pencil.and.outline"
        case "notam": return "bell"
        default: return "doc"
        }
    }
}

// MARK: - 预览卡片视图
struct PinPreviewCard: View {
    let pin: PinnedChart
    
    var body: some View {
        HStack {
            // 缩略图区域
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.orange.opacity(0.1))
                    .frame(width: 80, height: 100)
                
                if let thumbnailData = pin.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 100)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    Image(systemName: iconForDocumentType(pin.documentType))
                        .foregroundColor(.orange)
                        .font(.largeTitle)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(pin.displayName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack {
                    if !pin.icao.isEmpty {
                        Text(pin.icao)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.2), in: Capsule())
                    }
                    
                    Text(DocumentType(rawValue: pin.documentType)?.displayName ?? pin.type)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                Text("收藏于 \(pin.pinnedAt.formatted(.dateTime.month().day()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func iconForDocumentType(_ type: String) -> String {
        switch type {
        case "chart": return "airplane"
        case "enroute": return "map"
        case "aip": return "doc.text"
        case "sup": return "exclamationmark.triangle"
        case "amdt": return "pencil.and.outline"
        case "notam": return "bell"
        default: return "doc"
        }
    }
}

// MARK: - 网格卡片视图
struct PinGridCard: View {
    let pin: PinnedChart
    
    var body: some View {
        VStack(spacing: 12) {
            // 缩略图区域
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.orange.opacity(0.1))
                    .frame(height: 120)
                
                if let thumbnailData = pin.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    Image(systemName: iconForDocumentType(pin.documentType))
                        .foregroundColor(.orange)
                        .font(.largeTitle)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(pin.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if !pin.icao.isEmpty {
                    Text(pin.icao)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func iconForDocumentType(_ type: String) -> String {
        switch type {
        case "chart": return "airplane"
        case "enroute": return "map"
        case "aip": return "doc.text"
        case "sup": return "exclamationmark.triangle"
        case "amdt": return "pencil.and.outline"
        case "notam": return "bell"
        default: return "doc"
        }
    }
}

#Preview("Compact View") {
    PinboardCompactView()
}

#Preview("Full View") {
    PinboardFullView()
}