import Foundation

/// A periodic, low-pressure nudge to support the app.
///
/// Restraint is the point: it waits until the app has actually been useful (a
/// provider connected, and a few launches), then asks at most **once a month**,
/// on a jittered schedule so it never lands on a predictable date. Someone who
/// taps through to support isn't asked again for about a year — nagging a person
/// who already helped is the fastest way to make them stop.
enum SupportPromptState {

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: Config.appGroup) ?? .standard
    }

    private enum Key {
        static let launchCount = "launchCount"
        static let nextAskAt = "supportPromptNextAskAt"
        /// Pre-1.0 flag: a plain "already shown" boolean, with no schedule.
        static let legacyShown = "supportPromptShown"
    }

    /// Cold launches before the first ask.
    private static let firstAskLaunches = 4
    /// Roughly monthly, jittered so it isn't the same day every time.
    private static let repeatDays: ClosedRange<Int> = 25...40
    /// After the user taps a support link.
    private static let supportedDays: ClosedRange<Int> = 350...380

    static func recordLaunch() {
        defaults.set(launchCount + 1, forKey: Key.launchCount)
        migrateLegacyFlagIfNeeded()
    }

    static var launchCount: Int { defaults.integer(forKey: Key.launchCount) }

    private static var nextAskAt: Date? {
        get { defaults.object(forKey: Key.nextAskAt) as? Date }
        set { defaults.set(newValue, forKey: Key.nextAskAt) }
    }

    /// Installs from before the schedule existed carry only a boolean. Turn it
    /// into a date so they aren't re-asked the moment they update.
    private static func migrateLegacyFlagIfNeeded() {
        guard defaults.bool(forKey: Key.legacyShown), nextAskAt == nil else { return }
        schedule(in: repeatDays)
        defaults.removeObject(forKey: Key.legacyShown)
    }

    static func shouldAsk(hasProvider: Bool) -> Bool {
        guard hasProvider else { return false }
        if let next = nextAskAt { return Date() >= next }
        return launchCount >= firstAskLaunches
    }

    /// Called when the sheet is actually on screen.
    static func markShown() { schedule(in: repeatDays) }

    /// Called when the user taps through to a support link.
    static func markSupported() { schedule(in: supportedDays) }

    private static func schedule(in days: ClosedRange<Int>) {
        let offset = TimeInterval(Int.random(in: days) * 24 * 3600)
        nextAskAt = Date().addingTimeInterval(offset)
    }

    /// Part of "Delete all data" — see Settings.eraseEverything().
    static func reset() {
        for key in [Key.launchCount, Key.nextAskAt, Key.legacyShown] {
            defaults.removeObject(forKey: key)
        }
    }
}
