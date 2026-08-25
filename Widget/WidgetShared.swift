import SwiftUI
import WidgetKit

/// Shared timeline plumbing and small views for both widgets.
enum WidgetData {

    /// Fetches the given providers, falling back to the cache on failure.
    ///
    /// `allowRefresh: false` throughout — the app owns token renewal. Both
    /// processes share one Keychain item and refresh tokens rotate on use, so a
    /// widget refresh racing the app would strand one with a dead token.
    static func readings(for providers: [ProviderID]) async -> (readings: [ProviderUsage], stale: Bool) {
        var out: [ProviderUsage] = []
        var stale = false
        for id in providers {
            do {
                out.append(try await ProviderRegistry.provider(id).fetchUsage(allowRefresh: false))
            } catch {
                if let cached = UsageCache.load(id) {
                    out.append(cached)
                    stale = true
                }
            }
        }
        return (out, stale)
    }

    /// ~30 min is a hint; iOS throttles widget timelines as it sees fit.
    static func nextRefresh() -> Date { Date().addingTimeInterval(30 * 60) }

    static let sample = ProviderUsage(
        provider: .anthropic,
        buckets: [
            Bucket(id: "five_hour", label: "Session", subtitle: "5-hour window",
                   percent: 24, resetsAt: Date().addingTimeInterval(3600 * 3)),
            Bucket(id: "seven_day", label: "Weekly", subtitle: "7-day",
                   percent: 20, resetsAt: Date().addingTimeInterval(3600 * 72)),
        ],
        credits: nil, accountLabel: nil, fetchedAt: Date())
}

/// "Updated 12:48" — or "Updated 12:48 · stale" when every fetch failed and we're
/// showing the cache, so an old number is never mistaken for a fresh one.
struct UpdatedFooter: View {
    let readings: [ProviderUsage]
    let stale: Bool
    var compact = false

    private var timestamp: Date? { readings.map(\.fetchedAt).max() }

    var body: some View {
        if let timestamp {
            HStack(spacing: 3) {
                if stale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                }
                Text(compact
                     ? timestamp.formatted(date: .omitted, time: .shortened)
                     : "Updated \(timestamp.formatted(date: .omitted, time: .shortened))")
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: compact ? WidgetType.footer : WidgetType.footer + 1))
            .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            .lineLimit(1)
        }
    }
}

/// Compact labelled bar used across widget families.
///
/// Type sizes are deliberately below the SwiftUI text styles: a widget is mostly
/// chrome at `.caption2`, and the numbers are what the user actually reads. Labels
/// and reset lines shrink; the percentage and the bar keep (or gain) weight.
enum WidgetType {
    static let label: CGFloat = 9
    static let value: CGFloat = 12
    static let detail: CGFloat = 8.5
    static let header: CGFloat = 10
    static let footer: CGFloat = 8
    static let barHeight: CGFloat = 6
}

struct WidgetBar: View {
    let label: String
    let percent: Double
    var tint: Color?
    var showReset: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: WidgetType.label))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: WidgetType.value, weight: .semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint ?? severityTint(percent))
                        .frame(width: max(geo.size.width * min(max(percent, 0), 100) / 100, 2))
                }
            }
            .frame(height: WidgetType.barHeight)
            if let showReset {
                Text("resets \(resetString(showReset))")
                    .font(.system(size: WidgetType.detail))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

/// Shown when the chosen provider (or every provider) isn't connected.
struct WidgetUnconnected: View {
    var provider: ProviderID?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up.slash").font(.title3)
            Text(provider.map { "\($0.displayName) not connected" } ?? "Not connected")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}
