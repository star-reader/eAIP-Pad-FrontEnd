import Foundation
import Combine

// MARK: - 基础 ViewModel 协议
@MainActor
protocol BaseViewModel: ObservableObject {
    var isLoading: Bool { get set }
    var errorMessage: String? { get set }
}

// MARK: - 可加载数据的 ViewModel 协议
@MainActor
protocol LoadableViewModel: BaseViewModel {
    associatedtype DataType
    var data: DataType { get set }
    func loadData() async
    func retry() async
}

// MARK: - 基础 ViewModel 实现
@MainActor
class BaseViewModelImpl: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    /// 执行异步操作并处理加载状态和错误
    func performAsync<T>(
        _ operation: () async throws -> T,
        onSuccess: ((T) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await operation()
            isLoading = false
            onSuccess?(result)
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            onError?(error)
            LoggerService.shared.error(
                module: String(describing: type(of: self)),
                message: "操作失败: \(error.localizedDescription)"
            )
        }
    }
    
    /// 重置状态
    func resetState() {
        isLoading = false
        errorMessage = nil
    }
}