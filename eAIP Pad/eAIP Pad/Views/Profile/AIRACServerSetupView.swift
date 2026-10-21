import SwiftData
import SwiftUI

struct AIRACServerSetupView: View {
    private enum Step { case address, mode, initializing, complete }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var airacService = AIRACService.shared
    @State private var step: Step = .address
    @State private var address = ""
    @State private var mode: AIRACServerMode = .copy
    @State private var verifiedVersion: String?
    @State private var verifiedDate: Date?
    @State private var isVerifying = false
    @State private var errorMessage: String?
    let onCompleted: () -> Void

    private var isBusy: Bool { isVerifying || step == .initializing }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    stepHeader
                        .id(step)
                        .transition(.opacity)
                        .padding(.vertical, 24)
                    stepContent
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("在线服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step == .mode, !isBusy {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("上一步", systemImage: "chevron.left") {
                            errorMessage = nil
                            step = .address
                        }
                    }
                }
                if !isBusy {
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .close, action: close)
                        }
                    } else {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("关闭", action: close)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if step != .initializing {
                    SheetWideBottomInset {
                        if #available(iOS 26.0, *) {
                            nextButton.buttonStyle(.glassProminent)
                        } else {
                            nextButton.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
            .task {
                guard address.isEmpty,
                    let current = try? AIRACPackageStore.currentVersion(modelContext: modelContext),
                    let savedAddress = current.serverURL else { return }
                address = savedAddress
                mode = current.source == AIRACServerMode.request.source ? .request : .copy
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isBusy)
    }

    private var stepHeader: some View {
        Group {
            switch step {
            case .address:
                StateMessageContent(title: "连接在线服务器", systemImage: "network",
                    description: "填写官方 eAIP Web 数据包的在线地址。")
            case .mode:
                StateMessageContent(title: "选择导入方式", systemImage: "arrow.down.to.line",
                    description: "已连接 AIRAC \(verifiedVersion ?? "")")
            case .initializing:
                StateMessageContent(title: mode == .copy ? "正在复制资料" : "正在配置请求",
                    systemImage: mode == .copy ? "arrow.down.to.line" : "network",
                    description: mode == .copy ? "复制耗时较长，请保持应用开启。" : "正在校验目录并保存服务器配置。")
            case .complete:
                StateMessageContent(title: "配置完成", systemImage: "checkmark.circle.fill",
                    description: mode == .copy ? "全部资料已复制到本地，可以离线浏览。" : "浏览列表和航图时，将从服务器实时获取资料。", tint: .green)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .address:
            VStack(alignment: .leading, spacing: 12) {
                Text("服务器地址")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                TextField("https://example.com/eaip/", text: $address, axis: .vertical)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .disabled(isVerifying)
                    .onSubmit { advance() }
                    .padding(20)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                Text("填写含 index.html 和 Data 目录的数据包根目录（HTTPS）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        case .mode:
            VStack(spacing: 0) {
                modeRow(.copy, image: "square.and.arrow.down",
                    description: "全部复制，支持离线（耗时较长）")
                Divider().padding(.leading, 68)
                modeRow(.request, image: "network",
                    description: "按需加载列表与航图，需联网")
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        case .initializing:
            VStack(spacing: 12) {
                ProgressView(value: airacService.updateProgress)
                    .accessibilityLabel("初始化进度")
                Text(airacService.updateProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(airacService.updateMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 340)
        case .complete:
            EmptyView()
        }
    }

    private func modeRow(_ value: AIRACServerMode, image: String, description: String) -> some View {
        Button { mode = value } label: {
            HStack(spacing: 14) {
                Image(systemName: image)
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.blue.gradient)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value.title).font(.headline).foregroundStyle(.primary)
                    Text(description).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: mode == value ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(mode == value ? .blue : Color.secondary.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }

    private var nextButton: some View {
        Button(action: advance) {
            Text(isVerifying ? "正在验证" : step == .complete ? "完成" : step == .mode ? "完成配置" : "下一步")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                // 进度图标不参与按钮布局，验证态始终沿用「下一步」的自然高度。
                .overlay(alignment: .leading) {
                    if isVerifying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .frame(width: 20, height: 20)
                            .padding(.leading, 16)
                            .accessibilityHidden(true)
                    }
                }
        }
        .disabled(isBusy || (step == .address && address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }

    private func advance() {
        guard !isBusy else { return }
        if step == .complete { onCompleted(); return }
        errorMessage = nil
        if step == .address {
            isVerifying = true
            Task {
                defer { isVerifying = false }
                do {
                    let configuration = try AIRACServerConfiguration(address: address, mode: mode)
                    let parsed = try await AIRACServerClient.shared.catalog(from: configuration)
                    verifiedVersion = parsed.version
                    verifiedDate = parsed.effectiveDate
                    address = configuration.rootURL.absoluteString
                    step = .mode
                } catch { errorMessage = error.localizedDescription }
            }
        } else if step == .mode {
            guard let verifiedVersion, let verifiedDate else { step = .address; return }
            do {
                let configuration = try AIRACServerConfiguration(address: address, mode: mode)
                step = .initializing
                Task {
                    if await airacService.configureServer(configuration,
                        expectedVersion: verifiedVersion, expectedDate: verifiedDate, modelContext: modelContext) {
                        step = .complete
                    } else {
                        errorMessage = airacService.errorMessage
                        step = .mode
                    }
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func close() {
        if step == .complete { onCompleted() }
        else { dismiss() }
    }
}
