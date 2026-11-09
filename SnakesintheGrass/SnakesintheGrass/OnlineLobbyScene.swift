//
//  OnlineLobbyScene.swift
//  slyme
//
//  "online" entry: checks Game Center sign-in, shows your skin and map, and
//  opens the standard matchmaker (quick match + invite friends).
//

import SpriteKit
import GameKit

final class OnlineLobbyScene: SKScene {
    static weak var active: OnlineLobbyScene?

    enum Status: Equatable {
        case signingIn, signedOut, ready, finding, failed(String)
        var text: String {
            switch self {
            case .signingIn: return "signing in to game center…"
            case .signedOut: return "not signed in to game center."
            case .ready: return "ready."
            case .finding: return "finding an opponent…"
            case .failed(let m): return "couldn't connect. \(m.lowercased())"
            }
        }
    }

    private let font = "CourierNewPS-BoldMT"
    private(set) var status: Status = .signingIn
    private var forcedStatus: Status?

    init(size: CGSize, forcedStatus: Status? = nil) {
        self.forcedStatus = forcedStatus
        super.init(size: size)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        OnlineLobbyScene.active = self
        if let f = forcedStatus { status = f; build(); return }
        status = GKLocalPlayer.local.isAuthenticated ? .ready : .signingIn
        build()
        if !GKLocalPlayer.local.isAuthenticated {
            GameCenterManager.shared.authenticatePlayer()
            // The auth handler only shows its sheet once per launch; if nothing
            // changes shortly, explain how to sign in.
            run(.sequence([.wait(forDuration: 2.5), .run { [weak self] in
                guard let self, self.status == .signingIn else { return }
                self.setStatus(GKLocalPlayer.local.isAuthenticated ? .ready : .signedOut)
            }]))
        }
    }

    override func willMove(from view: SKView) {
        if OnlineLobbyScene.active === self { OnlineLobbyScene.active = nil }
        super.willMove(from: view)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if view != nil { build() }
    }

    func setStatus(_ s: Status) {
        guard forcedStatus == nil else { return }
        status = s; build()
    }

    private func label(_ t: String, _ size: CGFloat, _ color: UIColor, _ p: CGPoint, name: String? = nil) {
        let l = SKLabelNode(fontNamed: font)
        l.text = t; l.fontSize = size; l.fontColor = color; l.position = p; l.name = name
        l.verticalAlignmentMode = .center
        l.preferredMaxLayoutWidth = size > 14 ? 0 : self.size.width - 48
        l.numberOfLines = 0
        addChild(l)
    }

    private func build() {
        guard size.width > 0 else { return }
        removeAllChildren()
        let cx = size.width / 2, cy = size.height / 2
        let store = EntitlementStore.shared
        label("online", 30, .systemIndigo, CGPoint(x: cx, y: cy + 230))
        label("you vs one player. same board. same apple. free.", 12, .gray, CGPoint(x: cx, y: cy + 200))

        // Stats
        let stats = OnlineStats.shared
        if stats.totalMatches > 0 {
            let record = "\(stats.wins)–\(stats.losses)" + (stats.draws > 0 ? "–\(stats.draws)" : "")
            let rate = String(format: "%.0f%%", stats.winRate)
            label("record  \(record)  ·  \(rate) win rate", 12, UIColor(white: 1, alpha: 0.5), CGPoint(x: cx, y: cy + 170))
        }

        let skin = store.selectedSkin
        let head = SKSpriteNode(texture: SKTexture(imageNamed: skin.textureName(for: "head_right")),
                                size: CGSize(width: 34, height: 34))
        head.position = CGPoint(x: cx, y: cy + 130); addChild(head)
        label("you  \(skin.name)", 14, .white, CGPoint(x: cx, y: cy + 95))
        label("map  \(store.selectedMap.name)  (void if they don't own it)", 11, .darkGray, CGPoint(x: cx, y: cy + 72))

        var statusColor = UIColor.lightGray
        if case .failed = status { statusColor = .systemRed }
        if status == .signedOut { statusColor = .systemRed }
        label(status.text, 14, statusColor, CGPoint(x: cx, y: cy + 10))
        if status == .signedOut {
            label("open settings › game center and sign in, then come back.", 11, .gray, CGPoint(x: cx, y: cy - 20))
        }
        if status == .finding {
            let dot = SKShapeNode(circleOfRadius: 4)
            dot.fillColor = .systemIndigo; dot.strokeColor = .clear
            dot.position = CGPoint(x: cx, y: cy - 25); addChild(dot)
            dot.run(.repeatForever(.sequence([.fadeAlpha(to: 0.15, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
        }
        let canPlay = status == .ready || { if case .failed = status { return true }; return false }()
        label("find match", 22, canPlay ? .white : UIColor(white: 1, alpha: 0.2), CGPoint(x: cx, y: cy - 80),
              name: canPlay ? "find" : nil)
        label("quick match or invite a friend", 11, .darkGray, CGPoint(x: cx, y: cy - 105))
        
        // Leaderboard button (only if authenticated)
        if GKLocalPlayer.local.isAuthenticated {
            label("leaderboard", 16, .lightGray, CGPoint(x: cx, y: cy - 145), name: "leaderboard")
        }
        
        if status == .signedOut {
            label("try again", 16, .lightGray, CGPoint(x: cx, y: cy - 175), name: "retry")
        }
        label("back", 18, .darkGray, CGPoint(x: cx, y: cy - 210), name: "back")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        for node in nodes(at: t.location(in: self)) {
            switch node.name {
            case "find": OnlineMatchmaker.shared.presentMatchmaker(); return
            case "leaderboard": GameCenterManager.shared.showOnlineLeaderboard(); return
            case "retry":
                setStatus(GKLocalPlayer.local.isAuthenticated ? .ready : .signedOut); return
            case "back":
                let m = MainMenu(size: size); m.scaleMode = .resizeFill
                view?.presentScene(m, transition: .fade(withDuration: 0.4)); return
            default: continue
            }
        }
    }
}
