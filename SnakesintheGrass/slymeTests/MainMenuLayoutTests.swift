//
//  MainMenuLayoutTests.swift
//  slymeTests
//
//  Rotation / size-change must clear+rebuild the menu, never stack duplicates.
//

import XCTest
import SpriteKit
@testable import slyme

final class MainMenuLayoutTests: XCTestCase {
    func testLayoutClearsBeforeRebuild() {
        let scene = MainMenu(size: CGSize(width: 390, height: 844))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.presentScene(scene)
        let exp1 = expectation(description: "first layout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1)
        let portraitCount = scene.children.count
        XCTAssertGreaterThanOrEqual(portraitCount, 7) // title + subtitle + 5 items
        XCTAssertLessThanOrEqual(portraitCount, 8)

        view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        scene.size = view.bounds.size
        scene.didChangeSize(CGSize(width: 390, height: 844))
        let exp2 = expectation(description: "landscape layout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1)

        XCTAssertEqual(scene.children.count, portraitCount,
                       "rotation must clear before rebuild, not stack a second menu")
        XCTAssertFalse(scene.children.contains { $0.name == "twoPlayerButton" })
        let names = Set(scene.children.compactMap(\.name))
        XCTAssertEqual(names.intersection(["playButton", "onlineButton", "aboutButton",
                                           "highScoresButton", "customizeButton"]).count, 5)
        let mid = scene.size.width / 2
        for node in scene.children {
            XCTAssertEqual(node.position.x, mid, accuracy: 1,
                           "menu item should be horizontally centered after rotate")
        }
    }

    func testRepeatedSizeChangesDoNotAccumulate() {
        let scene = MainMenu(size: CGSize(width: 390, height: 844))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.presentScene(scene)
        let ready = expectation(description: "ready")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ready.fulfill() }
        wait(for: [ready], timeout: 1)
        let base = scene.children.count
        for i in 0..<10 {
            let landscape = i % 2 == 0
            let s = landscape ? CGSize(width: 844, height: 390) : CGSize(width: 390, height: 844)
            view.frame = CGRect(origin: .zero, size: s)
            scene.size = s
            scene.didChangeSize(s)
        }
        let done = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(scene.children.count, base)
    }
}
