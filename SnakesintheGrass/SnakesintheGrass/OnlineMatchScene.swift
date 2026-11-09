//
//  OnlineMatchScene.swift
//  slyme
//
//  Renders an OnlineSession and routes swipes into it. No rules here: the host's
//  session runs VersusMatch; both sides draw the latest OnlineState snapshot.
//  Never submits to the single-player leaderboard. See docs/ONLINE_PLAY.md.
//

import SpriteKit
import UIKit

final class OnlineMatchScene: SKScene {
    private let font = "CourierNewPS-BoldMT"
    let session: OnlineSession
    private let opponentName: String

    // Layout
    private let columns = MapCatalog.columns, rows = MapCatalog.rows
    private var cellSize: CGFloat = 20
    private var boardRect: CGRect = .zero
    private var hud: [CGRect] = [.zero, .zero]   // [mine, theirs]
    private var hingeInteraction: AnyObject?
    private var mapShown: String?

    // Nodes
    private let myLabel = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
    private let theirLabel = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
    private let infoLabel = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
    private let pingLabel = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
    private var appleNode: SKSpriteNode?
    private var overlay: SKNode?
    private var swipeStart: CGPoint?
    private var clock: TimeInterval = 0
    /// Guest sees a 180° board so their snake starts at the bottom.
    private var flipsBoard: Bool { session.role == .guest }

    private let impact = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()
    private var lastApples = 0
    private var matchRecorded = false  // Ensures match is counted exactly once

    #if DEBUG
    /// Loopback demo: the opponent (and optionally you) driven by a bot.
    private var demoPeer: OnlineSession?
    private var demoLink: LoopbackLink?
    private var demoAutopilot = false
    #endif

    init(size: CGSize, session: OnlineSession, opponentName: String) {
        self.session = session
        self.opponentName = opponentName.lowercased()
        super.init(size: size)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    #if DEBUG
    /// Screenshot/demo: host vs an in-process bot over a LoopbackLink.
    /// Pass `asGuest: true` (or launch with -slymeOnlineAsGuest) to render the
    /// guest's flipped view of the same match.
    static func loopbackDemo(size: CGSize, autopilot: Bool, asGuest: Bool = false) -> OnlineMatchScene {
        let link = LoopbackLink(); link.autoDeliver = true
        let host = OnlineSession(transport: link.a, localID: "A", skin: EntitlementStore.shared.selectedSkin.id,
                                 map: EntitlementStore.shared.selectedMap.id,
                                 ownedMaps: MapCatalog.all.map(\.id), nonce: 2)
        let guest = OnlineSession(transport: link.b, localID: "B", skin: "ember", map: MapCatalog.defaultID,
                                  ownedMaps: MapCatalog.all.filter { $0.tier == .free }.map(\.id), nonce: 1)
        let view = asGuest ? guest : host
        let peer = asGuest ? host : guest
        let s = OnlineMatchScene(size: size, session: view, opponentName: asGuest ? "host" : "bot")
        s.demoPeer = peer; s.demoLink = link; s.demoAutopilot = autopilot
        return s
    }
    #endif

    override func didMove(to view: SKView) {
        backgroundColor = .black
        impact.prepare(); notify.prepare()
        for l in [myLabel, theirLabel, infoLabel, pingLabel] {
            l.verticalAlignmentMode = .center; l.zPosition = 20; addChild(l)
        }
        myLabel.fontSize = 18; theirLabel.fontSize = 18
        infoLabel.fontSize = 11; infoLabel.fontColor = UIColor(white: 1, alpha: 0.35)
        pingLabel.fontSize = 11
        session.onStart = { [weak self] in self?.roundStarted() }
        session.onUpdate = { [weak self] in self?.render() }
        session.onEnd = { [weak self] e in self?.ended(e) }
        session.onStatus = { [weak self] in self?.statusChanged() }
        relayout()
        installHingeObserver(on: view)
        NotificationCenter.default.addObserver(self, selector: #selector(resignActive),
                                               name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
                                               name: UIScene.didActivateNotification, object: nil)
        session.begin(now: clock)
        #if DEBUG
        demoPeer?.begin(now: clock)
        #endif
        showConnecting()
    }

    override func willMove(from view: SKView) {
        NotificationCenter.default.removeObserver(self)
        if #available(iOS 27.1, *), let h = hingeInteraction as? UIHingeInteraction { view.removeInteraction(h) }
        hingeInteraction = nil
        super.willMove(from: view)
    }

    @objc private func resignActive() { session.setLocalAway(true, now: clock) }
    @objc private func becameActive() { session.setLocalAway(false, now: clock); relayout() }

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
            view.addInteraction(i); hingeInteraction = i
        }
    }

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

    // MARK: Layout

    /// Flat: opponent strip on top, yours at the bottom, board between; swipe anywhere.
    /// Partially folded: board on one side of the fold, scores on the other.
    private func relayout() {
        guard size.width > 0, size.height > 0 else { return }
        let ins = view?.safeAreaInsets ?? .zero
        let safe = CGRect(x: ins.left, y: ins.bottom, width: max(0, size.width - ins.left - ins.right),
                          height: max(0, size.height - ins.top - ins.bottom))
        var play: CGRect
        if let d = activeDivisionRect(), d.intersects(safe) {
            if d.height >= d.width {
                let left = CGRect(x: safe.minX, y: safe.minY, width: d.minX - safe.minX, height: safe.height)
                let right = CGRect(x: d.maxX, y: safe.minY, width: safe.maxX - d.maxX, height: safe.height)
                play = left.width >= right.width ? left : right
                let side = left.width >= right.width ? right : left
                hud = [CGRect(x: side.minX, y: side.minY, width: side.width, height: side.height / 2),
                       CGRect(x: side.minX, y: side.midY, width: side.width, height: side.height / 2)]
            } else {
                play = CGRect(x: safe.minX, y: d.maxY, width: safe.width, height: safe.maxY - d.maxY)
                let side = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: d.minY - safe.minY)
                hud = [CGRect(x: side.minX, y: side.minY, width: side.width / 2, height: side.height),
                       CGRect(x: side.midX, y: side.minY, width: side.width / 2, height: side.height)]
            }
        } else {
            let band: CGFloat = 56
            hud = [CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: band),
                   CGRect(x: safe.minX, y: safe.maxY - band, width: safe.width, height: band)]
            play = CGRect(x: safe.minX, y: safe.minY + band, width: safe.width, height: safe.height - 2 * band)
        }
        play = play.insetBy(dx: 8, dy: 8)
        cellSize = max(4, floor(min(play.width / CGFloat(columns), play.height / CGFloat(rows))))
        let w = cellSize * CGFloat(columns), h = cellSize * CGFloat(rows)
        boardRect = CGRect(x: (play.midX - w / 2).rounded(), y: (play.midY - h / 2).rounded(), width: w, height: h)
        myLabel.position = CGPoint(x: hud[0].midX, y: hud[0].midY)
        theirLabel.position = CGPoint(x: hud[1].midX, y: hud[1].midY)
        infoLabel.position = CGPoint(x: hud[0].minX + 40, y: hud[0].midY)
        pingLabel.position = CGPoint(x: hud[0].maxX - 40, y: hud[0].midY)
        mapShown = nil
        render()
        rebuildOverlay()
    }

    private func drawMap() {
        guard mapShown != session.mapID else { return }
        mapShown = session.mapID
        childNode(withName: "mapLayer")?.removeFromParent()
        let map = MapCatalog.map(id: session.mapID) ?? MapCatalog.all[0]
        let layer = MapRenderer.board(for: map, cell: cellSize, previewFloor: false)
        layer.name = "mapLayer"; layer.position = CGPoint(x: boardRect.midX, y: boardRect.midY); layer.zPosition = -1
        // Rotate the floor/obstacles 180° so asymmetric maps stay aligned with flipped snakes.
        if flipsBoard { layer.zRotation = .pi }
        addChild(layer)
    }

    private func viewCell(_ c: GridCell) -> GridCell {
        flipsBoard ? OnlineViewFlip.cell(c) : c
    }

    private func point(_ c: GridCell) -> CGPoint {
        let v = viewCell(c)
        return CGPoint(x: boardRect.minX + (CGFloat(v.x) + 0.5) * cellSize,
                       y: boardRect.minY + (CGFloat(v.y) + 0.5) * cellSize)
    }

    private func skin(_ p: PlayerID) -> Skin {
        let id = p == session.me ? session.mySkin : session.theirSkin
        return SkinCatalog.skin(id: id) ?? SkinCatalog.all[0]
    }

    // MARK: Render

    private func render() {
        guard boardRect.width > 0 else { return }
        drawMap()
        children.filter { $0.name == "seg" }.forEach { $0.removeFromParent() }
        guard let st = session.state, st.snakes.count == 2 else { return }
        for p in [PlayerID.one, .two] {
            let s = st.snakes[p.rawValue]
            // Texture picking uses the cells as drawn, so a flipped view gets
            // head_up when the snake is moving toward the top of the guest's screen.
            let drawn = s.body.map(viewCell)
            let cells = drawn.map { ($0.x, $0.y) }
            let vd = flipsBoard ? OnlineViewFlip.direction(s.direction) : s.direction
            let mv = CGVector(dx: vd.dx, dy: vd.dy)
            for (i, c) in cells.enumerated() {
                let prev = i > 0 ? cells[i - 1] : nil
                let next = i < cells.count - 1 ? cells[i + 1] : nil
                let part: GameScene.SnakePartType = i == 0 ? .head : (i == cells.count - 1 ? .tail : .body)
                let tex = part.getTextureName(previousPosition: prev, currentPosition: c, nextPosition: next, moveDirection: mv)
                let n = skin(p).makeSegment(textureName: tex, isHead: i == 0, size: CGSize(width: cellSize, height: cellSize))
                n.position = point(s.body[i]); n.name = "seg"; n.zPosition = i == 0 ? 2 : 1
                addChild(n)
            }
        }
        let goal = TwoPlayerConfig.applesToWin
        let mine = st.snakes[session.me.rawValue].apples, theirs = st.snakes[session.them.rawValue].apples
        myLabel.text = "you  \(mine)/\(goal)"
        myLabel.fontColor = skin(session.me).previewColor.withAlphaComponent(1)
        theirLabel.text = "\(opponentName)  \(theirs)/\(goal)"
        theirLabel.fontColor = skin(session.them).previewColor.withAlphaComponent(1)
        infoLabel.text = "spd \(TwoPlayerConfig.speedLevel(totalApples: st.totalApples))"
        if st.totalApples > lastApples { impact.impactOccurred() }
        lastApples = st.totalApples
        if let a = st.apple {
            if appleNode == nil {
                let n = SKSpriteNode(texture: SKTexture(imageNamed: "apple")); n.zPosition = 1
                addChild(n); appleNode = n
            }
            appleNode?.size = CGSize(width: cellSize, height: cellSize)
            appleNode?.position = point(a)
        } else { appleNode?.removeFromParent(); appleNode = nil }
        updatePing()
    }

    private func updatePing() {
        guard let rtt = session.rtt else { pingLabel.text = ""; return }
        let ms = Int(rtt * 1000)
        pingLabel.text = "\(ms)ms"
        pingLabel.fontColor = ms < 80 ? .systemGreen : (ms < 160 ? .systemYellow : .systemRed)
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        clock = currentTime
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-slymeFreeze") && session.state?.tick ?? 0 >= 28 { return }
        if let peer = demoPeer {
            // The host session must keep ticking regardless of which side we render.
            let hostSide = session.role == .host ? session : peer
            let guestSide = session.role == .guest ? session : peer
            hostSide.advance(now: currentTime)
            guestSide.advance(now: currentTime)
            if let st = hostSide.state {
                if let d = OnlineMatchScene.botMove(st, me: .two), d != st.snakes[1].direction {
                    guestSide.localTurn(d)
                }
                if demoAutopilot, let d = OnlineMatchScene.botMove(st, me: .one), d != st.snakes[0].direction {
                    hostSide.localTurn(d)
                }
            }
            return
        }
        #endif
        session.advance(now: currentTime)
    }

    private func roundStarted() {
        lastApples = 0
        mapShown = nil
        overlay?.removeFromParent(); overlay = nil
        render()
        rebuildOverlay()
    }

    private func ended(_ e: OnlineEnd) {
        var won = false
        switch e {
        case .match(.winner(let p, _)): won = p == session.me
        case .opponentLeft, .opponentForfeited: won = true
        default: break
        }
        notify.notificationOccurred(won ? .success : .error)
        recordMatchOutcome(e)
        rebuildOverlay()
    }
    
    /// Record match outcome for stats tracking and leaderboard submission
    private func recordMatchOutcome(_ end: OnlineEnd) {
        // Only record once per scene instance
        guard !matchRecorded else { return }
        matchRecorded = true
        
        let outcome: MatchOutcome
        switch end {
        case .match(.winner(let p, _)):
            outcome = p == session.me ? .win : .loss
        case .opponentLeft, .opponentForfeited:
            outcome = .win
        case .youForfeited:
            outcome = .loss
        case .match(.draw):
            outcome = .draw
        case .versionMismatch:
            return  // Don't count version mismatch
        }
        
        let stats = OnlineStats.shared
        stats.recordMatch(outcome: outcome)
        
        // Submit wins to Game Center leaderboard
        if outcome == .win {
            Task {
                await GameCenterManager.shared.submitOnlineWins(stats.wins)
            }
        }
    }

    private func statusChanged() { updatePing(); rebuildOverlay() }

    // MARK: Overlays

    private func rebuildOverlay() {
        overlay?.removeFromParent(); overlay = nil
        switch session.phase {
        case .handshake: showConnecting()
        case .countdown:
            let o = makeOverlay(dim: false)
            label("go.", 28, .white, CGPoint(x: boardRect.midX, y: boardRect.midY + 40), in: o)
            label("you are \(skin(session.me).name). swipe anywhere.", 12, UIColor(white: 1, alpha: 0.6),
                  CGPoint(x: boardRect.midX, y: boardRect.midY + 10), in: o)
        case .playing:
            if session.opponentAway {
                let o = makeOverlay(dim: true)
                label("\(opponentName) left the app.", 16, .white, CGPoint(x: boardRect.midX, y: boardRect.midY + 20), in: o)
                label("they forfeit in \(Int(OnlineConfig.awayGrace))s", 12, .gray, CGPoint(x: boardRect.midX, y: boardRect.midY - 10), in: o)
            }
        case .ended: showResult()
        }
    }

    private func showConnecting() {
        guard session.phase == .handshake, boardRect.width > 0 else { return }
        overlay?.removeFromParent()
        let o = makeOverlay(dim: true)
        label("connecting…", 20, .white, CGPoint(x: boardRect.midX, y: boardRect.midY + 20), in: o)
        label("vs \(opponentName)", 12, .gray, CGPoint(x: boardRect.midX, y: boardRect.midY - 10), in: o)
        label("leave", 18, .darkGray, CGPoint(x: boardRect.midX, y: boardRect.midY - 70), name: "menu", in: o)
    }

    private func showResult() {
        guard let e = session.end else { return }
        let o = makeOverlay(dim: true)
        let c = CGPoint(x: boardRect.midX, y: boardRect.midY)
        var title = "draw.", sub = "", color = UIColor.white
        let st = session.state
        let mine = st?.snakes[session.me.rawValue].apples ?? 0, theirs = st?.snakes[session.them.rawValue].apples ?? 0
        let score = "\(mine) – \(theirs)"
        switch e {
        case .match(.draw): sub = "\(score)  both crashed"
        case .match(.winner(let p, let reason)):
            let won = p == session.me
            title = won ? "you win." : "you lose."
            color = won ? skin(session.me).previewColor.withAlphaComponent(1) : .systemRed
            sub = reason == .apples ? "\(score)  first to \(TwoPlayerConfig.applesToWin)"
                                    : "\(score)  \(won ? opponentName : "you") crashed"
        case .opponentLeft: title = "you win."; sub = "\(opponentName) left the match"
        case .opponentForfeited: title = "you win."; sub = "\(opponentName) was away too long"
        case .youForfeited: title = "forfeit."; color = .systemRed; sub = "you were away too long"
        case .versionMismatch: title = "can't play."; sub = "update slyme on both devices"
        }
        label(title, 40, color, CGPoint(x: c.x, y: c.y + 60), in: o)
        label(sub, 14, UIColor(white: 1, alpha: 0.6), CGPoint(x: c.x, y: c.y + 20), in: o)
        if session.opponentGone {
            label("opponent disconnected", 12, .darkGray, CGPoint(x: c.x, y: c.y - 40), in: o)
        } else if session.rematchLocal {
            label("waiting for \(opponentName)…", 16, .gray, CGPoint(x: c.x, y: c.y - 40), in: o)
        } else {
            label(session.rematchRemote ? "rematch? they're in" : "rematch", 22, .lightGray,
                  CGPoint(x: c.x, y: c.y - 40), name: "rematch", in: o)
        }
        label("menu", 20, .darkGray, CGPoint(x: c.x, y: c.y - 90), name: "menu", in: o)
    }

    private func makeOverlay(dim: Bool) -> SKNode {
        let o = SKNode(); o.zPosition = 100
        if dim {
            let d = SKSpriteNode(color: UIColor(white: 0, alpha: 0.72), size: boardRect.size)
            d.position = CGPoint(x: boardRect.midX, y: boardRect.midY); o.addChild(d)
        }
        addChild(o); overlay = o
        return o
    }

    private func label(_ t: String, _ size: CGFloat, _ color: UIColor, _ p: CGPoint, name: String? = nil, in parent: SKNode) {
        let l = SKLabelNode(fontNamed: font)
        l.text = t; l.fontSize = size; l.fontColor = color; l.position = p; l.name = name
        l.verticalAlignmentMode = .center
        parent.addChild(l)
    }

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: self)
        let names = nodes(at: loc).compactMap(\.name)
        if names.contains("menu") { leave(); return }
        if names.contains("rematch") { session.requestRematch(); return }
        swipeStart = loc
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let s = swipeStart else { return }
        let loc = t.location(in: self)
        let dx = loc.x - s.x, dy = loc.y - s.y
        guard max(abs(dx), abs(dy)) >= TwoPlayerConfig.swipeThreshold else { return }
        let screen: Direction = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
        // Guest view is flipped: swipe up on screen → board .down, so the snake
        // moves toward the top of THEIR screen. Host sends screen dirs as-is.
        session.localTurn(flipsBoard ? OnlineViewFlip.boardDirection(fromScreen: screen) : screen)
        swipeStart = loc
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { swipeStart = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { swipeStart = nil }

    private func leave() {
        session.quit()
        guard let view = view else { return }
        let m = MainMenu(size: view.bounds.size); m.scaleMode = .resizeFill
        view.presentScene(m, transition: .fade(withDuration: 0.5))
    }

    #if DEBUG
    /// Greedy bot for the demo: head for the apple, avoid instant death if possible.
    static func botMove(_ st: OnlineState, me: PlayerID) -> Direction? {
        guard st.snakes.count == 2, let apple = st.apple else { return nil }
        let s = st.snakes[me.rawValue]
        let cols = MapCatalog.columns, rows = MapCatalog.rows
        let blocked = Set(st.snakes.flatMap { $0.body.dropLast() })
        func next(_ d: Direction) -> GridCell {
            GridCell((s.head.x + d.dx + cols) % cols, (s.head.y + d.dy + rows) % rows)
        }
        let options = Direction.allCases.filter { $0 != s.direction.opposite && !blocked.contains(next($0)) }
        return options.min { a, b in
            let na = next(a), nb = next(b)
            return abs(na.x - apple.x) + abs(na.y - apple.y) < abs(nb.x - apple.x) + abs(nb.y - apple.y)
        }
    }
    #endif
}
