//
//  EntitlementStore.swift
//  slyme
//
//  Who owns what, and what's selected. UserDefaults-backed for now.
//
//  StoreKit 2 lives in StoreManager. It reports the verified product ids the
//  player owns via `applyStoreEntitlements(_:)`; this file is the single
//  source of truth for product ids and what each product unlocks.
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
        // Seasonal free maps hide outside their window (unless previously selected
        // as the saved pick — still require availability for gameplay selection).
        if !map.isAvailable() { return false }
        return isUnlocked(tier: map.tier, key: "map.\(mapID)")
    }

    /// Owned through a purchase (ignores free tier and debug unlock-all).
    func isOwnedViaStore(skinID: String) -> Bool { unlockedIDs.contains("skin.\(skinID)") }
    func isOwnedViaStore(mapID: String) -> Bool { unlockedIDs.contains("map.\(mapID)") }

    private func isUnlocked(tier: CosmeticTier, key: String) -> Bool {
        if tier == .free { return true }
        #if DEBUG
        if debugUnlockAll { return true }
        #endif
        return unlockedIDs.contains(key)
    }

    /// Grant one item locally (used after a verified purchase, before the
    /// full entitlement refresh lands).
    func grant(skinID: String) { unlockedIDs.insert("skin.\(skinID)") }
    func grant(mapID: String) { unlockedIDs.insert("map.\(mapID)") }

    /// Replace ownership with what StoreKit says the player owns (verified,
    /// non-revoked `Transaction.currentEntitlements`). Packs expand to items.
    /// Refunded/revoked products disappear here too.
    func applyStoreEntitlements(_ productIDs: Set<String>) {
        var keys = Set<String>()
        for pid in productIDs { keys.formUnion(Self.itemKeys(forProductID: pid)) }
        if keys != unlockedIDs { unlockedIDs = keys }
    }

    // MARK: Product ids (single source of truth)

    static let productPrefix = "com.ysdwysd."
    static let packSkinsID = productPrefix + "pack.skins"
    static let packMapsID = productPrefix + "pack.maps"
    static let packEverythingID = productPrefix + "pack.everything"

    static func productID(skinID: String) -> String { productPrefix + "skin.\(skinID)" }
    static func productID(mapID: String) -> String { productPrefix + "map.\(mapID)" }

    static var premiumSkins: [Skin] { SkinCatalog.all.filter { $0.tier == .premium } }
    static var premiumMaps: [GameMap] { MapCatalog.all.filter { $0.tier == .premium } }

    /// Every product the app sells, singles first, then packs.
    static var allProductIDs: [String] {
        premiumSkins.map { productID(skinID: $0.id) }
            + premiumMaps.map { productID(mapID: $0.id) }
            + [packSkinsID, packMapsID, packEverythingID]
    }

    /// Ownership keys ("skin.gold", "map.box") a product unlocks.
    static func itemKeys(forProductID pid: String) -> Set<String> {
        let skins = Set(premiumSkins.map { "skin.\($0.id)" })
        let maps = Set(premiumMaps.map { "map.\($0.id)" })
        switch pid {
        case packSkinsID: return skins
        case packMapsID: return maps
        case packEverythingID: return skins.union(maps)
        default:
            guard pid.hasPrefix(productPrefix) else { return [] }
            let key = String(pid.dropFirst(productPrefix.count))
            return skins.contains(key) || maps.contains(key) ? [key] : []
        }
    }

    /// Packs that cover an item, smallest first ("pack.skins" then "pack.everything").
    static func packIDs(covering key: String) -> [String] {
        [packSkinsID, packMapsID, packEverythingID].filter { itemKeys(forProductID: $0).contains(key) }
    }

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
