import Foundation

/// Outbound links.
///
/// The app has its own public repo, separate from the macOS menu bar app's: that
/// one is a submodule of the private monorepo, so nesting iOS inside it would
/// carry the iOS sources twice.
enum Links {
    static let github = URL(string: "https://github.com/stavrop/ai-usage-limits")!
    static let bug = URL(string: "https://github.com/stavrop/ai-usage-limits/issues/new?labels=bug&template=bug_report.yml")!
    static let feature = URL(string: "https://github.com/stavrop/ai-usage-limits/issues/new?labels=enhancement&template=feature_request.yml")!
    static let coffee = URL(string: "https://buymeacoffee.com/stavrop")!

    /// This app's own policy and terms. Deliberately NOT the macOS app's pages —
    /// those describe reading credential files the user's desktop CLIs already
    /// wrote, which is not how this app works. Source lives in PRIVACY.md /
    /// TERMS.md; `docs/build.py` regenerates the hosted HTML.
    static let privacy = URL(string: "https://stavrop.github.io/ai-usage-limits/privacy.html")!
    static let terms = URL(string: "https://stavrop.github.io/ai-usage-limits/terms.html")!
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
