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

// MARK: - 列表 ViewModel 基类
@MainActor
class ListViewModel<Item>: BaseViewModelImpl {
    @Published var items: [Item] = []
    @Published var searchText: String = ""
    
    /// 过滤后的列表（子类可以重写）
    var filteredItems: [Item] {
        items
    }
    
    /// 加载列表数据
    func loadItems() async {
        // 子类实现
    }
    
    /// 重试加载
    func retry() async {
        await loadItems()
    }
    
    /// 清空列表
    func clearItems() {
        items = []
    }
}

// MARK: - 详情 ViewModel 基类
@MainActor
class DetailViewModel<Item>: BaseViewModelImpl {
    @Published var item: Item?
    
    /// 加载详情数据
    func loadDetail() async {
        // 子类实现
    }
    
    /// 重试加载
    func retry() async {
        await loadDetail()
    }
}
