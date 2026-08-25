import SwiftUI

/// Root view: onboarding on first run, the dashboard afterwards.
struct ContentView: View {
    @StateObject private var store = UsageStore()
    @State private var hasOnboarded = Settings.hasOnboarded
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if hasOnboarded {
                RootTabView()
            } else {
                OnboardingView { hasOnboarded = true }
            }
        }
        .environmentObject(store)
        .onAppear {
            // A full erase resets onboarding, so the user is walked through what
            // the app does before it asks for anything again.
            store.onErased = { hasOnboarded = false }
        }
        .onChange(of: scenePhase) { _, phase in
            // Credentials can change while backgrounded (a session expiring, or
            // a provider connected from the widget's deep link).
            guard phase == .active, hasOnboarded else { return }
            Task { await store.refreshAll() }
        }
    }
}
