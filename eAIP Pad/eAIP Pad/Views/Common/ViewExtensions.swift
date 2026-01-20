import SwiftUI

// MARK: - 加载状态视图修饰符
struct LoadingViewModifier: ViewModifier {
    let isLoading: Bool
    let message: String
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isLoading ? 0 : 1)
            
            if isLoading {
                ProgressView(message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

extension View {
    /// 添加加载遮罩层
    func loadingOverlay(isLoading: Bool, message: String = "加载中...") -> some View {
        self.modifier(LoadingViewModifier(isLoading: isLoading, message: message))
    }
}

// MARK: - 错误处理视图修饰符
struct CustomErrorAlertModifier: ViewModifier {
    @Binding var errorMessage: String?
    let retryAction: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert("错误", isPresented: .constant(errorMessage != nil)) {
                if let retry = retryAction {
                    Button("重试") {
                        retry()
                    }
                }
                Button("确定", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
    }
}

extension View {
    /// 添加错误弹窗
    func customErrorAlert(errorMessage: Binding<String?>, retryAction: (() -> Void)? = nil) -> some View {
        self.modifier(CustomErrorAlertModifier(errorMessage: errorMessage, retryAction: retryAction))
    }
}
