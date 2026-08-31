import Foundation

/// Sample readings for the built-in demo.
///
/// The app is a viewer for accounts that belong to other services, so there is
/// no way to hand anyone — a new user deciding whether to install, or an App
/// Review tester — a working account to look at. Demo mode fills the dashboard
/// and the widgets with these fixed, obviously-fictional figures instead.
///
/// Nothing here touches the network, the Keychain or the usage cache: the
/// readings are built on demand and live only in `UsageStore` (and in a widget
/// timeline entry). Every card the demo produces is labelled as sample data by
/// the views that show it, and the account label says so too.
enum DemoData {

    /// Shown in the account slot so a sample card can never read as a real login.
    static let accountLabel = "demo@example.com — sample data"

    /// Which providers the demo populates, in the app's usual display order.
    static let providers: [ProviderID] = ProviderID.displayOrder

    static func readings(for ids: [ProviderID] = providers,
                         now: Date = Date()) -> [ProviderUsage] {
        ids.map { reading($0, now: now) }
    }

    static func readingsByProvider(now: Date = Date()) -> [ProviderID: ProviderUsage] {
        Dictionary(uniqueKeysWithValues: providers.map { ($0, reading($0, now: now)) })
    }

    /// The next boundary of a repeating window, in absolute time.
    ///
    /// Reset times are *not* "now plus a fixed offset": that pins the countdown,
    /// so every refresh would snap "resets in 2h 36m" back to the same value
    /// after the user had watched it tick down. Anchoring to the window's own
    /// cycle instead means the sample counts down continuously and rolls over on
    /// its own, identically in the app and in the widget, with nothing stored.
    private static func nextReset(everyHours: Double, now: Date) -> Date {
        let window = everyHours * 3600
        let elapsed = now.timeIntervalSince1970
        return Date(timeIntervalSince1970: (floor(elapsed / window) + 1) * window)
    }

    /// One provider's sample reading.
    ///
    /// The buckets mirror the shape each service really returns — Claude's
    /// 5-hour session plus its weekly window, ChatGPT's two windows, Grok's
    /// credit period, Cursor's monthly requests, OpenRouter's credits with no
    /// window at all — so the demo shows the layout the user will actually get.
    /// The numbers are chosen to span the green/amber/red ramp.
    static func reading(_ provider: ProviderID, now: Date = Date()) -> ProviderUsage {
        func at(everyHours: Double) -> Date { nextReset(everyHours: everyHours, now: now) }

        switch provider {
        case .anthropic:
            return ProviderUsage(
                provider: provider,
                buckets: [
                    Bucket(id: "five_hour", label: "Session", subtitle: "5-hour window",
                           percent: 43, resetsAt: at(everyHours: 5)),
                    Bucket(id: "seven_day", label: "Weekly", subtitle: "7-day",
                           percent: 68, resetsAt: at(everyHours: 24 * 7)),
                ],
                credits: CreditInfo(used: 4.20, limit: 25, remaining: nil,
                                    currency: "USD", note: nil),
                accountLabel: accountLabel,
                fetchedAt: now)

        case .openai:
            return ProviderUsage(
                provider: provider,
                buckets: [
                    Bucket(id: "primary", label: "Messages", subtitle: "3-hour window",
                           percent: 88, resetsAt: at(everyHours: 3)),
                    Bucket(id: "secondary", label: "Weekly", subtitle: "7-day",
                           percent: 52, resetsAt: at(everyHours: 24 * 7)),
                ],
                credits: nil,
                accountLabel: accountLabel,
                fetchedAt: now)

        case .xai:
            return ProviderUsage(
                provider: provider,
                buckets: [
                    Bucket(id: "credits", label: "Credits", subtitle: "current period",
                           percent: 31, resetsAt: at(everyHours: 24 * 30)),
                ],
                credits: CreditInfo(used: 6.20, limit: 20, remaining: nil,
                                    currency: "USD", note: nil),
                accountLabel: accountLabel,
                fetchedAt: now)

        case .cursor:
            return ProviderUsage(
                provider: provider,
                buckets: [
                    Bucket(id: "requests", label: "Requests", subtitle: "monthly plan",
                           percent: 74, resetsAt: at(everyHours: 24 * 28)),
                ],
                credits: nil,
                accountLabel: accountLabel,
                fetchedAt: now)

        case .openrouter:
            return ProviderUsage(
                provider: provider,
                buckets: [],
                credits: CreditInfo(used: 12.50, limit: 50, remaining: 37.50,
                                    currency: "USD", note: nil),
                accountLabel: accountLabel,
                fetchedAt: now)
        }
    }
}
