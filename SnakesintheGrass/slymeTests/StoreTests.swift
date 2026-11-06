//
//  StoreTests.swift
//  slymeTests
//
//  StoreKitTest against slyme.storekit: products load with prices, buying a
//  skin unlocks only that skin, a pack unlocks everything it covers.
//

import XCTest
import StoreKit
import StoreKitTest
import SpriteKit
import UIKit
@testable import slyme

@MainActor
final class StoreTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!
    private var entitlements: EntitlementStore!
    private var store: StoreManager!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "slyme")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defaults = UserDefaults(suiteName: "slymeTests")!
        defaults.removePersistentDomain(forName: "slymeTests")
        entitlements = EntitlementStore(defaults: defaults)
        store = StoreManager(entitlements: entitlements)
    }

    func testAllProductsLoadWithPrices() async {
        await store.loadProducts()
        XCTAssertEqual(Set(store.products.keys), Set(EntitlementStore.allProductIDs))
        XCTAssertEqual(store.product(for: "com.ysdwysd.skin.gold")?.price, Decimal(string: "0.99"))
        XCTAssertEqual(store.product(for: "com.ysdwysd.map.box")?.price, Decimal(string: "1.99"))
        XCTAssertEqual(store.product(for: EntitlementStore.packEverythingID)?.price, Decimal(string: "5.99"))
        XCTAssertNotNil(store.displayPrice(for: "com.ysdwysd.skin.gold"))
    }

    func testBuyingSkinUnlocksOnlyThatSkin() async {
        XCTAssertFalse(entitlements.isUnlocked(skinID: "gold"))
        let outcome = await store.purchase(productID: EntitlementStore.productID(skinID: "gold"))
        XCTAssertEqual(outcome, .purchased)
        XCTAssertTrue(entitlements.isOwnedViaStore(skinID: "gold"))
        XCTAssertFalse(entitlements.isOwnedViaStore(skinID: "ghost"))
        XCTAssertFalse(entitlements.isOwnedViaStore(mapID: "box"))
        // Fresh launch restores from currentEntitlements.
        let other = EntitlementStore(defaults: defaults)
        defaults.removeObject(forKey: "cosmetics.unlockedIDs")
        await StoreManager(entitlements: other).refreshEntitlements()
        XCTAssertTrue(other.isOwnedViaStore(skinID: "gold"))
    }

    func testSkinsPackUnlocksAllPaidSkins() async {
        let outcome = await store.purchase(productID: EntitlementStore.packSkinsID)
        XCTAssertEqual(outcome, .purchased)
        for skin in EntitlementStore.premiumSkins { XCTAssertTrue(entitlements.isOwnedViaStore(skinID: skin.id)) }
        for map in EntitlementStore.premiumMaps { XCTAssertFalse(entitlements.isOwnedViaStore(mapID: map.id)) }
    }

    func testRefundRemovesEntitlement() async throws {
        _ = await store.purchase(productID: EntitlementStore.productID(mapID: "box"))
        XCTAssertTrue(entitlements.isOwnedViaStore(mapID: "box"))
        let tx = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == "com.ysdwysd.map.box" })
        try session.refundTransaction(identifier: UInt(tx.identifier))
        // The revocation lands asynchronously; give it a moment.
        for _ in 0..<20 where entitlements.isOwnedViaStore(mapID: "box") {
            try await Task.sleep(nanoseconds: 200_000_000)
            await store.refreshEntitlements()
        }
        XCTAssertFalse(entitlements.isOwnedViaStore(mapID: "box"))
    }

    func testFailedPurchaseDoesNotUnlock() async throws {
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        let outcome = await store.purchase(productID: EntitlementStore.productID(skinID: "indigo"))
        if case .failed = outcome {} else { XCTFail("expected failure, got \(outcome)") }
        XCTAssertFalse(entitlements.isOwnedViaStore(skinID: "indigo"))
    }

    /// Screenshot helper, skipped unless /tmp/slyme_shoot exists. Shows the
    /// customize screen and a purchase sheet in the host app with the
    /// StoreKit config prices loaded, holding each for a few seconds so
    /// `xcrun simctl io booted screenshot` can capture it.
    func testZZShowSheetForScreenshots() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/slyme_shoot"))
        await StoreManager.shared.loadProducts()
        let view = try XCTUnwrap(Self.findSKView())
        let wasUnlockAll = EntitlementStore.shared.debugUnlockAll
        EntitlementStore.shared.debugUnlockAll = false
        defer { EntitlementStore.shared.debugUnlockAll = wasUnlockAll }
        for (page, key) in [(CustomizeScene.Page.skins, nil), (.skins, "skin.gold"), (.maps, "map.box")] as [(CustomizeScene.Page, String?)] {
            let scene = CustomizeScene(size: view.bounds.size, page: page)
            scene.scaleMode = .resizeFill
            view.presentScene(scene)
            try await Task.sleep(nanoseconds: 500_000_000)
            if let key { scene.debugShowSheet(key) }
            FileManager.default.createFile(atPath: "/tmp/slyme_shoot_ready_\(key ?? "customize")", contents: nil)
            try await Task.sleep(nanoseconds: 6_000_000_000)
        }
    }


    /// Writes portrait + landscape menu PNGs to /tmp (no device rotate).
    /// Skipped unless /tmp/slyme_shoot_menu exists.
    func testZZShowMenuOrientations() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/slyme_shoot_menu"))
        for (label, size) in [("portrait", CGSize(width: 390, height: 844)),
                              ("landscape", CGSize(width: 844, height: 390))] {
            let view = SKView(frame: CGRect(origin: .zero, size: size))
            let scene = MainMenu(size: size)
            scene.scaleMode = .resizeFill
            view.presentScene(scene)
            scene.didChangeSize(.zero)
            try await Task.sleep(nanoseconds: 150_000_000)
            scene.didChangeSize(size)
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertLessThanOrEqual(scene.children.count, 8)
            XCTAssertFalse(scene.children.contains { $0.name == "twoPlayerButton" })
            let mid = size.width / 2
            for node in scene.children {
                XCTAssertEqual(node.position.x, mid, accuracy: 1.5)
            }
            guard let tex = view.texture(from: scene) else {
                XCTFail("could not render \(label)"); continue
            }
            let img = tex.cgImage()
            let ui = UIImage(cgImage: img)
            let url = URL(fileURLWithPath: "/tmp/slyme-menu-\(label).png")
            try XCTUnwrap(ui.pngData()).write(to: url)
            FileManager.default.createFile(atPath: "/tmp/slyme_shoot_ready_menu_\(label)", contents: nil)
        }
    }

    private static func findSKView() -> SKView? {
        func walk(_ v: UIView) -> SKView? {
            if let s = v as? SKView { return s }
            for c in v.subviews { if let s = walk(c) { return s } }
            return nil
        }
        for case let ws as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in ws.windows { if let s = walk(w) { return s } }
        }
        return nil
    }
}
