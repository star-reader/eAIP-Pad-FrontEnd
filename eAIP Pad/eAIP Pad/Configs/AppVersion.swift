import Foundation

nonisolated enum AppVersion {
    static var appVersion: String { displayVersion(in: .main) }

    static func displayVersion(in bundle: Bundle) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "v\(version) (build \(build))"
    }
}
