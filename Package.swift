// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EAIPDataCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "EAIPDataCore", targets: ["EAIPDataCore"])],
    targets: [
        .target(
            name: "EAIPDataCore",
            path: "eAIP Pad/eAIP Pad",
            exclude: [
                "App.swift", "ContentView.swift", "Assets.xcassets", "Configs", "DependencyInjection", "Views",
                "eAIP Pad.entitlements", "Common/Imports.swift", "Common/AIRACHelper.swift",
                "Common/ColorScheme.swift", "Common/VersionIntroManager.swift", "Common/Extensions",
                "Services/AIRACService.swift", "Services/LoggerService.swift", "Services/PDFCacheService.swift"
            ],
            sources: [
                "Common/AIRACDocumentIdentity.swift", "Models/Import/EAIPPackageModels.swift",
                "Models/Network/AirportModels.swift", "Models/Network/ChartModels.swift",
                "Models/Network/DocumentModels.swift", "Models/SwiftDataModels.swift",
                "Models/SwiftDataModels+Mapping.swift", "Services/LocalAIRACPackageParser.swift",
                "Services/AIRACFileStore.swift", "Services/AIRACPackageStore.swift"
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "EAIPDataCoreTests", dependencies: ["EAIPDataCore"], path: "Tests/EAIPDataCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
