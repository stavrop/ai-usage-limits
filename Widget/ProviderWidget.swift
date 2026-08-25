import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Single-provider widget
//
// A separate widget kind rather than a mode of the overview one, for two reasons:
// the gallery makes the choice explicit at add-time (the overview widget's picker
// is only reachable via Edit Widget, which few people find), and the layout is
// genuinely different — every bucket for one provider, with reset times and
// credits, instead of one summary line each.

struct ProviderEntry: TimelineEntry {
    let date: Date
    let reading: ProviderUsage?
    let provider: ProviderID
    let stale: Bool
}

struct ProviderTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> ProviderEntry {
        ProviderEntry(date: Date(), reading: WidgetData.sample,
                      provider: .anthropic, stale: false)
    }

    func snapshot(for configuration: SingleProviderIntent,
                  in context: Context) async -> ProviderEntry {
        let id = configuration.provider.providerID
        return ProviderEntry(date: Date(),
                             reading: UsageCache.load(id) ?? WidgetData.sample,
                             provider: id, stale: false)
    }

    func timeline(for configuration: SingleProviderIntent,
                  in context: Context) async -> Timeline<ProviderEntry> {
        let id = configuration.provider.providerID
        guard CredentialStore.isConnected(id) else {
            return Timeline(entries: [ProviderEntry(date: Date(), reading: nil,
                                                    provider: id, stale: false)],
                            policy: .after(WidgetData.nextRefresh()))
        }
        let result = await WidgetData.readings(for: [id])
        return Timeline(entries: [ProviderEntry(date: Date(),
                                                reading: result.readings.first,
                                                provider: id,
                                                stale: result.stale)],
                        policy: .after(WidgetData.nextRefresh()))
    }
}

struct ProviderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProviderEntry

    var body: some View {
        if let reading = entry.reading {
            switch family {
            case .accessoryInline:
                Text("\(entry.provider.shortLabel) \(reading.headline?.wholePercent ?? 0)%")
            case .accessoryCircular:
                circular(reading)
            case .accessoryRectangular:
                rectangular(reading)
            default:
                detail(reading)
            }
        } else {
            WidgetUnconnected(provider: entry.provider)
        }
    }

    private func circular(_ reading: ProviderUsage) -> some View {
        Gauge(value: reading.headline?.clampedFraction ?? 0) {
            Text(entry.provider.shortLabel).font(.caption2)
        } currentValueLabel: {
            Text("\(reading.headline?.wholePercent ?? 0)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func rectangular(_ reading: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.provider.displayName)
                .font(.system(size: WidgetType.label, weight: .semibold))
            ForEach(reading.buckets.prefix(2)) { bucket in
                HStack {
                    Text(bucket.label).font(.system(size: WidgetType.label))
                    Spacer()
                    Text("\(bucket.wholePercent)%")
                        .font(.system(size: WidgetType.label, weight: .semibold))
                        .monospacedDigit()
                }
            }
            UpdatedFooter(readings: [reading], stale: entry.stale, compact: true)
        }
    }

    /// Small / medium / large all show the same thing; bigger families simply fit
    /// more buckets and the reset line.
    private func detail(_ reading: ProviderUsage) -> some View {
        let maxBuckets = family == .systemSmall ? 2 : (family == .systemLarge ? 6 : 3)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: entry.provider.iconName)
                    .font(.system(size: WidgetType.header))
                    .foregroundStyle(entry.provider.tint)
                Text(entry.provider.displayName)
                    .font(.system(size: WidgetType.header, weight: .semibold))
                Spacer(minLength: 0)
            }

            if reading.buckets.isEmpty {
                Text("No limits reported.")
                    .font(.system(size: WidgetType.label)).foregroundStyle(.secondary)
            } else {
                ForEach(reading.buckets.prefix(maxBuckets)) { bucket in
                    WidgetBar(label: bucket.label,
                              percent: bucket.percent,
                              showReset: family == .systemSmall ? nil : bucket.resetsAt)
                }
            }

            if family != .systemSmall, let credits = reading.credits,
               let text = Self.creditsText(credits) {
                Text(text)
                    .font(.system(size: WidgetType.detail))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            UpdatedFooter(readings: [reading], stale: entry.stale)
        }
    }

    private static func creditsText(_ credits: CreditInfo) -> String? {
        if let note = credits.note { return note }
        func money(_ v: Double?) -> String? {
            guard let v else { return nil }
            return v.formatted(.currency(code: credits.currency).precision(.fractionLength(2)))
        }
        if let used = money(credits.used), let limit = money(credits.limit) {
            return "Credits \(used) of \(limit)"
        }
        if let remaining = money(credits.remaining) { return "\(remaining) remaining" }
        return money(credits.used).map { "Credits used \($0)" }
    }
}

struct SingleProviderWidget: Widget {
    let kind = "AIUsageLimitsProviderWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SingleProviderIntent.self,
                               provider: ProviderTimelineProvider()) { entry in
            ProviderWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Single Provider")
        .description("One provider in full detail. Choose which in the widget's settings.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}
