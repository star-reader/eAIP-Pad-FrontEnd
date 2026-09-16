import SwiftUI

struct FeatureIntroSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)

                        Text("本地数据导入")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        Text("APP 数据现已可以从本地导入。按照以下步骤完成数据包导入，即可开始使用。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    featureRow(
                        icon: "person.crop.circle.fill",
                        title: "前往「个人」页面",
                        description: "在底部导航栏选择「个人」，进入应用设置。"
                    )

                    featureRow(
                        icon: "tray.and.arrow.down.fill",
                        title: "导入 AIRAC 数据包",
                        description: "点击「导入 AIRAC 数据包」，选择已下载的官方 EAIP Web 数据包文件夹。"
                    )

                    featureRow(
                        icon: "airplane.circle.fill",
                        title: "离线浏览航空数据",
                        description: "导入完成后，即可离线查看机场、航路、细则和文档等内容。"
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) {
                            confirmAndDismiss()
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", systemImage: "xmark") {
                            confirmAndDismiss()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SheetWideBottomInset {
                    continueButton
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var continueButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                confirmAndDismiss()
            } label: {
                Text("继续")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        } else {
            Button {
                confirmAndDismiss()
            } label: {
                Text("继续")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }

    private func confirmAndDismiss() {
        VersionIntroManager.markIntroAsSeen()
        dismiss()
    }
}

#Preview {
    Color.black.opacity(0.2)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            FeatureIntroSheet()
        }
}
