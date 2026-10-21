import Foundation
import PDFKit
import SwiftData
import Testing
@testable import EAIPDataCore

@Suite("Reader rotation and shared preferences", .serialized)
@MainActor
struct ReaderAndPreferencesTests {
    @Test func rotationsPreserveMixedOriginalAnglesAndRestoreThem() throws {
        let document = try #require(PDFDocument(data: AIRACDataCoreTests.Fixture.pdf(pages: 3)))
        for (index, angle) in [0, 90, 270].enumerated() { document.page(at: index)?.rotation = angle }
        let rotation = PDFDocumentRotation()
        #expect(!rotation.apply(0, to: document))
        rotation.apply(90, to: document)
        #expect((0..<3).map { document.page(at: $0)?.rotation } == [90, 180, 0])
        rotation.apply(270, to: document)
        #expect((0..<3).map { document.page(at: $0)?.rotation } == [270, 0, 180])
        rotation.apply(0, to: document)
        #expect((0..<3).map { document.page(at: $0)?.rotation } == [0, 90, 270])
    }

    @Test func replacementDocumentUsesItsOwnOriginalAngles() throws {
        let first = try #require(PDFDocument(data: AIRACDataCoreTests.Fixture.pdf()))
        first.page(at: 0)?.rotation = 90
        let rotation = PDFDocumentRotation()
        rotation.apply(90, to: first)
        let second = try #require(PDFDocument(data: AIRACDataCoreTests.Fixture.pdf()))
        second.page(at: 0)?.rotation = 270
        rotation.apply(90, to: second)
        #expect(second.page(at: 0)?.rotation == 0)
        rotation.apply(0, to: second)
        #expect(second.page(at: 0)?.rotation == 270)
    }

    @Test func bundleIsTheSourceOfVersionAndBuild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Version-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        #if os(macOS)
        let contents = root.appendingPathComponent("Contents")
        #else
        let contents = root
        #endif
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "test.eaip.version", "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "2.4.6", "CFBundleVersion": "42"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: root))
        #expect(AppVersion.displayVersion(in: bundle) == "v2.4.6 (build 42)")
    }

    @Test func oldQuickAccessStyleMigratesToSharedSettingsOnce() throws {
        let fixture = try AIRACDataCoreTests.Fixture(); defer { fixture.remove() }
        let suite = "Pinboard-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preview", forKey: "pinboardStyle")
        try UserSettings.migratePinboardStyle(in: fixture.context, defaults: defaults)
        let reopened = ModelContext(fixture.container)
        let settings = try #require(try reopened.fetch(FetchDescriptor<UserSettings>()).first)
        #expect(settings.pinboardStyle == "preview")
        #expect(defaults.object(forKey: "pinboardStyle") == nil)
        settings.pinboardStyle = "grid"
        try reopened.save()
        try UserSettings.migratePinboardStyle(in: reopened, defaults: defaults)
        #expect(settings.pinboardStyle == "grid")
    }

    @Test func explicitSharedStyleTakesPriorityOverLegacyPreference() throws {
        let fixture = try AIRACDataCoreTests.Fixture(); defer { fixture.remove() }
        let settings = UserSettings()
        settings.pinboardStyle = "grid"
        fixture.context.insert(settings)
        let suite = "Pinboard-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preview", forKey: "pinboardStyle")
        try UserSettings.migratePinboardStyle(in: fixture.context, defaults: defaults)
        #expect(settings.pinboardStyle == "grid")
        #expect(defaults.object(forKey: "pinboardStyle") == nil)
    }
}
