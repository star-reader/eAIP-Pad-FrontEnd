import SwiftUI
import SwiftData
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 收藏夹视图
struct PinboardView: View {
    @Query private var pinnedCharts: [PinnedChart]
    @Query private var userSettings: [UserSettings]
    @Environment(\.modelContext) private var modelContext
    
    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }
    
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("收藏")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("紧凑模式") {
                                currentSettings.pinboardStyle = PinboardStyle.compact.rawValue
                                try? modelContext.save()
                            }
                            Button("预览模式") {
                                currentSettings.pinboardStyle = PinboardStyle.preview.rawValue
                                try? modelContext.save()
                            }
                            Button("网格模式") {
                                currentSettings.pinboardStyle = PinboardStyle.grid.rawValue
                                try? modelContext.save()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if pinnedCharts.isEmpty {
            ContentUnavailableView(
                "暂无收藏",
                systemImage: "pin.slash",
                description: Text("收藏的航图会显示在这里")
            )
            .foregroundColor(Color.primaryBlue)
        } else {
            switch currentSettings.pinboardStyle {
            case PinboardStyle.compact.rawValue:
                PinboardCompactView()
            case PinboardStyle.preview.rawValue:
                PinboardPreviewGridView()
            case PinboardStyle.grid.rawValue:
                PinboardTaskView()
            default:
                PinboardCompactView()
            }
        }
    }
}

// MARK: - 紧凑样式视图（使用现有的PinboardCompactView）

// MARK: - 预览网格样式视图
struct PinboardPreviewGridView: View {
    @Query private var pinnedCharts: [PinnedChart]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 300))
            ], spacing: 16) {
                ForEach(pinnedCharts, id: \.id) { (chart: PinnedChart) in
                    NavigationLink {
                        // TODO: 打开PDF阅读器
                        Text("航图详情: \(chart.displayName)")
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            // 预览图占位符
                            Rectangle()
                                .fill(Color.primaryBlue.opacity(0.1))
                                .frame(height: 200)
                                .overlay(
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(Color.primaryBlue.opacity(0.3))
                                )
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chart.displayName)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .lineLimit(2)
                                    .foregroundColor(.primary)
                                
                                if !chart.icao.isEmpty {
                                    Text(chart.icao)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Text(chart.type)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primaryBlue.opacity(0.1))
                                        .foregroundColor(Color.primaryBlue)
                                        .cornerRadius(4)
                                    
                                    Spacer()
                                    
                                    Text(chart.pinnedAt, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
    }
}

// MARK: - 任务样式视图
struct PinboardTaskView: View {
    @Query private var pinnedCharts: [PinnedChart]
    
    var body: some View {
        List {
            ForEach(pinnedCharts, id: \.id) { (chart: PinnedChart) in
                NavigationLink {
                    // TODO: 打开PDF阅读器
                    Text("航图详情: \(chart.displayName)")
                } label: {
                    HStack {
                        // 任务状态指示器
                        Circle()
                            .fill(Color.primaryBlue)
                            .frame(width: 8, height: 8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chart.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            
                            HStack {
                                if !chart.icao.isEmpty {
                                    Text(chart.icao)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(chart.type)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(chart.pinnedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: deleteCharts)
        }
        .listStyle(PlainListStyle())
    }
    
    private func deleteCharts(offsets: IndexSet) {
        // TODO: 实现删除功能
    }
}

#Preview("Pinboard - Main") {
    PinboardView()
}

#Preview("Pinboard - Grid") {
    PinboardPreviewGridView()
}

#Preview("Pinboard - Task") {
    PinboardTaskView()
}
