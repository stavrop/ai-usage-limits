import SwiftUI
import StoreKit

/// Three tips, buying nothing. Shown from About and from the support prompt.
///
/// The screen goes out of its way to say that a tip unlocks nothing — partly
/// because it's true, partly because an in-app purchase that quietly implies
/// features is exactly what guideline 3.1.1 exists to stop.
struct TipJarView: View {
    /// Set when presented as a sheet, so it can dismiss itself.
    var showsDoneButton = false

    @Environment(\.dismiss) private var dismiss
    @State private var jar = TipJar()

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.pink)
                    Text(jar.thanked || SupportPromptState.hasTipped
                         ? "Thank you" : "Leave a tip")
                        .font(.title2).bold()
                    Text(jar.thanked || SupportPromptState.hasTipped
                         ? "It genuinely helps. The app stays free either way."
                         : "AI Usage Limits is free, has no ads, has no server and "
                         + "collects nothing about you. If it saves you from "
                         + "running out mid-task, you can say thanks here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)

            Section {
                if jar.loading && jar.products.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                } else if jar.products.isEmpty {
                    Text("Tips aren't available right now. This usually means the "
                       + "App Store is unreachable — everything else in the app "
                       + "works offline from its last reading.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(jar.products, id: \.id) { product in
                        TipRow(product: product,
                               busy: jar.purchasing == product.id,
                               disabled: jar.purchasing != nil) {
                            Task { await jar.purchase(product) }
                        }
                    }
                }
            } footer: {
                Text("A tip unlocks nothing. There are no paid features, no Pro "
                   + "tier and nothing to restore — every part of the app is "
                   + "already yours.")
            }

            if let error = jar.lastError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Tip jar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await jar.load() }
        .task { await jar.watchForUpdates() }
    }
}

private struct TipRow: View {
    let product: Product
    let busy: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                if !product.description.isEmpty {
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: action) {
                if busy {
                    ProgressView()
                } else {
                    Text(product.displayPrice).monospacedDigit()
                }
            }
            .buttonStyle(.bordered)
            .disabled(disabled)
        }
    }
}

/// Wraps the jar for sheet presentation.
struct TipJarSheet: View {
    var body: some View {
        NavigationStack { TipJarView(showsDoneButton: true) }
    }
}
