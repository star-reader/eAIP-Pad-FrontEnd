// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EAIPDataCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "EAIPDataCore", targets: ["EAIPDataCore"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(
            name: "EAIPDataCore",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
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
                "Services/AIRACFileStore.swift", "Services/AIRACPackageStore.swift",
                "Services/AIRACArchiveExtractor.swift", "Services/AIRACServerClient.swift",
                "Services/AIRACOnlineData.swift"
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "EAIPDataCoreTests",
            dependencies: ["EAIPDataCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            path: "Tests/EAIPDataCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
