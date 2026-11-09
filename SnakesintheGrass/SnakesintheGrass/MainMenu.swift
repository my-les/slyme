//
//  MainMenu.swift
//  SnakesintheGrass
//
//  Created by myle$ on 11/18/24.
//

import Foundation
import SpriteKit
import UIKit

class MainMenu: SKScene {
    /// Bumped on every layout request so stale async rebuilds are ignored.
    private var layoutGeneration = 0

    override func didMove(to view: SKView) {
        backgroundColor = .black
        // Rebuild every time we land on a view. Always clear first — stacking
        // without removeAllChildren caused the ghosted double menu on rotate/Duo.
        requestLayout()
        NotificationCenter.default.addObserver(self, selector: #selector(safeAreaMaybeChanged),
                                               name: UIScene.didActivateNotification, object: nil)
        GameCenterManager.shared.authenticatePlayer()
    }

    override func willMove(from view: SKView) {
        NotificationCenter.default.removeObserver(self)
        super.willMove(from: view)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Rotation / fold: size flips first; safe-area insets often catch up a
        // beat later. Rebuild now and again on the next run-loop.
        if view != nil { requestLayout() }
    }

    @objc private func safeAreaMaybeChanged() { requestLayout() }

    /// Clear + rebuild once for this generation; schedule a follow-up in case
    /// safeAreaInsets / bounds settle after didChangeSize.
    private func requestLayout() {
        layoutGeneration &+= 1
        let gen = layoutGeneration
        if let v = view { syncSize(from: v) }
        layoutMenu()
        // Deferred rebuild for safe area inset settling
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, self.layoutGeneration == gen, let v = self.view else { return }
            self.syncSize(from: v)
            self.layoutMenu()
        }
    }

    /// Keep scene.size matched to the SKView. SpriteView + rotation can leave
    /// them out of sync and park the menu in a corner of a larger canvas.
    private func syncSize(from view: SKView) {
        let b = view.bounds.size
        guard b.width > 1, b.height > 1 else { return }
        if abs(b.width - size.width) > 0.5 || abs(b.height - size.height) > 0.5 {
            size = b
        }
    }

    /// Full safe-area rect. Menu is not clipped to a Duo hinge half.
    private func contentRect() -> CGRect {
        let ins = view?.safeAreaInsets ?? .zero
        return CGRect(x: ins.left, y: ins.bottom,
                      width: max(0, size.width - ins.left - ins.right),
                      height: max(0, size.height - ins.top - ins.bottom))
    }

    private func layoutMenu() {
        removeAllChildren()
        backgroundColor = .black
        let r = contentRect()
        guard r.width > 0, r.height > 0 else { return }
        let cx = r.midX, cy = r.midY

        // Same-device "2 players" intentionally omitted; online covers multiplayer.
        let items: [(String, String)] = [
            ("play", "playButton"),
            ("online", "onlineButton"),
            ("instructions", "aboutButton"),
            ("high scores", "highScoresButton"),
            ("customize", "customizeButton"),
        ]
        // Fit title + subtitle + N items into the safe height (landscape is short).
        let titleBlock: CGFloat = 70
        let needed: CGFloat = titleBlock + CGFloat(items.count - 1) * 55 + 20
        let step: CGFloat = needed > r.height - 20
            ? max(36, (r.height - titleBlock - 20) / CGFloat(max(1, items.count - 1)))
            : 55
        let stackH = titleBlock + CGFloat(items.count - 1) * step
        let top = cy + stackH / 2

        let title = SKLabelNode(text: "slyme")
        title.fontName = "CourierNewPS-BoldMT"
        title.fontSize = 30
        title.fontColor = .systemIndigo
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: cx, y: top)
        addChild(title)

        let subtitle = SKLabelNode(text: "eat or be ate.")
        subtitle.fontName = "CourierNewPS-BoldMT"
        subtitle.fontSize = 14
        subtitle.fontColor = .red
        subtitle.verticalAlignmentMode = .center
        subtitle.position = CGPoint(x: cx, y: top - 30)
        addChild(subtitle)

        let firstItemY = top - titleBlock
        for (i, item) in items.enumerated() {
            addChild(createButton(withText: item.0, name: item.1,
                                  position: CGPoint(x: cx, y: firstItemY - CGFloat(i) * step)))
        }
    }

    private func createButton(withText text: String, name: String, position: CGPoint) -> SKLabelNode {
        let button = SKLabelNode(text: text)
        button.fontName = "CourierNewPS-BoldMT"
        button.fontSize = 20
        button.fontColor = .darkGray
        button.verticalAlignmentMode = .center
        button.position = position
        button.name = name
        return button
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let nodes = nodes(at: location)

        for node in nodes {
            if node.name == "playButton" {
                let gameScene = GameScene(size: self.size)
                gameScene.scaleMode = .resizeFill
                view?.presentScene(gameScene, transition: .flipHorizontal(withDuration: 0.5))
            } else if node.name == "aboutButton" {
                showAlert(withTitle: "how to play", message:
                """

                1. swipe to control the direction

                2. crush the apple

                3. don't snake yourself twin

                4. try to get the highest score

                """
                )
            } else if node.name == "onlineButton" {
                let lobby = OnlineLobbyScene(size: self.size)
                lobby.scaleMode = .resizeFill
                view?.presentScene(lobby, transition: .fade(withDuration: 0.4))
            } else if node.name == "customizeButton" {
                let customize = CustomizeScene(size: self.size)
                customize.scaleMode = .resizeFill
                view?.presentScene(customize, transition: .fade(withDuration: 0.4))
            } else if node.name == "highScoresButton" {
                GameCenterManager.shared.showLeaderboard()
            }
        }
    }

    private func showAlert(withTitle title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        if let viewController = view?.window?.rootViewController {
            viewController.present(alert, animated: true, completion: nil)
        }
    }
}
