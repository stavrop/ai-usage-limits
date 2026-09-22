import Foundation
import StoreKit

/// The tip jar: three consumable in-app purchases that buy nothing.
///
/// Deliberately not an entitlement. Nothing in the app is gated, so there is no
/// `currentEntitlements` to consult — StoreKit does not report consumables there
/// anyway — and no restore: a consumable is spent the moment it is finished. The
/// only thing kept is a local flag, so someone who has already helped isn't asked
/// again (see `SupportPromptState.markTipped`).
///
/// This replaces the external "Buy me a coffee" link, which was removed in build 6
/// under guideline 3.1.1: a donation path other than In-App Purchase is only
/// allowed on some storefronts, and the app ships to 174.
@Observable
@MainActor
final class TipJar {

    /// Small to large. Order matters — the UI shows them in this order and falls
    /// back to it when StoreKit returns products in its own.
    static let productIDs = [
        "com.stavrop.ailimits.tip.small",
        "com.stavrop.ailimits.tip.medium",
        "com.stavrop.ailimits.tip.large",
    ]

    private(set) var products: [Product] = []
    private(set) var loading = false
    /// Product id currently being bought, if any — drives the row's spinner.
    private(set) var purchasing: String?
    /// Set after a successful purchase so the view can say thank you.
    var thanked = false
    /// Why the last attempt didn't complete (nil on success or plain cancel).
    var lastError: String?

    /// Ask-to-Buy and other deferred purchases arrive here rather than from
    /// `purchase()`. Finish them or StoreKit re-delivers them forever.
    ///
    /// Driven from the view's `.task`, so it is cancelled when the screen goes
    /// away — an owned `Task` handle can't be cancelled from `deinit`, which is
    /// nonisolated while this type is not.
    func watchForUpdates() async {
        for await update in Transaction.updates {
            guard case .verified(let t) = update else { continue }
            await t.finish()
            guard Self.productIDs.contains(t.productID) else { continue }
            SupportPromptState.markTipped()
            thanked = true
        }
    }

    func load() async {
        guard products.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { a, b in
                let ia = Self.productIDs.firstIndex(of: a.id) ?? 0
                let ib = Self.productIDs.firstIndex(of: b.id) ?? 0
                return ia < ib
            }
        } catch {
            lastError = Self.describe(error)
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        lastError = nil
        purchasing = product.id
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let t):
                    // A consumable has to be finished or it is redelivered on
                    // every launch. There is nothing to grant first: the thanks
                    // IS the product.
                    await t.finish()
                    SupportPromptState.markTipped()
                    thanked = true
                    return true
                case .unverified(_, let err):
                    lastError = "That purchase could not be verified: \(err.localizedDescription)"
                    return false
                }
            case .userCancelled:
                return false                       // not an error worth showing
            case .pending:
                // Ask to Buy, or a payment awaiting approval: it lands in
                // `Transaction.updates` if and when it clears.
                lastError = "Waiting for approval — the tip will go through once it's approved."
                return false
            @unknown default:
                lastError = "Unknown purchase result."
                return false
            }
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    /// Turn a StoreKit error into something a person can act on.
    static func describe(_ error: Error) -> String {
        if let e = error as? Product.PurchaseError { return e.localizedDescription }
        if let e = error as? StoreKitError { return e.localizedDescription }
        return error.localizedDescription
    }
}
