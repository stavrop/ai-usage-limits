import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    @State private var pollMinutes = Settings.pollMinutes
    @State private var alertThreshold = Settings.alertThreshold
    @State private var confirmErase = false
    @State private var demoMode = Settings.demoMode

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ProviderID.displayOrder, id: \.self) { id in
                        ProviderConnectRow(provider: id, allowsDisconnect: true)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8,
                                                      bottom: 4, trailing: 8))
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Providers")
                } footer: {
                    Text("Connect as many as you use. Each one is stored separately, "
                       + "so disconnecting one never affects the others.")
                }

                Section {
                    Toggle("Show sample data", isOn: $demoMode)
                        .onChange(of: demoMode) { _, on in store.setDemo(on) }
                } header: {
                    Text("Demo")
                } footer: {
                    Text("Fills the app and its widgets with made-up figures so you "
                       + "can see how everything looks without connecting an "
                       + "account. Nothing is fetched and nothing is stored; "
                       + "connecting a real provider switches it off.")
                }

                Section("Refresh") {
                    Stepper("Every \(pollMinutes) min", value: $pollMinutes, in: 1...120)
                        .onChange(of: pollMinutes) { _, newValue in
                            Settings.pollMinutes = newValue
                        }
                    VStack(alignment: .leading) {
                        Text("Warn at \(alertThreshold)%")
                        Slider(value: Binding(
                            get: { Double(alertThreshold) },
                            set: { alertThreshold = Int($0); Settings.alertThreshold = Int($0) }
                        ), in: 50...100, step: 5)
                    }
                }

                Section {
                    Label("Add a widget from the Home Screen: long-press, tap +, "
                        + "search for AI Usage Limits, then pick a provider — or "
                        + "\"All providers\" for a combined view.",
                          systemImage: "square.grid.2x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Widgets")
                }

                Section {
                    Button(role: .destructive) {
                        confirmErase = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Removes every stored credential, all cached usage and your "
                       + "preferences from this device, and signs you out of every "
                       + "provider here. Nothing was ever sent anywhere else, so this "
                       + "erases everything the app holds about you.")
                }

            }
            .alert("Delete all data?", isPresented: $confirmErase) {
                Button("Delete everything", role: .destructive) {
                    store.eraseEverything()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every credential, cached reading and preference is removed from "
                   + "this device. This can't be undone — you'll need to connect your "
                   + "providers again.")
            }
            .onChange(of: store.isDemo) { _, on in demoMode = on }
            .navigationTitle("Settings")
        }
    }
}
