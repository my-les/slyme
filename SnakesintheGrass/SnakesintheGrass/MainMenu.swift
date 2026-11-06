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

    override func didMove(to view: SKView) {
        backgroundColor = .black
        // Rebuild every time we land on a view: SpriteView / Duo can call
        // didMove more than once as the size settles, and adding without
        // clearing produced the ghosted double menu on device.
        syncSize(from: view)
        layoutMenu()
        // Size often settles one run-loop later on Duo / multi-display.
        DispatchQueue.main.async { [weak self] in
            guard let self, let v = self.view else { return }
            self.syncSize(from: v)
            self.layoutMenu()
        }
        GameCenterManager.shared.authenticatePlayer()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Size often starts small (or .zero from ContentView) then jumps to the
        // real bounds on Duo / iPad. Relayout so the menu stays centered.
        if view != nil { layoutMenu() }
    }

    /// Keep scene.size matched to the SKView. SpriteView + Duo can leave them
    /// out of sync, which parked the menu in a corner of a larger canvas.
    private func syncSize(from view: SKView) {
        let b = view.bounds.size
        guard b.width > 1, b.height > 1 else { return }
        if abs(b.width - size.width) > 0.5 || abs(b.height - size.height) > 0.5 {
            size = b
        }
    }

    /// Safe play rect. Menu stays centered on the full screen: we do NOT
    /// shrink to a Duo hinge half here (that parked the menu in a corner when
    /// a division region was reported active while flat). Game scenes still
    /// use reservedRegions for board / HUD splits.
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

        let title = SKLabelNode(text: "slyme")
        title.fontName = "CourierNewPS-BoldMT"
        title.fontSize = 30
        title.fontColor = .systemIndigo
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: cx, y: cy + 100)
        addChild(title)

        let subtitle = SKLabelNode(text: "eat or be ate.")
        subtitle.fontName = "CourierNewPS-BoldMT"
        subtitle.fontSize = 14
        subtitle.fontColor = .red
        subtitle.verticalAlignmentMode = .center
        subtitle.position = CGPoint(x: cx, y: cy + 70)
        addChild(subtitle)

        // Same-device "2 players" intentionally omitted; online covers multiplayer.
        let items: [(String, String)] = [
            ("play", "playButton"),
            ("online", "onlineButton"),
            ("instructions", "aboutButton"),
            ("high scores", "highScoresButton"),
            ("customize", "customizeButton"),
        ]
        for (i, item) in items.enumerated() {
            addChild(createButton(withText: item.0, name: item.1,
                                  position: CGPoint(x: cx, y: cy - CGFloat(i) * 55)))
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
