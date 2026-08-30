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
    /// What the dashboard and widgets show — the demo's providers while it is on,
    /// the genuinely connected ones otherwise.
    @Published private(set) var connected: [ProviderID] = []
    /// Providers with credentials actually stored on this device. Settings rows
    /// read this, so the demo never makes a service look signed in when it isn't.
    @Published private(set) var realConnected: [ProviderID] = []
    @Published private(set) var isDemo = Settings.demoMode

    init() {
        realConnected = CredentialStore.connectedProviders
        if isDemo {
            connected = DemoData.providers
            usage = DemoData.readingsByProvider()
        } else {
            usage = UsageCache.loadAll()
            connected = realConnected
        }
    }

    /// True only for real connections — the support prompt and onboarding's
    /// "Done" button must not be fooled by sample data.
    var hasAnyProvider: Bool { !realConnected.isEmpty }

    var isRefreshing: Bool { !refreshing.isEmpty }

    func reloadConnections() {
        realConnected = CredentialStore.connectedProviders
        guard !isDemo else {
            connected = DemoData.providers
            return
        }
        connected = realConnected
        // Drop readings and errors for anything disconnected while we were away.
        usage = usage.filter { connected.contains($0.key) }
        errors = errors.filter { connected.contains($0.key) }
    }

    /// Turns the sample-data demo on or off.
    ///
    /// Demo readings are built in memory and never written to `UsageCache`, so
    /// switching back shows the real cache exactly as it was left.
    func setDemo(_ on: Bool) {
        Settings.demoMode = on
        isDemo = on
        errors = [:]
        realConnected = CredentialStore.connectedProviders
        if on {
            connected = DemoData.providers
            usage = DemoData.readingsByProvider()
        } else {
            connected = realConnected
            usage = UsageCache.loadAll().filter { connected.contains($0.key) }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Refreshes every connected provider concurrently.
    func refreshAll() async {
        guard !isDemo else {
            // Re-date the sample so its reset countdowns keep moving; a demo
            // whose "resets in 2h" never changes looks broken.
            usage = DemoData.readingsByProvider()
            realConnected = CredentialStore.connectedProviders
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
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
        guard !isDemo else {
            usage[id] = DemoData.reading(id)
            return
        }
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
        realConnected.removeAll { $0 == id }
        guard !isDemo else { return }
        usage[id] = nil
        errors[id] = nil
        connected.removeAll { $0 == id }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Erases everything and returns the app to a fresh-install state.
    /// `ContentView` observes `onErased` to send the user back to onboarding.
    func eraseEverything() {
        Settings.eraseEverything()
        isDemo = false
        usage = [:]
        errors = [:]
        connected = []
        realConnected = []
        WidgetCenter.shared.reloadAllTimelines()
        onErased?()
    }

    /// Set by the root view so a full erase can reset navigation.
    var onErased: (() -> Void)?

    /// Called after a successful connect.
    ///
    /// A real connection ends the demo: once there is something genuine to show,
    /// leaving sample cards alongside it would be misleading.
    func didConnect(_ id: ProviderID) async {
        if isDemo { setDemo(false) }
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
