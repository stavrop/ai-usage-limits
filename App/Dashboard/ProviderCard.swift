import SwiftUI

/// One provider's card: its buckets as gradient bars, plus credits if any.
struct ProviderCard: View {
    let provider: ProviderID
    let usage: ProviderUsage?
    let error: ProviderError?
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let error, error.needsReconnect {
                Label(error.errorDescription ?? "Needs attention",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let usage, !usage.buckets.isEmpty {
                ForEach(usage.buckets) { bucket in
                    BucketBar(bucket: bucket)
                }
            } else if isRefreshing {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if usage != nil {
                Text("No limits reported for this account.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let credits = usage?.credits {
                CreditsLine(credits: credits)
            }

            if let error, !error.needsReconnect {
                Text(error.errorDescription ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if let fetchedAt = usage?.fetchedAt {
                Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.iconName)
                .font(.headline)
                .foregroundStyle(provider.tint)
            Text(provider.displayName).font(.headline)
            Spacer()
            if isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// A labelled gradient bar. Mirrors the macOS dropdown's severity ramp.
struct BucketBar: View {
    let bucket: Bucket

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.label).font(.subheadline)
                Spacer()
                Text("\(bucket.wholePercent)%")
                    .font(.subheadline).bold()
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [severityTint(bucket.percent).opacity(0.7),
                                     severityTint(bucket.percent)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * bucket.clampedFraction, 3))
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                if let subtitle = bucket.subtitle {
                    Text(subtitle)
                    Text("·")
                }
                Text("resets \(resetString(bucket.resetsAt))")
                if !resetClock(bucket.resetsAt).isEmpty {
                    Text("· \(resetClock(bucket.resetsAt))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

struct CreditsLine: View {
    let credits: CreditInfo

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "creditcard")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var text: String {
        if let note = credits.note { return note }
        func money(_ value: Double?) -> String? {
            guard let value else { return nil }
            return value.formatted(.currency(code: credits.currency)
                .precision(.fractionLength(2)))
        }
        if let used = money(credits.used), let limit = money(credits.limit) {
            return "Credits \(used) of \(limit)"
        }
        if let remaining = money(credits.remaining) {
            return "\(remaining) remaining"
        }
        if let used = money(credits.used) {
            return "Credits used \(used)"
        }
        return "Credits"
    }
}
