//
//  TwoPlayerSetupScene.swift
//  slyme
//
//  Pre-match screen: each player picks an unlocked skin, map cycles through
//  unlocked maps, optional "face each other" toggle, then start.
//

import SpriteKit
import UIKit

final class TwoPlayerSetupScene: SKScene {
    private enum Key {
        static let p1 = "twoPlayer.p1Skin", p2 = "twoPlayer.p2Skin", facing = "twoPlayer.facing"
    }
    private let font = "CourierNewPS-BoldMT"
    private let store = EntitlementStore.shared
    private var picks: [String] = []
    private var mapID: String = MapCatalog.defaultID
    private var facing = TwoPlayerConfig.defaultFacing
    private let tick = UISelectionFeedbackGenerator()

    private var skins: [Skin] { SkinCatalog.visible(owned: { store.isUnlocked(skinID: $0.id) }) }
    private var unlockedSkins: [Skin] { skins.filter { store.isUnlocked(skinID: $0.id) } }
    private var unlockedMaps: [GameMap] { MapCatalog.all.filter { store.isUnlocked(mapID: $0.id) } }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        let d = UserDefaults.standard
        let free = unlockedSkins.map(\.id)
        var p1 = d.string(forKey: Key.p1).flatMap { free.contains($0) ? $0 : nil } ?? SkinCatalog.defaultID
        if !free.contains(p1) { p1 = free.first ?? SkinCatalog.defaultID }
        var p2 = d.string(forKey: Key.p2).flatMap { free.contains($0) ? $0 : nil } ?? (free.first { $0 != p1 } ?? p1)
        if p2 == p1, let other = free.first(where: { $0 != p1 }) , d.string(forKey: Key.p2) == nil { p2 = other }
        picks = [p1, p2]
        mapID = store.selectedMap.id
        if d.object(forKey: Key.facing) != nil { facing = d.bool(forKey: Key.facing) }
        build()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if view != nil, !picks.isEmpty { build() }
    }

    private func label(_ t: String, _ size: CGFloat, _ color: UIColor, _ p: CGPoint, name: String? = nil) {
        let l = SKLabelNode(fontNamed: font)
        l.text = t; l.fontSize = size; l.fontColor = color; l.position = p; l.name = name
        l.verticalAlignmentMode = .center
        addChild(l)
    }

    private func build() {
        removeAllChildren()
        let cx = size.width / 2, cy = size.height / 2
        label("2 players", 30, .systemIndigo, CGPoint(x: cx, y: cy + 230))
        label("one board. one apple. first to \(TwoPlayerConfig.applesToWin).", 12, .gray, CGPoint(x: cx, y: cy + 200))
        row(player: 1, y: cy + 130)
        row(player: 0, y: cy + 30)
        let mapName = MapCatalog.map(id: mapID)?.name ?? mapID
        label("map  \(mapName)  ›", 18, .lightGray, CGPoint(x: cx, y: cy - 50), name: "map")
        label("p2 faces p1  \(facing ? "on" : "off")", 16, .darkGray, CGPoint(x: cx, y: cy - 95), name: "facing")
        label("start", 24, .white, CGPoint(x: cx, y: cy - 160), name: "start")
        label("back", 18, .darkGray, CGPoint(x: cx, y: cy - 210), name: "back")
    }

    /// One row of skin swatches (og head art) for a player. Locked = dimmed, not tappable.
    private func row(player: Int, y: CGFloat) {
        let list = skins
        let selected = picks[player]
        label("p\(player + 1)  \(SkinCatalog.skin(id: selected)?.name ?? selected)", 14, .white,
              CGPoint(x: size.width / 2, y: y + 34))
        let sw: CGFloat = 34, gap: CGFloat = 10
        let perRow = max(1, Int((size.width - 32 + gap) / (sw + gap)))
        for (i, s) in list.enumerated() {
            let r = i / perRow, c = i % perRow
            let n = min(perRow, list.count - r * perRow)
            let x0 = size.width / 2 - (CGFloat(n) * sw + CGFloat(n - 1) * gap) / 2 + sw / 2
            let pos = CGPoint(x: x0 + CGFloat(c) * (sw + gap), y: y - CGFloat(r) * (sw + gap))
            let unlocked = store.isUnlocked(skinID: s.id)
            let node = SKSpriteNode(texture: SKTexture(imageNamed: s.textureName(for: "head_right")),
                                    size: CGSize(width: sw - 6, height: sw - 6))
            node.position = pos
            node.alpha = unlocked ? 1 : 0.22
            node.name = unlocked ? "pick:\(player):\(s.id)" : "locked"
            addChild(node)
            if s.id == selected {
                let ring = SKShapeNode(rectOf: CGSize(width: sw, height: sw), cornerRadius: 6)
                ring.strokeColor = .white; ring.lineWidth = 1.5; ring.position = pos
                addChild(ring)
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        for node in nodes(at: t.location(in: self)) {
            guard let name = node.name else { continue }
            let d = UserDefaults.standard
            if name.hasPrefix("pick:") {
                let parts = name.split(separator: ":")
                let p = Int(parts[1]) ?? 0
                picks[p] = String(parts[2])
                d.set(picks[p], forKey: p == 0 ? Key.p1 : Key.p2)
                tick.selectionChanged(); build(); return
            }
            switch name {
            case "map":
                let maps = unlockedMaps
                if let i = maps.firstIndex(where: { $0.id == mapID }), !maps.isEmpty {
                    mapID = maps[(i + 1) % maps.count].id
                } else { mapID = maps.first?.id ?? MapCatalog.defaultID }
                tick.selectionChanged(); build(); return
            case "facing":
                facing.toggle(); d.set(facing, forKey: Key.facing)
                tick.selectionChanged(); build(); return
            case "start": start(); return
            case "back":
                let m = MainMenu(size: size); m.scaleMode = .resizeFill
                view?.presentScene(m, transition: .fade(withDuration: 0.4)); return
            default: continue
            }
        }
    }

    private func start() {
        let s1 = SkinCatalog.skin(id: picks[0]) ?? SkinCatalog.all[0]
        let s2 = SkinCatalog.skin(id: picks[1]) ?? SkinCatalog.all[0]
        let map = MapCatalog.map(id: mapID) ?? MapCatalog.all[0]
        let scene = TwoPlayerScene(size: size, p1Skin: s1, p2Skin: s2, map: map, facing: facing)
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: .flipHorizontal(withDuration: 0.5))
    }
}
