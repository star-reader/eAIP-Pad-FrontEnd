import Foundation
import SwiftUI
import SwiftData
import PDFKit

// MARK: - 依赖注入容器
class DIContainer {
    static let shared = DIContainer()
    
    private var services: [String: Any] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - 注册服务
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        lock.lock()
        defer { lock.unlock() }
        let key = String(describing: type)
        services[key] = factory
    }
    
    func register<T>(_ type: T.Type, instance: T) {
        lock.lock()
        defer { lock.unlock() }
        let key = String(describing: type)
        services[key] = instance
    }
    
    // MARK: - 解析服务
    func resolve<T>(_ type: T.Type) -> T {
        lock.lock()
        defer { lock.unlock() }
        
        let key = String(describing: type)
        
        if let instance = services[key] as? T {
            return instance
        }
        
        if let factory = services[key] as? () -> T {
            return factory()
        }
        
        fatalError("未注册的服务类型: \(key)")
    }
    
    // MARK: - 可选解析
    func resolveOptional<T>(_ type: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }
        
        let key = String(describing: type)
        
        if let instance = services[key] as? T {
            return instance
        }
        
        if let factory = services[key] as? () -> T {
            return factory()
        }
        
        return nil
    }
    
    // MARK: - 清除所有服务
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        services.removeAll()
    }
}

// MARK: - Environment Key for DI Container
struct DIContainerKey: EnvironmentKey {
    static let defaultValue = DIContainer.shared
}

extension EnvironmentValues {
    var diContainer: DIContainer {
        get { self[DIContainerKey.self] }
        set { self[DIContainerKey.self] = newValue }
    }
}

// 注意：服务协议定义在 ServiceProtocols.swift 中
// 这样可以避免循环依赖问题

// MARK: - 服务注册扩展
extension DIContainer {
    /// 注册所有核心服务
    /// 注意：当前服务类还未实现协议，这些注册代码暂时注释掉
    /// 未来可以让服务类实现对应的协议后启用
    func registerServices() {
        // 等待服务类实现协议后再启用这些注册
        // register(NetworkServiceProtocol.self, instance: NetworkService.shared)
        // register(KeychainServiceProtocol.self, instance: KeychainService.shared)
        // register(LoggerServiceProtocol.self, instance: LoggerService.shared)
    }
    
    /// 在主线程注册 MainActor 隔离的服务
    @MainActor
    func registerMainActorServices() {
        // 等待服务类实现协议后再启用这些注册
        // register(AuthenticationServiceProtocol.self, instance: AuthenticationService.shared)
        // register(SubscriptionServiceProtocol.self, instance: SubscriptionService.shared)
    }
}
