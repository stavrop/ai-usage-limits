import SwiftUI

/// "Privacy & connections" — what each provider is asked for, and why.
///
/// Worth stating plainly in-app: the sign-in page a user sees belongs to the
/// provider and names the provider's own CLI, not this app. Explaining that up
/// front is the honest thing to do, and it's what a careful user will wonder
/// about the moment Safari opens.
struct AuthenticationNotesView: View {
    var body: some View {
        List {
            Section {
                Text("You sign in on each provider's own page, opened in Apple's "
                   + "Safari — not in a web view inside this app. Your password is "
                   + "typed into the provider, never into AI Usage Limits.")
                Text("Providers block sign-in inside embedded web views, so a real "
                   + "Safari session is the only way this can work. The app receives "
                   + "only the token the provider hands back after you approve.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How connecting works")
            }

            Section {
                Text("These apps use the same public OAuth clients their official "
                   + "command-line tools use, so the approval screen names that tool "
                   + "— for example \"Claude Code\" — rather than this app. That is "
                   + "expected. It is also why AI Usage Limits is unofficial: the "
                   + "providers have not published an API for reading your usage.")
                    .font(.footnote)
            } header: {
                Text("Whose name you'll see")
            }

            ForEach(ProviderID.displayOrder, id: \.self) { id in
                Section {
                    Text(Self.summary(for: id)).font(.footnote)
                    if let scopes = Self.scopes(for: id) {
                        Text(scopes)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No scopes requested.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = Self.note(for: id) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Label(id.displayName, systemImage: id.iconName)
                }
            }

            Section {
                Text("Whatever a token could technically do, this app only ever calls "
                   + "each provider's usage endpoint. It never sends messages, runs "
                   + "code, changes your plan, or spends on your behalf.")
                    .font(.footnote)
                Text("Tokens are stored in this device's Keychain and sent only to the "
                   + "provider they belong to. There is no account and no server: "
                   + "nothing is uploaded anywhere else.")
                    .font(.footnote)
            }

            Section {
                Text("An independent app. Not affiliated with, endorsed by, or "
                   + "sponsored by Anthropic, OpenAI, xAI, Anysphere or OpenRouter. "
                   + "Provider names identify only the services you choose to connect.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy & connections")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Copy

    private static func summary(for id: ProviderID) -> String {
        switch id {
        case .anthropic:
            return "You authorize in Safari on the same screen you'd see authorizing "
                 + "Claude Code on a new machine. The app catches the redirect back."
        case .openai:
            return "You sign in to ChatGPT in Safari; the app catches the redirect "
                 + "back. This mirrors the scopes the Codex CLI itself uses."
        case .xai:
            return "You sign in with your X account on xAI's page in Safari, using "
                 + "the same OAuth flow as the Grok CLI."
        case .cursor:
            return "You approve the connection on Cursor's own login page, which "
                 + "hands back a token. No OAuth scopes are involved."
        case .openrouter:
            return "You paste an API key you created in your OpenRouter dashboard. "
                 + "No sign-in and no browser step."
        }
    }

    private static func scopes(for id: ProviderID) -> String? {
        switch ProviderRegistry.provider(id).auth {
        case .oauth(let config): return config.scopes
        case .browserPoll, .apiKey: return nil
        }
    }

    private static func note(for id: ProviderID) -> String? {
        switch id {
        case .anthropic:
            return "org:create_api_key has to be in the request or the provider "
                 + "rejects it, but it is never granted — the token you end up with "
                 + "carries user:profile only. It cannot send prompts or spend your "
                 + "allowance."
        case .openai:
            return "Used only to read your Codex rate-limit usage."
        case .xai:
            return "Identity scopes distinguish your account and offline_access keeps "
                 + "it connected. Used only to read your usage and plan."
        case .cursor:
            return "The token is used only to read your Cursor usage."
        case .openrouter:
            return "The key is used only to read your credit limit and balance. "
                 + "OpenRouter is the one provider here with a documented usage API."
        }
    }
}
