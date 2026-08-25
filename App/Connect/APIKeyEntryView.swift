import SwiftUI

/// Sheet for providers that authenticate with a pasted key.
///
/// The key is verified against the provider's API before it is kept, so a typo
/// surfaces here instead of as an empty card on the dashboard.
struct APIKeyEntryView: View {
    let provider: ProviderID
    /// Returns an error message, or nil on success.
    let onSubmit: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var busy = false
    @State private var error: String?

    private var config: APIKeyConfig? {
        if case .apiKey(let c) = ProviderRegistry.provider(provider).auth { return c }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(config?.placeholder ?? "API key", text: $key)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("\(provider.displayName) API key")
                } footer: {
                    Text(config?.instructions ?? "")
                }

                if let urlString = config?.dashboardURL, let url = URL(string: urlString) {
                    Section {
                        Link(destination: url) {
                            Label("Open \(provider.displayName) dashboard",
                                  systemImage: "arrow.up.right.square")
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Connect \(provider.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Connect") { submit() }
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            let result = await onSubmit(key)
            busy = false
            if let result {
                error = result
            } else {
                dismiss()
            }
        }
    }
}
