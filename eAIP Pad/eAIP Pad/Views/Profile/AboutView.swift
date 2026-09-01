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
                        
                        Text(AppVersion.appVersion)
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
                                icon: "internaldrive.fill",
                                title: "完全离线",
                                description: "航图数据全部保存在本机，无需联网即可查阅"
                            )

                            FeatureItem(
                                icon: "tray.and.arrow.down.fill",
                                title: "手动导入",
                                description: "从 EAIP China 官网下载 Web 数据包后手动导入更新"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("数据来源")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "info.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("官方数据源")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text("中国民用航空局 空中交通管理局 航行情报服务中心")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Button {
                                if let url = URL(string: "https://www.eaipchina.cn/") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "globe")
                                        .font(.caption)
                                    Text("访问官方 eAIP 网站")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
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
                        Text("© 2025-\(String(Calendar.current.component(.year, from: Date()))) eAIP Pad")
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
