//
//  TwoPlayerScene.swift
//  slyme
//
//  Local two-player versus on one device. Rules live in TwoPlayerRules.swift;
//  this scene only lays out, renders and routes touches. Never talks to
//  Game Center. See docs/TWO_PLAYER.md.
//

import SpriteKit
import UIKit

final class TwoPlayerScene: SKScene {
    static weak var active: TwoPlayerScene?

    private let font = "CourierNewPS-BoldMT"
    private let skins: [Skin]           // index = PlayerID.rawValue
    private let map: GameMap
    private let facing: Bool
    private var match: VersusMatch
    private var nextTick: TimeInterval = 0
    private var paused2P = false
    private var started = false

    // Layout
    private let columns = MapCatalog.columns, rows = MapCatalog.rows
    private var cellSize: CGFloat = 20
    private var boardRect: CGRect = .zero
    private var zones: [CGRect] = [.zero, .zero]   // touch zones per player
    private var hud: [CGRect] = [.zero, .zero]     // score area per player
    private var folded = false
    private var hingeInteraction: AnyObject?

    // Nodes
    private var scoreLabels: [SKLabelNode] = []
    private let speedLabel = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
    private var padNodes: [SKShapeNode] = []
    private var pauseButton: SKNode?
    private var appleNode: SKSpriteNode?
    private var overlay: SKNode?

    // Touches: start point + player, per finger (multi-touch).
    private var tracked: [ObjectIdentifier: (start: CGPoint, player: PlayerID)] = [:]

    private let impact = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()

    init(size: CGSize, p1Skin: Skin, p2Skin: Skin, map: GameMap, facing: Bool) {
        self.skins = [p1Skin, p2Skin]
        self.map = map
        self.facing = facing
        let board = VersusBoard(map: map)
        let (a, b) = VersusMatch.startSnakes(board: board)
        self.match = VersusMatch(board: board, p1: a, p2: b)
        super.init(size: size)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-slymeTwoDemo") { seedDemo() }
        #endif
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        view.isMultipleTouchEnabled = true
        impact.prepare(); notify.prepare()
        for p in [PlayerID.one, .two] {
            let l = SKLabelNode(fontNamed: font)
            l.fontSize = 18
            l.fontColor = skins[p.rawValue].previewColor.withAlphaComponent(1)
            l.verticalAlignmentMode = .center
            l.zPosition = 20
            addChild(l); scoreLabels.append(l)
            let pad = SKShapeNode()
            pad.fillColor = UIColor(white: 1, alpha: 0.04)
            pad.strokeColor = .clear
            pad.zPosition = -2
            addChild(pad); padNodes.append(pad)
        }
        speedLabel.fontSize = 11
        speedLabel.fontColor = UIColor(white: 1, alpha: 0.35)
        speedLabel.verticalAlignmentMode = .center
        speedLabel.zPosition = 20
        addChild(speedLabel)
        let pb = PauseControl.make(playing: false, at: .zero)
        addChild(pb); pauseButton = pb
        relayout()
        installHingeObserver(on: view)
        TwoPlayerScene.active = self
        NotificationCenter.default.addObserver(self, selector: #selector(resignActive),
                                               name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
                                               name: UIScene.didActivateNotification, object: nil)
    }

    override func willMove(from view: SKView) {
        NotificationCenter.default.removeObserver(self)
        if #available(iOS 27.1, *), let h = hingeInteraction as? UIHingeInteraction { view.removeInteraction(h) }
        hingeInteraction = nil
        if TwoPlayerScene.active === self { TwoPlayerScene.active = nil }
        super.willMove(from: view)
    }

    @objc private func resignActive() { if match.result == nil { setPaused(true) } }
    @objc private func becameActive() { if paused2P { isPaused = true }; relayout() }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if view != nil { relayout() }
    }

    private func installHingeObserver(on view: SKView) {
        guard hingeInteraction == nil else { return }
        if #available(iOS 27.1, *) {
            let i = UIHingeInteraction { [weak self] _, _ in
                self?.relayout()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(16))
                    self?.relayout()
                }
            }
            view.addInteraction(i)
            hingeInteraction = i
        }
    }

    // MARK: - Layout

    private func activeDivisionRect() -> CGRect? {
        guard let view = view else { return nil }
        if #available(iOS 27.1, *) {
            guard let r = view.reservedRegions(kind: .division).first(where: { $0.isActive }) else { return nil }
            let f = r.frame
            guard f.width > 0 || f.height > 0 else { return nil }
            return CGRect(x: f.minX, y: size.height - f.maxY, width: f.width, height: f.height)
        }
        return nil
    }

    /// Flat: P2 strip on top, P1 strip at the bottom, board between; each player
    /// swipes anywhere on their half of the screen.
    /// Partially folded: the board stays entirely on one side of the fold and the
    /// other side becomes two thumb pads (one per player) with the scores.
    private func relayout() {
        guard size.width > 0, size.height > 0 else { return }
        let ins = view?.safeAreaInsets ?? .zero
        let safe = CGRect(x: ins.left, y: ins.bottom,
                          width: max(0, size.width - ins.left - ins.right),
                          height: max(0, size.height - ins.top - ins.bottom))
        var play: CGRect
        if let d = activeDivisionRect(), d.intersects(safe) {
            folded = true
            if d.height >= d.width {
                // Book fold: board on the wider side, pads stacked on the other (P2 top, P1 bottom).
                let left = CGRect(x: safe.minX, y: safe.minY, width: d.minX - safe.minX, height: safe.height)
                let right = CGRect(x: d.maxX, y: safe.minY, width: safe.maxX - d.maxX, height: safe.height)
                play = left.width >= right.width ? left : right
                let pads = left.width >= right.width ? right : left
                let half = pads.height / 2
                zones = [CGRect(x: pads.minX, y: pads.minY, width: pads.width, height: half),
                         CGRect(x: pads.minX, y: pads.minY + half, width: pads.width, height: half)]
            } else {
                // Laptop fold: board on the upright top half, pads side by side below (P1 left, P2 right).
                play = CGRect(x: safe.minX, y: d.maxY, width: safe.width, height: safe.maxY - d.maxY)
                let pads = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: d.minY - safe.minY)
                let half = pads.width / 2
                zones = [CGRect(x: pads.minX, y: pads.minY, width: half, height: pads.height),
                         CGRect(x: pads.minX + half, y: pads.minY, width: half, height: pads.height)]
            }
            hud = zones
        } else {
            folded = false
            let band: CGFloat = 56
            hud = [CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: band),
                   CGRect(x: safe.minX, y: safe.maxY - band, width: safe.width, height: band)]
            play = CGRect(x: safe.minX, y: safe.minY + band, width: safe.width, height: safe.height - 2 * band)
            let mid = size.height / 2
            zones = [CGRect(x: 0, y: 0, width: size.width, height: mid),
                     CGRect(x: 0, y: mid, width: size.width, height: size.height - mid)]
        }
        play = play.insetBy(dx: 8, dy: 8)
        let cell = max(4, floor(min(play.width / CGFloat(columns), play.height / CGFloat(rows))))
        cellSize = cell
        let w = cell * CGFloat(columns), h = cell * CGFloat(rows)
        boardRect = CGRect(x: (play.midX - w / 2).rounded(), y: (play.midY - h / 2).rounded(), width: w, height: h)

        for (i, pad) in padNodes.enumerated() {
            pad.path = folded ? CGPath(roundedRect: zones[i].insetBy(dx: 8, dy: 8), cornerWidth: 22, cornerHeight: 22, transform: nil) : nil
        }
        for p in [PlayerID.one, .two] {
            let l = scoreLabels[p.rawValue]
            let r = hud[p.rawValue]
            l.position = CGPoint(x: r.midX, y: folded ? r.midY + 20 : r.midY)
            l.zRotation = (p == .two && facing && !folded) ? .pi : 0
        }
        if folded {
            // Pause sits on the line between the two pads.
            let a = zones[0], b = zones[1]
            pauseButton?.position = a.minX == b.minX ? CGPoint(x: a.midX, y: a.maxY) : CGPoint(x: a.maxX, y: a.midY)
            if let pp = pauseButton?.position { speedLabel.position = CGPoint(x: pp.x, y: pp.y - 30) }
        } else {
            pauseButton?.position = CGPoint(x: hud[0].maxX - 32, y: hud[0].midY)
            speedLabel.position = CGPoint(x: hud[0].minX + 36, y: hud[0].midY)
        }
        childNode(withName: "mapLayer")?.removeFromParent()
        let layer = MapRenderer.board(for: map, cell: cellSize, previewFloor: false)
        layer.name = "mapLayer"
        layer.position = CGPoint(x: boardRect.midX, y: boardRect.midY)
        layer.zPosition = -1
        addChild(layer)
        if let o = overlay { o.removeFromParent(); overlay = nil; if match.result != nil { showResult() } else if paused2P { showPause() } }
        render()
    }

    private func point(_ c: GridCell) -> CGPoint {
        CGPoint(x: boardRect.minX + (CGFloat(c.x) + 0.5) * cellSize,
                y: boardRect.minY + (CGFloat(c.y) + 0.5) * cellSize)
    }

    // MARK: - Render

    private func render() {
        children.filter { $0.name == "seg" }.forEach { $0.removeFromParent() }
        for p in [PlayerID.one, .two] {
            let s = match[p]
            let cells = s.body.map { ($0.x, $0.y) }
            let mv = CGVector(dx: s.direction.dx, dy: s.direction.dy)
            for (i, c) in cells.enumerated() {
                let prev = i > 0 ? cells[i - 1] : nil
                let next = i < cells.count - 1 ? cells[i + 1] : nil
                let part: GameScene.SnakePartType = i == 0 ? .head : (i == cells.count - 1 ? .tail : .body)
                let tex = part.getTextureName(previousPosition: prev, currentPosition: c, nextPosition: next, moveDirection: mv)
                let n = skins[p.rawValue].makeSegment(textureName: tex, isHead: i == 0, size: CGSize(width: cellSize, height: cellSize))
                n.position = point(s.body[i]); n.name = "seg"; n.zPosition = i == 0 ? 2 : 1
                addChild(n)
            }
            let goal = TwoPlayerConfig.applesToWin
            scoreLabels[p.rawValue].text = "p\(p.rawValue + 1)  \(s.apples)/\(goal)"
        }
        speedLabel.text = "spd \(match.speedLevel)"
        if let a = match.apple {
            if appleNode == nil {
                let n = SKSpriteNode(texture: SKTexture(imageNamed: "apple"))
                n.zPosition = 1; addChild(n); appleNode = n
            }
            appleNode?.size = CGSize(width: cellSize, height: cellSize)
            appleNode?.position = point(a)
        } else { appleNode?.removeFromParent(); appleNode = nil }
        for (i, pad) in padNodes.enumerated() {
            pad.childNode(withName: "hint")?.removeFromParent()
            guard folded else { continue }
            let h = SKLabelNode(fontNamed: font)
            h.name = "hint"; h.fontSize = 12; h.fontColor = UIColor(white: 1, alpha: 0.45)
            h.text = "swipe here"
            h.position = CGPoint(x: zones[i].midX, y: zones[i].midY - 12)
            pad.addChild(h)
        }
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-slymeFreeze") { return }
        #endif
        guard !paused2P, match.result == nil else { return }
        if !started { started = true; nextTick = currentTime + 0.6 }  // short beat before the first move
        guard currentTime >= nextTick else { return }
        nextTick = currentTime + match.tickInterval
        let ev = match.step()
        if !ev.deaths.isEmpty { notify.notificationOccurred(.error) }
        else if !ev.ate.isEmpty { impact.impactOccurred() }
        render()
        if match.result != nil {
            if ev.deaths.isEmpty { notify.notificationOccurred(.success) }
            showResult()
        }
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let loc = t.location(in: self)
            let names = nodes(at: loc).compactMap { $0.name }
            if names.contains("pauseButton") { setPaused(!paused2P); continue }
            if names.contains("resume") { setPaused(false); continue }
            if names.contains("menu") { goToMenu(); continue }
            if names.contains("rematch") { rematch(); continue }
            if let p = player(at: loc) { tracked[ObjectIdentifier(t)] = (loc, p) }
        }
    }

    /// A swipe belongs to whoever's zone it STARTED in.
    private func player(at p: CGPoint) -> PlayerID? {
        if zones[0].contains(p) { return .one }
        if zones[1].contains(p) { return .two }
        return nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !paused2P, match.result == nil else { return }
        for t in touches {
            let id = ObjectIdentifier(t)
            guard let tr = tracked[id] else { continue }
            let loc = t.location(in: self)
            let dx = loc.x - tr.start.x, dy = loc.y - tr.start.y
            guard max(abs(dx), abs(dy)) >= TwoPlayerConfig.swipeThreshold else { continue }
            let d: Direction = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
            match.turn(tr.player, d)
            tracked[id] = (loc, tr.player)   // keep dragging to turn again
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.forEach { tracked[ObjectIdentifier($0)] = nil }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.forEach { tracked[ObjectIdentifier($0)] = nil }
    }

    // MARK: - Pause / result

    private func setPaused(_ on: Bool) {
        guard match.result == nil, on != paused2P else { return }
        paused2P = on
        let pos = pauseButton?.position ?? .zero
        pauseButton?.removeFromParent()
        let pb = PauseControl.make(playing: on, at: pos)
        addChild(pb); pauseButton = pb
        overlay?.removeFromParent(); overlay = nil
        if on { showPause() } else { started = false }
    }

    private func makeOverlay() -> SKNode {
        let o = SKNode(); o.zPosition = 100
        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.72), size: CGSize(width: boardRect.width, height: boardRect.height))
        dim.position = CGPoint(x: boardRect.midX, y: boardRect.midY)
        o.addChild(dim)
        addChild(o); overlay = o
        return o
    }

    private func label(_ text: String, size: CGFloat, color: UIColor, at p: CGPoint, name: String? = nil, in parent: SKNode) {
        let l = SKLabelNode(fontNamed: font)
        l.text = text; l.fontSize = size; l.fontColor = color; l.position = p; l.name = name
        l.verticalAlignmentMode = .center
        parent.addChild(l)
    }

    private func showPause() {
        let o = makeOverlay()
        let c = CGPoint(x: boardRect.midX, y: boardRect.midY)
        label("pause", size: 36, color: .white, at: CGPoint(x: c.x, y: c.y + 40), in: o)
        label("resume", size: 20, color: .lightGray, at: CGPoint(x: c.x, y: c.y - 20), name: "resume", in: o)
        label("menu", size: 20, color: .darkGray, at: CGPoint(x: c.x, y: c.y - 70), name: "menu", in: o)
    }

    private func showResult() {
        guard let r = match.result else { return }
        let o = makeOverlay()
        let c = CGPoint(x: boardRect.midX, y: boardRect.midY)
        let a = match[.one].apples, b = match[.two].apples
        var title = "draw.", color = UIColor.white, sub = "\(a) – \(b)"
        if case let .winner(p, reason) = r {
            title = "p\(p.rawValue + 1) wins."
            color = skins[p.rawValue].previewColor.withAlphaComponent(1)
            let loser = p == .one ? 2 : 1
            sub = reason == .apples ? "\(a) – \(b)  first to \(TwoPlayerConfig.applesToWin)" : "\(a) – \(b)  p\(loser) crashed"
        }
        label(title, size: 40, color: color, at: CGPoint(x: c.x, y: c.y + 60), in: o)
        label(sub, size: 14, color: UIColor(white: 1, alpha: 0.6), at: CGPoint(x: c.x, y: c.y + 20), in: o)
        label("rematch", size: 22, color: .lightGray, at: CGPoint(x: c.x, y: c.y - 40), name: "rematch", in: o)
        label("menu", size: 20, color: .darkGray, at: CGPoint(x: c.x, y: c.y - 90), name: "menu", in: o)
        if facing && !folded {
            // Same verdict, upside down, for the player across the table.
            let t = SKLabelNode(fontNamed: font)
            t.text = title; t.fontSize = 28; t.fontColor = color; t.zRotation = .pi
            t.position = CGPoint(x: c.x, y: boardRect.maxY - 60)
            o.addChild(t)
        }
    }

    private func rematch() {
        let board = VersusBoard(map: map)
        let (a, b) = VersusMatch.startSnakes(board: board)
        match = VersusMatch(board: board, p1: a, p2: b)
        overlay?.removeFromParent(); overlay = nil
        paused2P = false; started = false
        if let pos = pauseButton?.position {
            pauseButton?.removeFromParent()
            let pb = PauseControl.make(playing: false, at: pos)
            addChild(pb); pauseButton = pb
        }
        tracked.removeAll()
        render()
    }

    private func goToMenu() {
        guard let view = view else { return }
        let m = MainMenu(size: view.bounds.size)
        m.scaleMode = .resizeFill
        view.presentScene(m, transition: .fade(withDuration: 0.5))
    }

    #if DEBUG
    /// Screenshots only: a mid-match position.
    private func seedDemo() {
        guard match.board.obstacles.isEmpty else { return }
        func path(_ start: GridCell, _ moves: [Direction]) -> [GridCell] {
            var out = [start]; var c = start
            for m in moves { c = GridCell(c.x + m.dx, c.y + m.dy); out.append(c) }
            return out
        }
        // Bodies listed head first, so moves walk from head back to tail.
        let b1 = path(GridCell(7, 12), [.down, .down, .down, .left, .left, .down, .down, .down])
        let b2 = path(GridCell(11, 20), [.up, .up, .up, .right, .right, .right, .up, .up, .up, .up])
        match.snakes[0] = VersusSnake(body: b1, direction: .up, apples: 4)
        match.snakes[1] = VersusSnake(body: b2, direction: .down, apples: 6)
        match.apple = GridCell(9, 16)
    }
    #endif
}
