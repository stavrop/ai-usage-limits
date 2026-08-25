import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable { case home, settings, about }

    @EnvironmentObject private var store: UsageStore
    @State private var tab: Tab = .home
    @State private var showSupportPrompt = false

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(onAddProvider: { tab = .settings })
                .tabItem { Label("Home", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(Tab.home)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .task {
            // Ask only once the app has actually been useful — see SupportPromptState.
            if SupportPromptState.shouldAsk(hasProvider: store.hasAnyProvider) {
                showSupportPrompt = true
            }
        }
        .sheet(isPresented: $showSupportPrompt) {
            SupportPromptView()
                .presentationDetents([.medium, .large])
        }
    }
}
