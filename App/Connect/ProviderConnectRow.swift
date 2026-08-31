import SwiftUI

/// A single provider row with a Connect / Connected control.
///
/// Shared by onboarding and Settings so the two can never drift apart.
struct ProviderConnectRow: View {
    let provider: ProviderID
    /// Settings shows a Disconnect action; onboarding doesn't.
    var allowsDisconnect = false

    @EnvironmentObject private var store: UsageStore
    @StateObject private var model = ConnectRowModel()
    @State private var showKeySheet = false

    /// Deliberately `realConnected`: while the demo is on, `connected` lists the
    /// sample providers, and a row must never claim a service is signed in.
    private var isConnected: Bool { store.realConnected.contains(provider) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: provider.iconName)
                .font(.title2)
                .foregroundStyle(provider.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName).font(.body).bold()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(isConnected ? .secondary : .tertiary)
            }

            Spacer(minLength: 8)

            if model.busy {
                ProgressView()
            } else if isConnected {
                if allowsDisconnect {
                    Menu {
                        Button("Reconnect") { connect() }
                        Button("Disconnect", role: .destructive) {
                            store.disconnect(provider)
                        }
                    } label: {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            } else {
                Button("Connect") { connect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottom) {
            if let error = model.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .offset(y: 18)
            }
        }
        .padding(.bottom, model.error == nil ? 0 : 22)
        .sheet(isPresented: $showKeySheet) {
            APIKeyEntryView(provider: provider) { key in
                await model.connectKey(provider: provider, key: key, store: store)
            }
        }
    }

    private var statusText: String {
        if let error = store.errors[provider], error.needsReconnect {
            return error.errorDescription ?? "Needs attention"
        }
        if isConnected {
            // `store.usage` holds sample readings while the demo is on, and the
            // sample's account label must never be shown against a real login.
            return store.isDemo ? "Connected"
                                : (store.usage[provider]?.accountLabel ?? "Connected")
        }
        switch ProviderRegistry.provider(provider).auth {
        case .oauth: return "Sign in with your account"
        case .browserPoll: return "Approve in your browser"
        case .apiKey: return "Paste an API key"
        }
    }

    private func connect() {
        switch ProviderRegistry.provider(provider).auth {
        case .oauth:
            Task { await model.connectOAuth(provider: provider, store: store) }
        case .browserPoll:
            Task { await model.connectBrowserPoll(provider: provider, store: store) }
        case .apiKey:
            showKeySheet = true
        }
    }
}

/// Per-row connect state. One instance per row so a failure on one provider
/// never blocks or blanks another.
@MainActor
final class ConnectRowModel: ObservableObject {
    @Published var busy = false
    @Published var error: String?

    private let connector = ProviderConnector()

    func connectOAuth(provider: ProviderID, store: UsageStore) async {
        guard !busy else { return }
        busy = true
        error = nil
        do {
            try await connector.connectOAuth(provider: ProviderRegistry.provider(provider))
            await store.didConnect(provider)
        } catch {
            if !ProviderConnector.isUserCancellation(error) {
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        busy = false
    }

    func connectBrowserPoll(provider: ProviderID, store: UsageStore) async {
        guard !busy else { return }
        busy = true
        error = nil
        do {
            try await connector.connectBrowserPoll(
                provider: ProviderRegistry.provider(provider))
            await store.didConnect(provider)
        } catch {
            if !ProviderConnector.isUserCancellation(error) {
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        busy = false
    }

    func connectKey(provider: ProviderID, key: String, store: UsageStore) async -> String? {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await connector.connectAPIKey(
                provider: ProviderRegistry.provider(provider), key: key)
            await store.didConnect(provider)
            return nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return message
        }
    }
}
