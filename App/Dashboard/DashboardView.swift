import SwiftUI

struct DashboardView: View {
    /// Switches the tab bar to Settings — the dashboard no longer owns a sheet.
    let onAddProvider: () -> Void

    @EnvironmentObject private var store: UsageStore
    @State private var pollTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if store.connected.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Usage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing || store.connected.isEmpty)
                }
            }
        }
        .task { await store.refreshAll() }
        // The timer fires every minute but only acts on the user's cadence, so
        // changing the interval in Settings takes effect without re-arming.
        .onReceive(pollTimer) { _ in
            guard !store.connected.isEmpty else { return }
            let due = Date().timeIntervalSince(lastRefresh) >= Double(Settings.pollMinutes * 60)
            if due { Task { await store.refreshAll() } }
        }
    }

    /// Oldest reading across providers — the cadence anchor.
    private var lastRefresh: Date {
        store.usage.values.map(\.fetchedAt).min() ?? .distantPast
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 14) {
                if store.isDemo { DemoBanner() }

                ForEach(store.connected, id: \.self) { id in
                    ProviderCard(provider: id,
                                 usage: store.usage[id],
                                 error: store.errors[id],
                                 isRefreshing: store.refreshing.contains(id))
                }

                Button {
                    onAddProvider()
                } label: {
                    Label("Add a provider", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .refreshable { await store.refreshAll() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No providers yet", systemImage: "square.stack.3d.up.slash")
        } description: {
            Text("Connect a provider to see your usage here.")
        } actions: {
            VStack(spacing: 10) {
                Button("Add a provider") { onAddProvider() }
                    .buttonStyle(.borderedProminent)
                // Nothing here is worth looking at until a provider is attached,
                // and attaching one means signing in to someone else's service.
                // The sample lets anyone see what they'd get first.
                Button("Show sample data") { store.setDemo(true) }
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// Sits above the sample cards so a demo reading is never mistaken for a real
/// one — on screen, in a screenshot, or in a support conversation.
struct DemoBanner: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sample data").font(.subheadline).bold()
                Text("These figures are made up, so you can see how the app looks "
                   + "before connecting anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Turn off") { store.setDemo(false) }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(14)
        .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
