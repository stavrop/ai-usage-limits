import SwiftUI

/// A one-time nudge to support the app.
///
/// Deliberately restrained: it waits until the app has actually been useful
/// (a provider connected and a few launches), appears **once**, and its dismiss
/// button is a plain "No thanks" rather than a guilt-trip. Asking on first launch
/// — before the app has done anything for the user — is what makes these prompts
/// resented.
enum SupportPromptState {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: Config.appGroup) ?? .standard
    }
    private static let launchKey = "launchCount"
    private static let shownKey = "supportPromptShown"

    /// Launches required before asking.
    private static let threshold = 4

    static func recordLaunch() {
        defaults.set(launchCount + 1, forKey: launchKey)
    }

    static var launchCount: Int { defaults.integer(forKey: launchKey) }

    static var hasBeenShown: Bool {
        get { defaults.bool(forKey: shownKey) }
        set { defaults.set(newValue, forKey: shownKey) }
    }

    /// True when the app has proved useful and we haven't asked before.
    static func shouldAsk(hasProvider: Bool) -> Bool {
        hasProvider && !hasBeenShown && launchCount >= threshold
    }

    static func markShown() { hasBeenShown = true }
}

struct SupportPromptView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(.pink)

            Text("Enjoying AI Usage Limits?")
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            Text("It's free, has no ads and collects nothing about you. If it's "
               + "useful, a coffee or a GitHub star genuinely helps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Link(destination: Links.coffee) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Link(destination: Links.github) {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("No thanks") { dismiss() }
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .onAppear { SupportPromptState.markShown() }
    }
}
