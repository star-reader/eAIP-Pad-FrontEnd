import Foundation
import SwiftUI
import Combine

// MARK: - 全局错误处理器
@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    @Published var currentError: AppError?
    @Published var showError = false
    
    private init() {}
    
    // MARK: - 处理错误
    func handle(_ error: Error, context: String = "") {
        let appError = AppError.from(error)
        
        // 记录错误日志
        let errorMessage = context.isEmpty 
            ? appError.localizedDescription 
            : "\(context): \(appError.localizedDescription)"
        
        LoggerService.shared.error(module: "ErrorHandler", message: errorMessage)
        
        // 显示错误给用户
        currentError = appError
        showError = true
    }
    
    // MARK: - 清除错误
    func clearError() {
        currentError = nil
        showError = false
    }
    
    // MARK: - 获取用户友好的错误信息
    func getUserFriendlyMessage(for error: AppError) -> String {
        return error.localizedDescription
    }
    
    // MARK: - 获取恢复建议
    func getRecoverySuggestion(for error: AppError) -> String? {
        return error.recoverySuggestion
    }
    
    // MARK: - 判断错误是否可重试
    func isRetryable(_ error: AppError) -> Bool {
        return error.isRetryable
    }
}

// MARK: - Environment Key for ErrorHandler
struct ErrorHandlerKey: EnvironmentKey {
    @MainActor
    static var defaultValue: ErrorHandler {
        ErrorHandler.shared
    }
}

extension EnvironmentValues {
    var errorHandler: ErrorHandler {
        get { self[ErrorHandlerKey.self] }
        set { self[ErrorHandlerKey.self] = newValue }
    }
}

// MARK: - 错误展示视图修饰符
struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler
    var onRetry: ((AppError) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert("错误", isPresented: $errorHandler.showError, presenting: errorHandler.currentError) { error in
                if errorHandler.isRetryable(error), let onRetry = onRetry {
                    Button("重试") {
                        onRetry(error)
                        errorHandler.clearError()
                    }
                }
                
                Button("确定", role: .cancel) {
                    errorHandler.clearError()
                }
            } message: { error in
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorHandler.getUserFriendlyMessage(for: error))
                    
                    if let suggestion = errorHandler.getRecoverySuggestion(for: error) {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
    }
}

extension View {
    func errorAlert(errorHandler: ErrorHandler? = nil, onRetry: ((AppError) -> Void)? = nil) -> some View {
        modifier(ErrorAlertModifier(errorHandler: errorHandler ?? ErrorHandler.shared, onRetry: onRetry))
    }
}
