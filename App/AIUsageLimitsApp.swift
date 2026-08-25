import SwiftUI

@main
struct AIUsageLimitsApp: App {
    init() {
        // Drives the (once-only) support prompt, which waits for the app to have
        // been genuinely useful before asking for anything.
        SupportPromptState.recordLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
