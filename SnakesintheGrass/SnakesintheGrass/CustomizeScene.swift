//
//  CustomizeScene.swift
//  slyme
//
//  Skins and maps. Flat ink on black, no borders. Layout comes from the
//  safe-area rect, so it adapts to iPhone, iPad and iPhone Duo.
//

import SpriteKit
import UIKit

final class CustomizeScene: SKScene {
    enum Page { case skins, maps }

    private var page: Page
    /// Current pager page when there are more cards than fit.
    private var pageIndex = 0
    private let store = EntitlementStore.shared
    private let font = "CourierNewPS-BoldMT"
    private let toast = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
    private let selection = UISelectionFeedbackGenerator()
    private let shop = StoreManager.shared

    /// Locked item the purchase sheet is showing ("skin.gold" / "map.box").
    private var sheetKey: String?
    private var sheetMessage: String?
    private var busy = false
    private var layoutGeneration = 0
    private var storeObserver: NSObjectProtocol?

    init(size: CGSize, page: Page = .skins) {
        self.page = page
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        selection.prepare()
        storeObserver = NotificationCenter.default.addObserver(forName: .storeDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.build() }
        }
        if shop.products.isEmpty { Task { await shop.loadProducts() } }
        let b = view.bounds.size
        if b.width > 1, b.height > 1, (abs(b.width - size.width) > 0.5 || abs(b.height - size.height) > 0.5) {
            size = b
        }
        build()
        DispatchQueue.main.async { [weak self] in
            guard let self, let v = self.view else { return }
            let b = v.bounds.size
            if b.width > 1, b.height > 1, (abs(b.width - self.size.width) > 0.5 || abs(b.height - self.size.height) > 0.5) {
                self.size = b
            }
            self.build()
        }
    }

    override func willMove(from view: SKView) {
        if let o = storeObserver { NotificationCenter.default.removeObserver(o) }
        storeObserver = nil
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Rotation: insets often lag the size flip — rebuild now and once more after.
        if view != nil { requestBuild() }
    }

    private func requestBuild() {
        layoutGeneration &+= 1
        let gen = layoutGeneration
        if let v = view {
            let b = v.bounds.size
            if b.width > 1, b.height > 1, (abs(b.width - size.width) > 0.5 || abs(b.height - size.height) > 0.5) {
                size = b
            }
        }
        build()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.layoutGeneration == gen, let v = self.view else { return }
            let b = v.bounds.size
            if b.width > 1, b.height > 1, (abs(b.width - self.size.width) > 0.5 || abs(b.height - self.size.height) > 0.5) {
                self.size = b
            }
            self.build()
        }
    }

    private var safeRect: CGRect {
        let i = view?.safeAreaInsets ?? .zero
        // Full safe area (no hinge half). Cards stay centered on Duo flat/outer.
        return CGRect(x: i.left, y: i.bottom,
                      width: max(0, size.width - i.left - i.right),
                      height: max(0, size.height - i.top - i.bottom)).insetBy(dx: 24, dy: 16)
    }

    // MARK: Build

    private func build() {
        removeAllChildren()
        let r = safeRect
        guard r.width > 0, r.height > 0 else { return }

        let title = label("customize", size: 30, color: .systemIndigo)
        title.position = CGPoint(x: r.midX, y: r.maxY - 40)
        title.name = "title"
        addChild(title)

        let tabsY = r.maxY - 84
        let skinsTab = label("skins", size: 20, color: page == .skins ? Palette.paper : .darkGray)
        skinsTab.position = CGPoint(x: r.midX - 60, y: tabsY)
        skinsTab.name = "tab.skins"
        addChild(skinsTab)
        let mapsTab = label("maps", size: 20, color: page == .maps ? Palette.paper : .darkGray)
        mapsTab.position = CGPoint(x: r.midX + 60, y: tabsY)
        mapsTab.name = "tab.maps"
        addChild(mapsTab)

        let back = label("back", size: 20, color: .darkGray)
        back.position = CGPoint(x: r.midX, y: r.minY + 16)
        back.name = "back"
        addChild(back)

        toast.fontSize = 14
        toast.fontColor = UIColor(white: 1, alpha: 0.45)
        toast.position = CGPoint(x: r.midX, y: r.minY + 78)
        toast.alpha = 0
        toast.text = ""
        addChild(toast)

        let restore = label("restore purchases", size: 13, color: UIColor(white: 1, alpha: 0.45))
        restore.position = CGPoint(x: r.midX, y: r.minY + 50)
        restore.name = "restore"
        addChild(restore)

        // Grid area between tabs and pager/toast.
        let skins = SkinCatalog.visible(owned: { store.isUnlocked(skinID: $0.id) })
        let maps = MapCatalog.visible(owned: { store.isUnlocked(mapID: $0.id) })
        let count = page == .skins ? skins.count : maps.count
        // Footer band (restore/back/pager) is ~100pt; use the rest for cards.
        let grid = CGRect(x: r.minX, y: r.minY + 100, width: r.width, height: max(0, (tabsY - 28) - (r.minY + 100)))
        let columns = grid.width >= 600 ? 4 : (grid.width >= 420 ? 3 : 2)
        let gap: CGFloat = 16
        let cellW = (grid.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        // Cards never shrink below this; extra items go to the next page.
        let minCellH: CGFloat = min(120, cellW * 1.1)
        let maxRows = max(1, Int((grid.height + gap) / (minCellH + gap)))
        let perPage = columns * maxRows
        let pageCount = max(1, Int(ceil(Double(count) / Double(perPage))))
        pageIndex = min(max(0, pageIndex), pageCount - 1)
        let range = (pageIndex * perPage)..<min(count, (pageIndex + 1) * perPage)
        let rowsN = max(1, Int(ceil(Double(range.count) / Double(columns))))
        let rowsForSize = pageCount > 1 ? maxRows : rowsN
        let cellH = min((grid.height - gap * CGFloat(rowsForSize - 1)) / CGFloat(rowsForSize),
                        page == .maps ? cellW * 1.55 : cellW * 1.25)
        let totalH = cellH * CGFloat(rowsN) + gap * CGFloat(rowsN - 1)
        let top = pageCount > 1 ? grid.maxY : grid.midY + totalH / 2

        for (n, i) in range.enumerated() {
            let col = n % columns, row = n / columns
            let frame = CGRect(x: grid.minX + CGFloat(col) * (cellW + gap),
                               y: top - CGFloat(row + 1) * cellH - CGFloat(row) * gap,
                               width: cellW, height: cellH)
            addChild(page == .skins ? skinCard(skins[i], in: frame)
                                    : mapCard(maps[i], in: frame))
        }

        if pageCount > 1 {
            let y = r.minY + 104
            let prev = label("<", size: 22, color: pageIndex > 0 ? Palette.paper : .darkGray)
            prev.position = CGPoint(x: r.midX - 70, y: y)
            prev.name = "page.prev"
            addChild(prev)
            let info = label("\(pageIndex + 1)/\(pageCount)", size: 14, color: UIColor(white: 1, alpha: 0.45))
            info.position = CGPoint(x: r.midX, y: y)
            addChild(info)
            let next = label(">", size: 22, color: pageIndex < pageCount - 1 ? Palette.paper : .darkGray)
            next.position = CGPoint(x: r.midX + 70, y: y)
            next.name = "page.next"
            addChild(next)
        }

        if let key = sheetKey { addChild(purchaseSheet(for: key, in: r)) }
    }

    // MARK: Purchase sheet

    private func displayName(for key: String) -> String {
        if key.hasPrefix("skin."), let s = SkinCatalog.skin(id: String(key.dropFirst(5))) { return s.name }
        if key.hasPrefix("map."), let m = MapCatalog.map(id: String(key.dropFirst(4))) { return m.name }
        return key
    }

    private func productID(for key: String) -> String {
        key.hasPrefix("skin.") ? EntitlementStore.productID(skinID: String(key.dropFirst(5)))
                               : EntitlementStore.productID(mapID: String(key.dropFirst(4)))
    }

    private func packTitle(_ pid: String) -> String {
        switch pid {
        case EntitlementStore.packSkinsID: return "unlock all skins"
        case EntitlementStore.packMapsID: return "unlock all maps"
        default: return "unlock everything"
        }
    }

    private func priceText(_ pid: String) -> String {
        if let p = shop.displayPrice(for: pid) { return p }
        return shop.isLoading ? "..." : "--"
    }

    /// Small sheet over a dimmed screen: name, price, buy, pack offers, cancel.
    private func purchaseSheet(for key: String, in r: CGRect) -> SKNode {
        let root = SKNode()
        root.zPosition = 100
        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.75), size: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.name = "sheet.dim"
        root.addChild(dim)

        let packs = EntitlementStore.packIDs(covering: key)
        let w = min(r.width, 360)
        let h: CGFloat = 230 + CGFloat(packs.count) * 34
        let panel = SKSpriteNode(color: UIColor(white: 0.09, alpha: 1), size: CGSize(width: w, height: h))
        panel.position = CGPoint(x: r.midX, y: r.midY)
        panel.name = "sheet.panel"
        root.addChild(panel)

        let pid = productID(for: key)
        var y = h / 2 - 40
        func add(_ text: String, _ size: CGFloat, _ color: UIColor, _ name: String? = nil, gap: CGFloat) {
            let l = label(text, size: size, color: color)
            l.position = CGPoint(x: 0, y: y)
            l.name = name ?? "sheet.panel"
            panel.addChild(l)
            y -= gap
        }
        let muted = UIColor(white: 1, alpha: 0.45)
        add(displayName(for: key), 24, Palette.paper, gap: 28)
        add(key.hasPrefix("skin.") ? "snake skin" : "map", 12, muted, gap: 44)
        let canBuy = shop.product(for: pid) != nil && !busy
        add(busy ? "..." : "buy \(priceText(pid))", 22, canBuy ? Palette.orange : .darkGray, "sheet.buy", gap: 40)
        for pack in packs {
            let can = shop.product(for: pack) != nil && !busy
            add("\(packTitle(pack)) \(priceText(pack))", 14, can ? Palette.paper : .darkGray, "sheet.pack:\(pack)", gap: 34)
        }
        add(sheetMessage ?? (shop.lastLoadFailed && shop.products.isEmpty ? "store unavailable. check your connection." : " "),
            12, muted, gap: 34)
        add("cancel", 16, .darkGray, "sheet.cancel", gap: 0)
        return root
    }

    private func openSheet(_ key: String) {
        sheetKey = key
        sheetMessage = nil
        selection.selectionChanged()
        if shop.products.isEmpty { Task { await shop.loadProducts() } }
        build()
    }

    #if DEBUG
    /// Testing/screenshots only.
    func debugShowSheet(_ key: String) { openSheet(key) }
    #endif

    private func closeSheet() {
        sheetKey = nil
        sheetMessage = nil
        build()
    }

    private func buy(_ pid: String, for key: String) {
        guard !busy else { return }
        busy = true
        sheetMessage = nil
        build()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.shop.purchase(productID: pid)
            self.busy = false
            if outcome == .purchased {
                // Select what they just bought.
                if key.hasPrefix("skin."), let s = SkinCatalog.skin(id: String(key.dropFirst(5))) { self.store.selectedSkin = s }
                if key.hasPrefix("map."), let m = MapCatalog.map(id: String(key.dropFirst(4))) { self.store.selectedMap = m }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.closeSheet()
                if let m = outcome.message { self.showToast(m) }
            } else if outcome == .cancelled {
                self.build()
            } else {
                self.sheetMessage = outcome.message
                self.build()
            }
        }
    }

    private func restorePurchases() {
        guard !busy else { return }
        busy = true
        showToast("restoring...")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let msg = await self.shop.restore()
            self.busy = false
            self.build()
            if !msg.isEmpty { self.showToast(msg) }
        }
    }

    private func label(_ text: String, size: CGFloat, color: UIColor) -> SKLabelNode {
        let l = SKLabelNode(text: text)
        l.fontName = font
        l.fontSize = size
        l.fontColor = color
        l.verticalAlignmentMode = .center
        return l
    }

    /// Card: preview on top, name + state underneath. No outlines.
    private func card(name: String, nodeName: String, selected: Bool, locked: Bool,
                      preview: SKNode, in frame: CGRect) -> SKNode {
        let root = SKNode()
        root.position = CGPoint(x: frame.midX, y: frame.midY)
        root.name = nodeName
        // Invisible hit area so the whole card is tappable.
        let hit = SKSpriteNode(color: .clear, size: frame.size)
        hit.name = nodeName
        root.addChild(hit)

        preview.position = CGPoint(x: 0, y: 14)
        preview.alpha = locked ? 0.35 : 1
        root.addChild(preview)

        let title = label(name, size: 14, color: selected ? Palette.paper : UIColor(white: 1, alpha: 0.45))
        title.position = CGPoint(x: 0, y: -frame.height / 2 + 22)
        title.name = nodeName
        root.addChild(title)

        if selected {
            let dot = SKShapeNode(circleOfRadius: 3)
            dot.fillColor = Palette.paper
            dot.strokeColor = .clear
            dot.position = CGPoint(x: 0, y: -frame.height / 2 + 6)
            root.addChild(dot)
        }
        if locked, let img = CustomizeScene.lockImage {
            // Small lock beside the name; the preview stays readable.
            let lock = SKSpriteNode(texture: SKTexture(image: img))
            let s: CGFloat = 12
            lock.size = CGSize(width: s * img.size.width / max(1, img.size.height), height: s)
            lock.position = CGPoint(x: title.frame.maxX + 12, y: title.position.y)
            lock.zPosition = 5
            root.addChild(lock)
        }
        return root
    }

    private func skinCard(_ skin: Skin, in frame: CGRect) -> SKNode {
        let preview = SKNode()
        let cell = min(frame.width / 6, (frame.height - 50) / 2.2)
        // A short snake: tail, two bodies, head, moving right.
        let parts = ["tail_left", "body_horizontal", "body_horizontal", "head_right"]
        for (i, name) in parts.enumerated() {
            let seg = skin.makeSegment(textureName: name, isHead: i == parts.count - 1,
                                       size: CGSize(width: cell, height: cell))
            seg.position = CGPoint(x: (CGFloat(i) - 1.5) * cell, y: 0)
            preview.addChild(seg)
        }
        return card(name: skin.name, nodeName: "skin.\(skin.id)",
                    selected: store.selectedSkin.id == skin.id,
                    locked: !store.isUnlocked(skinID: skin.id), preview: preview, in: frame)
    }

    private func mapCard(_ map: GameMap, in frame: CGRect) -> SKNode {
        let maxH = frame.height - 50, maxW = frame.width * 0.8
        let c = floor(min(maxW / CGFloat(MapCatalog.columns), maxH / CGFloat(MapCatalog.rows)) * 2) / 2
        let preview = MapRenderer.board(for: map, cell: max(1, c))
        if map.edges == .kill {
            // Note the rule in words rather than with a border.
            let tag = label("walls bite", size: 9, color: UIColor(white: 1, alpha: 0.45))
            tag.position = CGPoint(x: 0, y: 0)
            tag.zPosition = 4
            preview.addChild(tag)
        }
        return card(name: map.name, nodeName: "map.\(map.id)",
                    selected: store.selectedMap.id == map.id,
                    locked: !store.isUnlocked(mapID: map.id), preview: preview, in: frame)
    }

    /// SF Symbol lock rasterized in paper ink (tint isn't honored by SKTexture directly).
    private static let lockImage: UIImage? = {
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        guard let symbol = UIImage(systemName: "lock.fill", withConfiguration: config) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: symbol.size)
        return renderer.image { _ in
            symbol.withTintColor(UIColor(white: 1, alpha: 0.45), renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: symbol.size))
        }
    }()

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let names = nodes(at: touch.location(in: self)).compactMap { $0.name }
        if let key = sheetKey {
            // Sheet is modal: only its controls respond. Don't rely on hit order.
            if names.contains("sheet.buy") {
                buy(productID(for: key), for: key)
            } else if let pack = names.first(where: { $0.hasPrefix("sheet.pack:") }) {
                buy(String(pack.dropFirst("sheet.pack:".count)), for: key)
            } else if names.contains("sheet.cancel") || !names.contains("sheet.panel") {
                if !busy { closeSheet() }
            }
            return
        }
        guard let name = names.first else { return }
        if name == "restore" { restorePurchases(); return }

        if name == "back" {
            let menu = MainMenu(size: size)
            menu.scaleMode = .resizeFill
            view?.presentScene(menu, transition: .fade(withDuration: 0.4))
        } else if name == "page.prev" || name == "page.next" {
            pageIndex += name == "page.next" ? 1 : -1
            selection.selectionChanged()
            build()
        } else if name == "tab.skins" || name == "tab.maps" {
            page = name == "tab.skins" ? .skins : .maps
            pageIndex = 0
            selection.selectionChanged()
            build()
        } else if name == "title" {
            #if DEBUG
            // Testing only: tap the title to toggle unlock-all.
            if touch.tapCount == 3 {
                store.debugUnlockAll.toggle()
                build()
                showToast(store.debugUnlockAll ? "debug: all unlocked." : "debug: locks back on.")
            }
            #endif
        } else if name.hasPrefix("skin."), let skin = SkinCatalog.skin(id: String(name.dropFirst(5))) {
            if store.isUnlocked(skinID: skin.id) {
                store.selectedSkin = skin
                selection.selectionChanged()
                build()
            } else {
                openSheet(name)
            }
        } else if name.hasPrefix("map."), let map = MapCatalog.map(id: String(name.dropFirst(4))) {
            if store.isUnlocked(mapID: map.id) {
                store.selectedMap = map
                selection.selectionChanged()
                build()
            } else {
                openSheet(name)
            }
        }
    }

    private func showToast(_ text: String) {
        toast.removeAllActions()
        toast.text = text
        toast.alpha = 1
        toast.run(.sequence([.wait(forDuration: 1.6), .fadeOut(withDuration: 0.4)]))
    }
}

/// Draws a map's floor and obstacles. Shared by game and previews.
enum MapRenderer {
    /// A node centered on (0,0) sized columns*cell x rows*cell.
    static func board(for map: GameMap, cell: CGFloat, previewFloor: Bool = true) -> SKNode {
        let node = SKNode()
        let cols = MapCatalog.columns, rows = MapCatalog.rows
        let w = cell * CGFloat(cols), h = cell * CGFloat(rows)
        // In game a black floor is simply not drawn, so the classic look is untouched.
        if map.background != .black || previewFloor {
            let floor = SKSpriteNode(color: map.background == .black ? UIColor(white: 0.04, alpha: 1) : map.background,
                                     size: CGSize(width: w, height: h))
            node.addChild(floor)
        }
        if let checker = map.checker {
            for x in 0..<cols { for y in 0..<rows where (x + y) % 2 == 0 {
                let t = SKSpriteNode(color: checker, size: CGSize(width: cell, height: cell))
                t.position = CGPoint(x: -w / 2 + (CGFloat(x) + 0.5) * cell, y: -h / 2 + (CGFloat(y) + 0.5) * cell)
                node.addChild(t)
            } }
        }
        for c in map.obstacles {
            let o = SKSpriteNode(color: map.obstacleColor, size: CGSize(width: cell, height: cell))
            o.position = CGPoint(x: -w / 2 + (CGFloat(c.x) + 0.5) * cell, y: -h / 2 + (CGFloat(c.y) + 0.5) * cell)
            o.zPosition = 1
            node.addChild(o)
        }
        return node
    }
}
