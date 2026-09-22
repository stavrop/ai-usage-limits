import SwiftUI

struct SupportPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showTipJar = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(.pink)

            Text("Enjoying AI Usage Limits?")
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            Text("It's free, has no ads and collects nothing about you. If it's "
               + "useful, a star on GitHub genuinely helps — it's how other "
               + "people find it. A tip is welcome too, and unlocks nothing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    support(Links.github)
                } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showTipJar = true
                } label: {
                    Label("Leave a tip", systemImage: "heart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("No thanks") { dismiss() }
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        // Showing it schedules the next ask ~a month out; tapping through
        // pushes that to ~a year.
        .onAppear { SupportPromptState.markShown() }
        .sheet(isPresented: $showTipJar) {
            TipJarSheet()
        }
    }

    private func support(_ url: URL) {
        SupportPromptState.markSupported()
        openURL(url)
        dismiss()
    }
}
