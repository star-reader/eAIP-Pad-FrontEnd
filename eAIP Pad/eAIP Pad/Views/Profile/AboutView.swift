import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Text("eAIP Pad")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("中国eAIP航图阅读器")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("版本 1.0.0 (Build 1)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("主要功能")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureItem(
                                icon: "airplane",
                                title: "完整机场航图库",
                                description: "中国全部AIP公开机场的完整机场航图"
                            )
                            
                            FeatureItem(
                                icon: "map",
                                title: "航路图支持",
                                description: "高清航路图和区域图"
                            )
                            
                            FeatureItem(
                                icon: "pin",
                                title: "快速访问",
                                description: "收藏常用航图，支持多种显示样式"
                            )

                            FeatureItem(
                                icon: "cloud.fill",
                                title: "航图缓存",
                                description: "航图加载后自动本地缓存，下次秒开"
                            )
                            
                            FeatureItem(
                                icon: "arrow.clockwise",
                                title: "自动更新",
                                description: "AIRAC版本自动同步，确保数据最新"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    
                    Button {
                        if let url = URL(string: "https://github.com/star-reader/eAIP-Pad-FrontEnd") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .font(.title3)
                            Text("在 GitHub 上查看源码")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.orange)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    
                    VStack(spacing: 8) {
                        Text("© 2025 eAIP Pad")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("专为中国航空爱好者设计")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview("About") {
    AboutView()
}
