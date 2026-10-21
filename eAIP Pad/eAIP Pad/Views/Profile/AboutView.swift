import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    appHeader

                    AboutSection(title: "主要功能") {
                        featureRow(icon: "airplane", title: "机场航图",
                            description: "按机场浏览航图与 AD 细则")
                        rowDivider
                        featureRow(icon: "map", title: "航路与区域图",
                            description: "分类查阅航路图和区域图")
                        rowDivider
                        featureRow(icon: "pin", title: "快速访问",
                            description: "收藏常用航图，切换多种显示样式")
                        rowDivider
                        featureRow(icon: "internaldrive.fill", title: "离线浏览",
                            description: "本地导入或复制后，可离线查阅")
                        rowDivider
                        featureRow(icon: "tray.and.arrow.down.fill", title: "数据导入",
                            description: "支持 ZIP、文件夹与在线服务器")
                    }

                    AboutSection(title: "数据来源") {
                        VStack(spacing: 20) {
                            FeatureItem(icon: "info.circle.fill", title: "官方数据源",
                                description: "中国民用航空局空中交通管理局航行情报服务中心")
                            officialWebsiteLink
                        }
                        .padding(20)
                    }

                    sourceCodeLink

                    Text("© 2025–\(String(Calendar.current.component(.year, from: Date()))) eAIP Pad")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if #available(iOS 26.0, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var appHeader: some View {
        VStack(spacing: 16) {
            StateSymbolView(systemImage: AppSymbols.airport)
            VStack(spacing: 8) {
                Text("eAIP Pad")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("中国 eAIP 航图阅读器")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(AppVersion.appVersion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .modifier(StateEntranceModifier())
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        FeatureItem(icon: icon, title: title, description: description)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 64).padding(.trailing, 20)
    }

    @ViewBuilder
    private var officialWebsiteLink: some View {
        if #available(iOS 26.0, *) {
            websiteLink.buttonStyle(.glass)
        } else {
            websiteLink.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var websiteLink: some View {
        if let url = URL(string: "https://www.eaipchina.cn/") {
            Link(destination: url) {
                HStack(spacing: 10) {
                    Label("访问官方 eAIP 网站", systemImage: "globe")
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .tint(.blue)
        }
    }

    @ViewBuilder
    private var sourceCodeLink: some View {
        if let url = URL(string: "https://github.com/star-reader/eAIP-Pad-FrontEnd") {
            Link(destination: url) {
                HStack(spacing: 14) {
                    AppSymbolView(systemImage: "link")
                    Text("在 GitHub 上查看源码")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AboutSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

private struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            AppSymbolView(systemImage: icon)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("About") {
    AboutView()
}
