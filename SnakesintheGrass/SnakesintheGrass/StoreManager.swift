//
//  StoreManager.swift
//  slyme
//
//  StoreKit 2: loads products, buys, verifies, finishes, listens for
//  updates (Ask to Buy, refunds, other devices) and restores. Ownership is
//  handed to EntitlementStore, which knows what each product unlocks.
//

import Foundation
import StoreKit

extension Notification.Name {
    /// Posted on the main thread when products or ownership change.
    static let storeDidChange = Notification.Name("slyme.storeDidChange")
}

@MainActor
final class StoreManager {
    static let shared = StoreManager()

    enum PurchaseOutcome: Equatable {
        case purchased
        case pending      // Ask to Buy / SCA: unlocks later via Transaction.updates
        case cancelled
        case failed(String)

        /// Short lowercase line for the UI (nil = say nothing).
        var message: String? {
            switch self {
            case .purchased: return "unlocked. enjoy."
            case .pending: return "waiting for approval."
            case .cancelled: return nil
            case .failed(let m): return m
            }
        }
    }

    private(set) var products: [String: Product] = [:]
    private(set) var isLoading = false
    private(set) var lastLoadFailed = false
    private var updatesTask: Task<Void, Never>?
    private let entitlements: EntitlementStore

    init(entitlements: EntitlementStore = .shared) {
        self.entitlements = entitlements
    }

    /// Call once at launch. Safe to call again (no-op if already started).
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    func product(for id: String) -> Product? { products[id] }

    /// Localized price, or nil while products are missing (offline).
    func displayPrice(for id: String) -> String? { products[id]?.displayPrice }

    // MARK: Products

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; notify() }
        do {
            let list = try await Product.products(for: EntitlementStore.allProductIDs)
            for p in list { products[p.id] = p }
            lastLoadFailed = list.isEmpty
        } catch {
            lastLoadFailed = true
        }
    }

    // MARK: Purchase

    func purchase(productID: String) async -> PurchaseOutcome {
        if products[productID] == nil { await loadProducts() }
        guard let product = products[productID] else {
            return .failed("store unavailable. check your connection.")
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("couldn't verify purchase.")
                }
                apply(transaction)
                await transaction.finish()
                await refreshEntitlements()
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("purchase failed. try again.")
            }
        } catch let error as StoreKitError {
            switch error {
            case .userCancelled: return .cancelled
            case .networkError: return .failed("you're offline. try again.")
            case .notAvailableInStorefront: return .failed("not available in your region.")
            case .notEntitled: return .failed("purchases are turned off on this device.")
            default: return .failed("purchase failed. try again.")
            }
        } catch Product.PurchaseError.purchaseNotAllowed {
            return .failed("purchases are turned off on this device.")
        } catch {
            return .failed("purchase failed. try again.")
        }
    }

    // MARK: Restore

    /// "restore purchases": forces a sync with the App Store (may ask the
    /// player to sign in), then re-reads entitlements.
    func restore() async -> String {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return ""
        } catch {
            await refreshEntitlements()
            return "couldn't reach the app store."
        }
        let before = ownedCount
        await refreshEntitlements()
        _ = before; return ownedCount > 0 ? "purchases restored." : "nothing to restore."
    }

    private var ownedCount: Int {
        EntitlementStore.premiumSkins.filter { entitlements.isOwnedViaStore(skinID: $0.id) }.count
            + EntitlementStore.premiumMaps.filter { entitlements.isOwnedViaStore(mapID: $0.id) }.count
    }

    // MARK: Entitlements

    /// Rebuild ownership from verified, non-revoked current entitlements.
    /// Works offline from StoreKit's on-device cache.
    func refreshEntitlements() async {
        var owned = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil, t.productType == .nonConsumable {
                owned.insert(t.productID)
            }
        }
        entitlements.applyStoreEntitlements(owned)
        notify()
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func apply(_ t: Transaction) {
        guard t.revocationDate == nil else { return }
        for key in EntitlementStore.itemKeys(forProductID: t.productID) {
            if key.hasPrefix("skin.") { entitlements.grant(skinID: String(key.dropFirst(5))) }
            if key.hasPrefix("map.") { entitlements.grant(mapID: String(key.dropFirst(4))) }
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .storeDidChange, object: nil)
    }
}
