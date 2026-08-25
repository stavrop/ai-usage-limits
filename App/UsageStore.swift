import Foundation
import SwiftUI
import WidgetKit

/// Observable state for the whole app: what's connected, the latest reading for
/// each provider, and any per-provider error.
///
/// Errors are tracked per provider so one service being rate-limited or signed
/// out never blanks the others — the same isolation the macOS app has.
@MainActor
final class UsageStore: ObservableObject {

    @Published private(set) var usage: [ProviderID: ProviderUsage] = [:]
    @Published private(set) var errors: [ProviderID: ProviderError] = [:]
    @Published private(set) var refreshing: Set<ProviderID> = []
    @Published private(set) var connected: [ProviderID] = []

    init() {
        usage = UsageCache.loadAll()
        connected = CredentialStore.connectedProviders
    }

    var hasAnyProvider: Bool { !connected.isEmpty }

    var isRefreshing: Bool { !refreshing.isEmpty }

    func reloadConnections() {
        connected = CredentialStore.connectedProviders
        // Drop readings and errors for anything disconnected while we were away.
        usage = usage.filter { connected.contains($0.key) }
        errors = errors.filter { connected.contains($0.key) }
    }

    /// Refreshes every connected provider concurrently.
    func refreshAll() async {
        reloadConnections()
        await withTaskGroup(of: Void.self) { group in
            for id in connected {
                group.addTask { [weak self] in await self?.refresh(id) }
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Refreshes one provider, leaving the last good reading in place on failure.
    func refresh(_ id: ProviderID) async {
        guard !refreshing.contains(id) else { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }

        do {
            let result = try await ProviderRegistry.provider(id).fetchUsage(allowRefresh: true)
            usage[id] = result
            errors[id] = nil
        } catch let error as ProviderError {
            errors[id] = error
            // Only a dead session removes the provider from the connected list;
            // a rate-limit or a blip must not sign the user out.
            if error.needsReconnect, !CredentialStore.isConnected(id) {
                connected.removeAll { $0 == id }
                usage[id] = nil
            }
        } catch {
            errors[id] = .network(error.localizedDescription)
        }
    }

    func disconnect(_ id: ProviderID) {
        Settings.forget(id)
        usage[id] = nil
        errors[id] = nil
        connected.removeAll { $0 == id }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Erases everything and returns the app to a fresh-install state.
    /// `ContentView` observes `onErased` to send the user back to onboarding.
    func eraseEverything() {
        Settings.eraseEverything()
        usage = [:]
        errors = [:]
        connected = []
        WidgetCenter.shared.reloadAllTimelines()
        onErased?()
    }

    /// Set by the root view so a full erase can reset navigation.
    var onErased: (() -> Void)?

    /// Called after a successful connect.
    func didConnect(_ id: ProviderID) async {
        reloadConnections()
        await refresh(id)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Most-consumed bucket across everything, for the summary line.
    var busiest: (provider: ProviderID, bucket: Bucket)? {
        var best: (ProviderID, Bucket)?
        for (id, reading) in usage {
            guard let top = reading.headline else { continue }
            if best == nil || top.percent > best!.1.percent { best = (id, top) }
        }
        return best.map { (provider: $0.0, bucket: $0.1) }
    }
}
