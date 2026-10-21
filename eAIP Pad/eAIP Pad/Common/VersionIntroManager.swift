import Foundation

enum VersionIntroManager {
    private static let lastSeenVersionKey = "lastSeenAppVersion"

    static func shouldShowIntro() -> Bool {
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenVersionKey)
        return lastSeen != AppVersion.appVersion
    }

    static func markIntroAsSeen() {
        UserDefaults.standard.set(AppVersion.appVersion, forKey: lastSeenVersionKey)
    }
}
