import AppIntents
import WidgetKit

/// The provider a widget instance shows.
///
/// Modelled as an AppEnum with an explicit "all" case rather than an optional, so
/// the widget gallery offers a single configurable widget that can be added once
/// per provider *and* once combined — instead of shipping four near-identical
/// widget kinds.
enum WidgetProviderChoice: String, AppEnum, CaseIterable {
    case all
    case anthropic
    case openai
    case xai
    case cursor
    case openrouter

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Provider")
    }

    static var caseDisplayRepresentations: [WidgetProviderChoice: DisplayRepresentation] {
        [
            .all: DisplayRepresentation(title: "All providers",
                                        subtitle: "Everything you've connected"),
            .anthropic: DisplayRepresentation(title: "Claude"),
            .openai: DisplayRepresentation(title: "ChatGPT"),
            .xai: DisplayRepresentation(title: "Grok"),
            .cursor: DisplayRepresentation(title: "Cursor"),
            .openrouter: DisplayRepresentation(title: "OpenRouter"),
        ]
    }

    /// nil means "all providers".
    var providerID: ProviderID? {
        switch self {
        case .all: return nil
        case .anthropic: return .anthropic
        case .openai: return .openai
        case .xai: return .xai
        case .cursor: return .cursor
        case .openrouter: return .openrouter
        }
    }
}

/// Widget configuration: pick which provider this instance tracks.
struct ProviderSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Provider"
    static var description = IntentDescription(
        "Show one provider's usage, or all of them together.")

    @Parameter(title: "Provider", default: .all)
    var provider: WidgetProviderChoice

    init() {}

    init(provider: WidgetProviderChoice) {
        self.provider = provider
    }
}


/// The provider a single-provider widget shows.
///
/// Separate from `WidgetProviderChoice` because this one has no "all" case — the
/// whole point of that widget is one provider in full detail, so an "all" option
/// would be a dead end in the picker.
enum SingleProviderChoice: String, AppEnum, CaseIterable {
    case anthropic
    case openai
    case xai
    case cursor
    case openrouter

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Provider")
    }

    static var caseDisplayRepresentations: [SingleProviderChoice: DisplayRepresentation] {
        [
            .anthropic: DisplayRepresentation(title: "Claude"),
            .openai: DisplayRepresentation(title: "ChatGPT"),
            .xai: DisplayRepresentation(title: "Grok"),
            .cursor: DisplayRepresentation(title: "Cursor"),
            .openrouter: DisplayRepresentation(title: "OpenRouter"),
        ]
    }

    var providerID: ProviderID {
        switch self {
        case .anthropic: return .anthropic
        case .openai: return .openai
        case .xai: return .xai
        case .cursor: return .cursor
        case .openrouter: return .openrouter
        }
    }
}

/// Configuration for the single-provider widget.
struct SingleProviderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Provider"
    static var description = IntentDescription(
        "Show one provider's limits in full detail.")

    @Parameter(title: "Provider", default: .anthropic)
    var provider: SingleProviderChoice

    init() {}

    init(provider: SingleProviderChoice) {
        self.provider = provider
    }
}
