//
//  MainMenu.swift
//  SnakesintheGrass
//
//  Created by myle$ on 11/18/24.
//

import Foundation
import SpriteKit

class MainMenu: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = .black

        // Create the title label
        let titleLabel = SKLabelNode(text: "slyme")
        titleLabel.fontName = "CourierNewPS-BoldMT"
        titleLabel.fontSize = 30
        titleLabel.fontColor = .systemIndigo
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 100)
        addChild(titleLabel)

        // Create the subtitle
        let subsubTItleLabel = SKLabelNode(text: "当你停止梦想时，你就开始走向衰亡")
        subsubTItleLabel.fontName = "CourierNewPS-BoldMT"
        subsubTItleLabel.fontSize = 12
        subsubTItleLabel.fontColor = .gray
        subsubTItleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        //addChild(subsubTItleLabel)

        let subtitleLabel = SKLabelNode(text: "eat or be ate.")
        subtitleLabel.fontName = "CourierNewPS-BoldMT"
        subtitleLabel.fontSize = 14
        subtitleLabel.fontColor = .red
        subtitleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        addChild(subtitleLabel)

        // Create the Play button
        let playButton = createButton(withText: "play", name: "playButton", position: CGPoint(x: size.width / 2, y: size.height / 2))
        addChild(playButton)

        let twoPlayerButton = createButton(withText: "2 players", name: "twoPlayerButton", position: CGPoint(x: size.width / 2, y: size.height / 2 - 60))
        addChild(twoPlayerButton)

        // Create the About button
        let aboutButton = createButton(withText: "instructions", name: "aboutButton", position: CGPoint(x: size.width / 2, y: size.height / 2 - 120))
        addChild(aboutButton)

        // Create the High Scores button
        let highScoresButton = createButton(withText: "high scores", name: "highScoresButton", position: CGPoint(x: size.width / 2, y: size.height / 2 - 180))
        addChild(highScoresButton)

        let customizeButton = createButton(withText: "customize", name: "customizeButton", position: CGPoint(x: size.width / 2, y: size.height / 2 - 240))
        addChild(customizeButton)

        // Initialize GameCenter
        GameCenterManager.shared.authenticatePlayer()
    }

    private func createButton(withText text: String, name: String, position: CGPoint) -> SKLabelNode {
        let button = SKLabelNode(text: text)
        button.fontName = "CourierNewPS-BoldMT"
        button.fontSize = 20
        button.fontColor = .darkGray
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
            } else if node.name == "twoPlayerButton" {
                let setup = TwoPlayerSetupScene(size: self.size)
                setup.scaleMode = .resizeFill
                view?.presentScene(setup, transition: .fade(withDuration: 0.4))
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
