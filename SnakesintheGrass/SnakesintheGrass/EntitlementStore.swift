//
//  EntitlementStore.swift
//  slyme
//
//  Who owns what, and what's selected. UserDefaults-backed for now.
//
//  STOREKIT PLUGS IN HERE: replace `unlockedIDs` persistence with
//  StoreKit 2 `Transaction.currentEntitlements` (map product IDs -> item IDs
//  via `productID(for:)`), and call `grant(_:)` from the purchase flow.
//  Nothing else in the app needs to change.
//

import Foundation

final class EntitlementStore {
    static let shared = EntitlementStore()

    private let defaults: UserDefaults
    private enum Key {
        static let unlocked = "cosmetics.unlockedIDs"
        static let skin = "cosmetics.selectedSkin"
        static let map = "cosmetics.selectedMap"
        static let debugAll = "cosmetics.debugUnlockAll"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pruneRemovedItems()
    }

    /// Drop selections/unlocks for items no longer in the catalogs (e.g. "signal").
    private func pruneRemovedItems() {
        if let id = defaults.string(forKey: Key.skin), SkinCatalog.skin(id: id) == nil {
            defaults.removeObject(forKey: Key.skin)
        }
        if let id = defaults.string(forKey: Key.map), MapCatalog.map(id: id) == nil {
            defaults.removeObject(forKey: Key.map)
        }
        let ids = unlockedIDs
        let kept = ids.filter { key in
            if key.hasPrefix("skin.") { return SkinCatalog.skin(id: String(key.dropFirst(5))) != nil }
            if key.hasPrefix("map.") { return MapCatalog.map(id: String(key.dropFirst(4))) != nil }
            return true
        }
        if kept != ids { unlockedIDs = kept }
    }

    // MARK: Ownership

    private var unlockedIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.unlocked) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.unlocked) }
    }

    func isUnlocked(skinID: String) -> Bool {
        guard let skin = SkinCatalog.skin(id: skinID) else { return false }
        return isUnlocked(tier: skin.tier, key: "skin.\(skinID)")
    }

    func isUnlocked(mapID: String) -> Bool {
        guard let map = MapCatalog.map(id: mapID) else { return false }
        return isUnlocked(tier: map.tier, key: "map.\(mapID)")
    }

    private func isUnlocked(tier: CosmeticTier, key: String) -> Bool {
        if tier == .free { return true }
        #if DEBUG
        if debugUnlockAll { return true }
        #endif
        return unlockedIDs.contains(key)
    }

    /// Single entry point for granting items (future: StoreKit transaction handler).
    func grant(skinID: String) { unlockedIDs.insert("skin.\(skinID)") }
    func grant(mapID: String) { unlockedIDs.insert("map.\(mapID)") }

    /// Suggested App Store product IDs (not live yet).
    static func productID(skinID: String) -> String { "com.ysdwysd.skin.\(skinID)" }
    static func productID(mapID: String) -> String { "com.ysdwysd.map.\(mapID)" }

    // MARK: Selection (falls back to defaults if locked or removed)

    var selectedSkin: Skin {
        get {
            let id = defaults.string(forKey: Key.skin) ?? SkinCatalog.defaultID
            if let s = SkinCatalog.skin(id: id), isUnlocked(skinID: id) { return s }
            return SkinCatalog.skin(id: SkinCatalog.defaultID)!
        }
        set { if isUnlocked(skinID: newValue.id) { defaults.set(newValue.id, forKey: Key.skin) } }
    }

    var selectedMap: GameMap {
        get {
            let id = defaults.string(forKey: Key.map) ?? MapCatalog.defaultID
            if let m = MapCatalog.map(id: id), isUnlocked(mapID: id) { return m }
            return MapCatalog.map(id: MapCatalog.defaultID)!
        }
        set { if isUnlocked(mapID: newValue.id) { defaults.set(newValue.id, forKey: Key.map) } }
    }

    // MARK: Debug

    #if DEBUG
    var debugUnlockAll: Bool {
        get { defaults.bool(forKey: Key.debugAll) }
        set { defaults.set(newValue, forKey: Key.debugAll) }
    }
    #endif
}
