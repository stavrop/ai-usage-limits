import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Overview widget (all providers, or one if configured)

struct UsageEntry: TimelineEntry {
    let date: Date
    let readings: [ProviderUsage]
    let choice: WidgetProviderChoice
    let stale: Bool
    var demo = false
}

struct UsageTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), readings: [WidgetData.sample], choice: .all, stale: false)
    }

    func snapshot(for configuration: ProviderSelectionIntent,
                  in context: Context) async -> UsageEntry {
        let cached = Self.providers(for: configuration.provider).compactMap { UsageCache.load($0) }
        return UsageEntry(date: Date(),
                          readings: cached.isEmpty ? [WidgetData.sample] : cached,
                          choice: configuration.provider,
                          stale: false)
    }

    func timeline(for configuration: ProviderSelectionIntent,
                  in context: Context) async -> Timeline<UsageEntry> {
        // Demo mode is stored in the App Group, so the widget shows the sample
        // alongside the app rather than an empty "not connected" tile.
        if Settings.demoMode {
            let ids = configuration.provider.providerID.map { [$0] } ?? DemoData.providers
            let entry = UsageEntry(date: Date(),
                                   readings: WidgetData.demoReadings(for: ids),
                                   choice: configuration.provider, stale: false, demo: true)
            return Timeline(entries: [entry], policy: .after(WidgetData.nextRefresh()))
        }
        let result = await WidgetData.readings(for: Self.providers(for: configuration.provider))
        let entry = UsageEntry(date: Date(), readings: result.readings,
                               choice: configuration.provider, stale: result.stale)
        return Timeline(entries: [entry], policy: .after(WidgetData.nextRefresh()))
    }

    private static func providers(for choice: WidgetProviderChoice) -> [ProviderID] {
        if let one = choice.providerID {
            return CredentialStore.isConnected(one) ? [one] : []
        }
        return CredentialStore.connectedProviders
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if entry.readings.isEmpty {
            WidgetUnconnected(provider: entry.choice.providerID)
        } else {
            switch family {
            case .accessoryInline:
                Text(inlineText)
            case .accessoryCircular:
                circular
            case .accessoryRectangular:
                rectangular
            case .systemSmall:
                small
            default:
                medium
            }
        }
    }

    /// The bucket closest to its limit across everything shown.
    private var headline: (provider: ProviderID, bucket: Bucket)? {
        var best: (ProviderID, Bucket)?
        for reading in entry.readings {
            guard let top = reading.headline else { continue }
            if best == nil || top.percent > best!.1.percent { best = (reading.provider, top) }
        }
        return best.map { (provider: $0.0, bucket: $0.1) }
    }

    private var inlineText: String {
        entry.readings
            .compactMap { r in r.headline.map { "\(r.provider.shortLabel) \($0.wholePercent)%" } }
            .joined(separator: " · ")
    }

    private var circular: some View {
        Gauge(value: headline?.bucket.clampedFraction ?? 0) {
            Text(headline?.provider.shortLabel ?? "—").font(.caption2)
        } currentValueLabel: {
            Text("\(headline?.bucket.wholePercent ?? 0)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(entry.readings.prefix(2)) { reading in
                if let top = reading.headline {
                    HStack {
                        Text(reading.provider.displayName)
                            .font(.system(size: WidgetType.label))
                        Spacer()
                        Text("\(top.wholePercent)%")
                            .font(.system(size: WidgetType.label, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            UpdatedFooter(readings: entry.readings, stale: entry.stale,
                          compact: true, demo: entry.demo)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Usage")
                .font(.system(size: WidgetType.header, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(entry.readings.prefix(3)) { reading in
                if let top = reading.headline {
                    WidgetBar(label: reading.provider.displayName,
                              percent: top.percent,
                              tint: reading.provider.tint)
                }
            }
            Spacer(minLength: 0)
            UpdatedFooter(readings: entry.readings, stale: entry.stale, demo: entry.demo)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entry.readings.prefix(family == .systemLarge ? 5 : 3)) { reading in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: reading.provider.iconName)
                            .font(.system(size: WidgetType.header))
                            .foregroundStyle(reading.provider.tint)
                        Text(reading.provider.displayName)
                            .font(.system(size: WidgetType.header, weight: .semibold))
                        Spacer(minLength: 2)
                        if let top = reading.headline {
                            Text("resets \(resetString(top.resetsAt))")
                                .font(.system(size: WidgetType.detail))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    ForEach(reading.buckets.prefix(family == .systemLarge ? 3 : 2)) { bucket in
                        WidgetBar(label: bucket.label, percent: bucket.percent)
                    }
                }
            }
            Spacer(minLength: 0)
            UpdatedFooter(readings: entry.readings, stale: entry.stale, demo: entry.demo)
        }
    }
}

struct UsageWidget: Widget {
    // Unchanged kind — renaming it would orphan widgets already on a Home Screen.
    let kind = "AIUsageLimitsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: ProviderSelectionIntent.self,
                               provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("All Providers")
        .description("Every provider you've connected, at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        SingleProviderWidget()
    }
}
