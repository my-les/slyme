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
    private let store = EntitlementStore.shared
    private let font = "CourierNewPS-BoldMT"
    private let toast = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
    private let selection = UISelectionFeedbackGenerator()

    init(size: CGSize, page: Page = .skins) {
        self.page = page
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        selection.prepare()
        build()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if view != nil { build() }
    }

    private var safeRect: CGRect {
        let i = view?.safeAreaInsets ?? .zero
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
        toast.position = CGPoint(x: r.midX, y: r.minY + 52)
        toast.alpha = 0
        toast.text = ""
        addChild(toast)

        // Grid area between tabs and toast.
        let grid = CGRect(x: r.minX, y: r.minY + 76, width: r.width, height: (tabsY - 28) - (r.minY + 76))
        let count = page == .skins ? SkinCatalog.all.count : MapCatalog.all.count
        let columns = grid.width >= 600 ? 4 : (grid.width >= 420 ? 3 : 2)
        let rowsN = Int(ceil(Double(count) / Double(columns)))
        let gap: CGFloat = 16
        let cellW = (grid.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellH = min((grid.height - gap * CGFloat(rowsN - 1)) / CGFloat(rowsN), cellW * 1.25)
        let totalH = cellH * CGFloat(rowsN) + gap * CGFloat(rowsN - 1)
        let top = grid.midY + totalH / 2

        for i in 0..<count {
            let col = i % columns, row = i / columns
            let frame = CGRect(x: grid.minX + CGFloat(col) * (cellW + gap),
                               y: top - CGFloat(row + 1) * cellH - CGFloat(row) * gap,
                               width: cellW, height: cellH)
            addChild(page == .skins ? skinCard(SkinCatalog.all[i], in: frame)
                                    : mapCard(MapCatalog.all[i], in: frame))
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
        if locked, let img = UIImage(systemName: "lock.fill")?
            .withTintColor(Palette.paper, renderingMode: .alwaysOriginal) {
            let lock = SKSpriteNode(texture: SKTexture(image: img))
            let s: CGFloat = 18
            lock.size = CGSize(width: s * img.size.width / max(1, img.size.height), height: s)
            lock.position = CGPoint(x: 0, y: 14)
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

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let names = nodes(at: touch.location(in: self)).compactMap { $0.name }
        guard let name = names.first else { return }

        if name == "back" {
            let menu = MainMenu(size: size)
            menu.scaleMode = .resizeFill
            view?.presentScene(menu, transition: .fade(withDuration: 0.4))
        } else if name == "tab.skins" || name == "tab.maps" {
            page = name == "tab.skins" ? .skins : .maps
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
                showToast("unlock coming soon.")
            }
        } else if name.hasPrefix("map."), let map = MapCatalog.map(id: String(name.dropFirst(4))) {
            if store.isUnlocked(mapID: map.id) {
                store.selectedMap = map
                selection.selectionChanged()
                build()
            } else {
                showToast("unlock coming soon.")
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
