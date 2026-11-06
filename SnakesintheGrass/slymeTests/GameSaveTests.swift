//
//  GameSaveTests.swift
//  slymeTests
//

import XCTest
import CoreGraphics
@testable import slyme

final class GameSaveTests: XCTestCase {
    func testRoundTripPreservesSnakeSkinMapScore() {
        let save = GameSave(score: 120, level: 3,
                            snake: [(5, 5), (4, 5), (3, 5), (3, 4)],
                            moveDirection: CGVector(dx: 1, dy: 0),
                            elapsedTime: 12.5, skinID: "ember", mapID: "lawn",
                            food: (9, 16), columns: 18, rows: 32)
        let decoded = GameSave.decode(save.encode())
        XCTAssertEqual(decoded, save)
    }

    func testCorruptOrWrongGridIsRejected() {
        var d = GameSave(score: 10, level: 1, snake: [(1, 1)], moveDirection: .init(dx: 1, dy: 0),
                         elapsedTime: 1, skinID: "og", mapID: "void", food: nil,
                         columns: 18, rows: 32).encode()
        d["version"] = 1
        XCTAssertNil(GameSave.decode(d))
        d = GameSave(score: 10, level: 1, snake: [(1, 1)], moveDirection: .init(dx: 1, dy: 0),
                     elapsedTime: 1, skinID: "og", mapID: "void", food: nil,
                     columns: 18, rows: 32).encode()
        d["columns"] = 10
        XCTAssertNil(GameSave.decode(d))
        d = GameSave(score: 10, level: 1, snake: [(1, 1), (1, 1)], moveDirection: .init(dx: 1, dy: 0),
                     elapsedTime: 1, skinID: "og", mapID: "void", food: nil,
                     columns: 18, rows: 32).encode()
        XCTAssertNil(GameSave.decode(d), "overlapping snake rejected")
    }

    func testBlockedCellRejected() {
        let d = GameSave(score: 10, level: 1, snake: [(4, 8)], moveDirection: .init(dx: 0, dy: 1),
                         elapsedTime: 0, skinID: "og", mapID: "feast", food: nil,
                         columns: 18, rows: 32).encode()
        XCTAssertNil(GameSave.decode(d, blocked: { x, y in x == 4 && y == 8 }))
        XCTAssertNotNil(GameSave.decode(d, blocked: { _, _ in false }))
    }

    func testFeastMapIsSeasonalFree() throws {
        let feast = try XCTUnwrap(MapCatalog.map(id: "feast"))
        XCTAssertEqual(feast.tier, .free)
        XCTAssertFalse(feast.obstacles.isEmpty)
        let inSeason = SkinCatalog.date("2026-11-20")!
        let offSeason = SkinCatalog.date("2026-07-01")!
        XCTAssertTrue(feast.isAvailable(at: inSeason))
        XCTAssertFalse(feast.isAvailable(at: offSeason))
        let visible = MapCatalog.visible(owned: { _ in false }, at: inSeason)
        XCTAssertTrue(visible.contains(where: { $0.id == "feast" }))
        let hidden = MapCatalog.visible(owned: { _ in false }, at: offSeason)
        XCTAssertFalse(hidden.contains(where: { $0.id == "feast" }))
    }

    func testStartSpeedIsSlowerThanBefore() {
        // Documented targets after the slowdown: SP 0.13, versus/online 0.15.
        // Ramp factor / min floors unchanged.
        XCTAssertEqual(TwoPlayerConfig.tickInterval, 0.15, accuracy: 1e-9)
        XCTAssertEqual(TwoPlayerConfig.minTickInterval, 0.06, accuracy: 1e-9)
        XCTAssertEqual(TwoPlayerConfig.speedUpStep, 0.01, accuracy: 1e-9)
        XCTAssertGreaterThan(TwoPlayerConfig.tickInterval(totalApples: 0),
                             TwoPlayerConfig.tickInterval(totalApples: TwoPlayerConfig.applesPerSpeedUp))
    }
}
