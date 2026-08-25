import Foundation

/// Outbound links.
///
/// NOTE: the GitHub repo below does not exist yet — the iOS app needs its own,
/// separate from the macOS menu bar app's repo (that one is a submodule of this
/// monorepo, so nesting iOS inside it would make the monorepo contain ios/
/// twice). Create `stavrop/ai-usage-limits` before shipping publicly.
enum Links {
    static let github = URL(string: "https://github.com/stavrop/ai-usage-limits")!
    static let bug = URL(string: "https://github.com/stavrop/ai-usage-limits/issues/new?labels=bug&template=bug_report.yml")!
    static let feature = URL(string: "https://github.com/stavrop/ai-usage-limits/issues/new?labels=enhancement&template=feature_request.yml")!
    static let coffee = URL(string: "https://buymeacoffee.com/stavrop")!

    /// Shared with the macOS app's GitHub Pages site. It currently describes the
    /// macOS app's behaviour (reading local credential files) — it needs an iOS
    /// section covering the OAuth sign-in and Keychain storage before the App
    /// Store listing points at it.
    static let privacy = URL(string: "https://stavrop.github.io/ai-usage-monitor/privacy.html")!
    static let terms = URL(string: "https://stavrop.github.io/ai-usage-monitor/terms.html")!
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
