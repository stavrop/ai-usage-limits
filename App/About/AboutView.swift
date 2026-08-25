import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text("AI Usage Limits").font(.title2).bold()
                        Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color.clear)

                Section("Support this app") {
                    Link(destination: Links.coffee) {
                        Label("Buy me a coffee", systemImage: "cup.and.saucer")
                    }
                    Link(destination: Links.github) {
                        Label("Star on GitHub", systemImage: "star")
                    }
                }

                Section("Feedback") {
                    Link(destination: Links.bug) {
                        Label("Report a bug", systemImage: "ladybug")
                    }
                    Link(destination: Links.feature) {
                        Label("Request a feature", systemImage: "lightbulb")
                    }
                }

                Section {
                    NavigationLink {
                        AuthenticationNotesView()
                    } label: {
                        Label("Privacy & connections", systemImage: "lock.shield")
                    }
                    Link(destination: Links.privacy) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                    Link(destination: Links.terms) {
                        Label("Terms of service", systemImage: "doc.text")
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Everything stays on this device. There is no account, no "
                       + "server and no analytics.")
                }

                Section {
                    Text("An independent app. Not affiliated with, endorsed by, or "
                       + "sponsored by Anthropic, OpenAI, xAI, Anysphere or "
                       + "OpenRouter. Some usage endpoints are undocumented and may "
                       + "change without notice.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
        }
    }
}
