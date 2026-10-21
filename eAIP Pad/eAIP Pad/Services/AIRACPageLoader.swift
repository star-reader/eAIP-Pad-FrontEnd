import Combine
import Foundation

/// 页面会话内保留结果与正在进行的请求；离开页面不取消请求，不写磁盘缓存。
@MainActor
final class AIRACPageLoader<Value>: ObservableObject {
    @Published private(set) var value: Value
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let initialValue: Value
    private var loadedKey: String?
    private var pendingKey: String?
    private var generation: UInt = 0
    private var request: Task<Void, Never>?

    init(initialValue: Value) {
        value = initialValue
        self.initialValue = initialValue
    }

    deinit { request?.cancel() }

    func load(
        key: String, force: Bool = false, errorPrefix: String = "",
        operation: @escaping @MainActor () async throws -> Value
    ) async {
        if !force, loadedKey == key { return }
        if !force, pendingKey == key, let request {
            await request.value
            return
        }
        request?.cancel()
        generation &+= 1
        let generation = self.generation
        loadedKey = nil
        value = initialValue
        pendingKey = key
        isLoading = true
        errorMessage = nil
        // 请求属于页面模型，SwiftUI 的外层 .task 取消时仍可继续加载。
        let task = Task { @MainActor [weak self] in
            do {
                let value = try await operation()
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.value = value
                self.loadedKey = key
                self.finish()
            } catch {
                guard let self, self.generation == generation else { return }
                if !Task.isCancelled { self.errorMessage = errorPrefix + error.localizedDescription }
                self.finish()
            }
        }
        request = task
        await task.value
    }

    private func finish() {
        pendingKey = nil
        request = nil
        isLoading = false
    }
}
