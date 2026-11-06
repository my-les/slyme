//
//  PauseControl.swift
//  slyme
//
//  High-contrast pause / play control that stays readable on dark maps.
//  Drawn (not a muddy asset) so the bars stay sharp at any size.
//

import SpriteKit
import UIKit

enum PauseControl {
    /// Visual size of the glyph circle. Hit area is larger (see `hitPadding`).
    static let diameter: CGFloat = 48
    static let hitPadding: CGFloat = 14

    /// Returns a node named "pauseButton" with an invisible hit pad + glyph.
    /// `playing` false → show pause bars; true → show play triangle (game is paused).
    static func make(playing: Bool, at position: CGPoint) -> SKNode {
        let root = SKNode()
        root.name = "pauseButton"
        root.position = position
        root.zPosition = 30

        let hit = SKSpriteNode(color: .clear,
                               size: CGSize(width: diameter + hitPadding * 2,
                                            height: diameter + hitPadding * 2))
        hit.name = "pauseButton"
        root.addChild(hit)

        let r = diameter / 2
        let ring = SKShapeNode(circleOfRadius: r)
        ring.fillColor = UIColor(white: 0, alpha: 0.45)
        ring.strokeColor = UIColor(white: 1, alpha: 0.85)
        ring.lineWidth = 2.5
        ring.name = "pauseButton"
        root.addChild(ring)

        let glyph = SKShapeNode(path: playing ? playPath(in: r) : pausePath(in: r))
        glyph.fillColor = .white
        glyph.strokeColor = .clear
        glyph.name = "pauseButton"
        root.addChild(glyph)
        return root
    }

    private static func pausePath(in r: CGFloat) -> CGPath {
        let w = r * 0.28, h = r * 0.95, gap = r * 0.2
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: -gap - w, y: -h / 2, width: w, height: h),
                            cornerWidth: w * 0.25, cornerHeight: w * 0.25)
        path.addRoundedRect(in: CGRect(x: gap, y: -h / 2, width: w, height: h),
                            cornerWidth: w * 0.25, cornerHeight: w * 0.25)
        return path
    }

    private static func playPath(in r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let inset = r * 0.28
        path.move(to: CGPoint(x: -r * 0.25 + inset * 0.2, y: -r * 0.55))
        path.addLine(to: CGPoint(x: r * 0.55, y: 0))
        path.addLine(to: CGPoint(x: -r * 0.25 + inset * 0.2, y: r * 0.55))
        path.closeSubpath()
        return path
    }
}
