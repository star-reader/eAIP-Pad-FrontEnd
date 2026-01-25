import SwiftUI

struct StatisticRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

struct SettingRow: View {
    let icon: String
    let title: String
    let color: Color
    var trailingText: String? = nil
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            if let trailingText = trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview("StatisticRow") {
    List {
        StatisticRow(
            icon: "pin.fill",
            title: "收藏航图",
            value: "12 个",
            color: .orange
        )
        
        StatisticRow(
            icon: "arrow.clockwise",
            title: "当前AIRAC",
            value: "2501",
            color: .blue
        )
    }
}

#Preview("SettingRow") {
    List {
        SettingRow(
            icon: "gearshape.fill",
            title: "偏好设置",
            color: .gray
        )
        
        SettingRow(
            icon: "trash.fill",
            title: "清理缓存",
            color: .red,
            trailingText: "125 MB"
        )
    }
}
