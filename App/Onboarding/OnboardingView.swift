import SwiftUI

/// First-run flow.
///
/// Deliberately does NOT open a sign-in sheet on launch. The app supports several
/// services, so the first screens explain what it does and how credentials are
/// handled, and only then offer the provider list — connecting any one of them is
/// optional, and the user can finish with none and add them later in Settings.
struct OnboardingView: View {
    @EnvironmentObject private var store: UsageStore
    /// Bumped when onboarding completes so the root view re-evaluates.
    let onFinish: () -> Void

    @State private var page = 0

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                privacy.tag(1)
                providers.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            footer
        }
    }

    // MARK: Pages

    private var welcome: some View {
        OnboardingPage(
            icon: "gauge.with.dots.needle.67percent",
            tint: .orange,
            title: "AI Usage Limits",
            subtitle: "See how much of your Claude, ChatGPT, Grok, Cursor and "
                + "OpenRouter allowance you've used — and when each one resets — "
                + "without opening a single dashboard."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "chart.pie", tint: .orange,
                           title: "Every provider in one place",
                           detail: "Session, weekly and credit limits side by side.")
                FeatureRow(icon: "square.grid.2x2", tint: .blue,
                           title: "Home Screen widgets",
                           detail: "One per provider, or all of them together.")
                FeatureRow(icon: "bolt.horizontal", tint: .green,
                           title: "Stays signed in",
                           detail: "Connect once; it renews itself in the background.")
            }
        }
    }

    private var privacy: some View {
        OnboardingPage(
            icon: "lock.shield",
            tint: .blue,
            title: "Your credentials stay yours",
            subtitle: "Everything is stored in this device's Keychain and sent only to "
                + "the provider it belongs to. There is no account, no server, and "
                + "no analytics."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "iphone", tint: .blue,
                           title: "On-device only",
                           detail: "Nothing is uploaded anywhere else — ever.")
                FeatureRow(icon: "eye.slash", tint: .purple,
                           title: "Read-only",
                           detail: "The app reads usage figures. It never sends prompts "
                                 + "or spends your allowance.")
                FeatureRow(icon: "exclamationmark.triangle", tint: .orange,
                           title: "Unofficial",
                           detail: "Not affiliated with Anthropic, OpenAI or OpenRouter. "
                                 + "Some usage endpoints are undocumented and may change.")
            }
        }
    }

    private var providers: some View {
        OnboardingPage(
            icon: "square.stack.3d.up",
            tint: .indigo,
            title: "Connect a provider",
            subtitle: "Add as many as you like now, or skip and do it later in Settings."
        ) {
            VStack(spacing: 10) {
                ForEach(ProviderID.displayOrder, id: \.self) { id in
                    ProviderConnectRow(provider: id)
                }

                // Every provider here is someone else's account, so there is no
                // way to try the app without signing in to one — unless we hand
                // over a sample.
                Button {
                    store.setDemo(true)
                    finish()
                } label: {
                    Label("Look around with sample data", systemImage: "wand.and.stars")
                        .font(.subheadline)
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 12) {
            if page < lastPage {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if store.hasAnyProvider || store.isDemo {
                Button {
                    finish()
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                // Connecting nothing is a legitimate outcome — the dashboard has
                // its own empty state and Settings can add providers any time.
                Button {
                    finish()
                } label: {
                    Text("Skip for now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    private func finish() {
        Settings.hasOnboarded = true
        onFinish()
    }
}

// MARK: - Building blocks

private struct OnboardingPage<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(tint)
                    .padding(.top, 40)

                Text(title)
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                content
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
