import Foundation
import SwiftUI

/// Which service a reading came from.
///
/// Deliberately mirrors the macOS app's `ProviderID` so both codebases describe
/// the same concepts. Raw values are persisted (Keychain accounts, widget intent
/// selections, cache keys) — do not rename them.
enum ProviderID: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openai
    case openrouter
    case xai
    case cursor

    var displayName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        case .openrouter: return "OpenRouter"
        case .xai: return "Grok"
        case .cursor: return "Cursor"
        }
    }

    /// Short label for cramped widget families.
    var shortLabel: String {
        switch self {
        case .anthropic: return "C"
        case .openai: return "G"
        case .openrouter: return "OR"
        case .xai: return "Gr"
        case .cursor: return "Cu"
        }
    }

    var iconName: String {
        switch self {
        case .anthropic: return "sparkle"
        case .openai: return "circle.hexagongrid"
        case .openrouter: return "arrow.triangle.branch"
        case .xai: return "bolt.circle"
        case .cursor: return "cursorarrow.rays"
        }
    }

    var tint: Color {
        switch self {
        case .anthropic: return .orange
        case .openai: return .teal
        case .openrouter: return .indigo
        case .xai: return .primary
        case .cursor: return .pink
        }
    }

    /// Order shown in lists.
    static let displayOrder: [ProviderID] = [.anthropic, .openai, .xai, .cursor, .openrouter]
}

/// One rate-limit or quota window.
///
/// Providers expose wildly different windows — Claude has a 5-hour session and a
/// 7-day window, ChatGPT has primary/secondary windows whose lengths come back
/// in the payload, OpenRouter has no window at all — so a bucket carries its own
/// label rather than the model naming fixed fields.
struct Bucket: Codable, Equatable, Identifiable, Sendable {
    /// Stable within a provider, so widgets can pin to one bucket.
    var id: String
    var label: String
    var subtitle: String?
    /// 0–100. Kept as a Double: Claude reports floats and rounding early loses
    /// precision the Mac app shows.
    var percent: Double
    var resetsAt: Date?

    var clampedFraction: Double { min(max(percent, 0), 100) / 100 }
    var wholePercent: Int { Int(percent.rounded()) }
}

/// Optional money/credit line, shown under the buckets.
struct CreditInfo: Codable, Equatable, Sendable {
    var used: Double?
    var limit: Double?
    var remaining: Double?
    var currency: String
    /// Free-text when a provider gives no structured numbers.
    var note: String?
}

/// Everything we know about one provider right now.
struct ProviderUsage: Codable, Equatable, Identifiable, Sendable {
    var provider: ProviderID
    var buckets: [Bucket]
    var credits: CreditInfo?
    /// e.g. the signed-in email, shown in Settings so multi-account users can tell
    /// which login is attached.
    var accountLabel: String?
    var fetchedAt: Date

    var id: String { provider.rawValue }

    /// The bucket a compact widget should lead with: the closest to its limit.
    var headline: Bucket? {
        buckets.max { $0.percent < $1.percent }
    }
}

/// Formats a reset date into a short human string, e.g. "in 4h 12m" / "in 2d 3h".
func resetString(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "—" }
    let delta = date.timeIntervalSince(now)
    if delta <= 0 { return "resetting…" }
    let hours = Int(delta) / 3600
    let mins = (Int(delta) % 3600) / 60
    if hours >= 24 {
        return "in \(hours / 24)d \(hours % 24)h"
    } else if hours > 0 {
        return "in \(hours)h \(mins)m"
    } else {
        return "in \(mins)m"
    }
}

func resetClock(_ date: Date?) -> String {
    guard let date else { return "" }
    let df = DateFormatter()
    df.locale = .current
    df.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" : "EEE h:mm a"
    return df.string(from: date)
}

/// Green → amber → red as a bucket fills, matching the macOS dropdown's bars.
func severityTint(_ percent: Double) -> Color {
    switch percent {
    case ..<60: return .green
    case ..<85: return .orange
    default: return .red
    }
}
