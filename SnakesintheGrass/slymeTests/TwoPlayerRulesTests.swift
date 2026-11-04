//
//  TwoPlayerRulesTests.swift
//  slymeTests
//

import XCTest
@testable import slyme

final class TwoPlayerRulesTests: XCTestCase {
    private func c(_ x: Int, _ y: Int) -> GridCell { GridCell(x, y) }
    private func snake(_ cells: [(Int, Int)], _ d: Direction, apples: Int = 0) -> VersusSnake {
        VersusSnake(body: cells.map { GridCell($0.0, $0.1) }, direction: d, apples: apples)
    }
    private func match(_ p1: VersusSnake, _ p2: VersusSnake, apple: GridCell = GridCell(0, 0),
                       board: VersusBoard = VersusBoard(columns: 10, rows: 10)) -> VersusMatch {
        VersusMatch(board: board, p1: p1, p2: p2, apple: apple, pickApple: { $0.first })
    }

    func testPlainMoveNoResult() {
        var m = match(snake([(2,2),(2,1),(2,0)], .up), snake([(7,7),(7,8),(7,9)], .down))
        let ev = m.step()
        XCTAssertTrue(ev.deaths.isEmpty)
        XCTAssertEqual(m[.one].body, [c(2,3), c(2,2), c(2,1)])
        XCTAssertNil(m.result)
    }

    func testWallKillsOnKillEdgeBoard() {
        var m = match(snake([(2,9),(2,8)], .up), snake([(7,5),(7,6)], .down),
                      board: VersusBoard(columns: 10, rows: 10, wraps: false))
        let ev = m.step()
        XCTAssertEqual(ev.deaths[.one], .wall)
        XCTAssertEqual(m.result, .winner(.two, reason: .opponentDied))
    }

    func testWrapBoardWraps() {
        var m = match(snake([(2,9),(2,8)], .up), snake([(7,5),(7,6)], .down))
        m.step()
        XCTAssertEqual(m[.one].head, c(2,0))
        XCTAssertNil(m.result)
    }

    func testObstacleKills() {
        var m = match(snake([(2,2),(2,1)], .up), snake([(7,5),(7,6)], .down),
                      board: VersusBoard(columns: 10, rows: 10, obstacles: [GridCell(2,3)]))
        XCTAssertEqual(m.step().deaths[.one], .obstacle)
    }

    func testHitOtherBodyLoses() {
        var m = match(snake([(4,5),(3,5)], .right), snake([(5,4),(5,5),(5,6)], .down))
        // P2 after move: (5,3),(5,4),(5,5). P1 enters (5,5), still P2's body.
        let ev = m.step()
        XCTAssertEqual(ev.deaths[.one], .otherBody)
        XCTAssertEqual(m.result, .winner(.two, reason: .opponentDied))
    }

    func testSelfHit() {
        var m = match(snake([(5,5),(5,4),(6,4),(6,5),(6,6)], .up), snake([(0,9),(1,9)], .left))
        m.turn(.one, .right) // into (6,5), which is still body after tail moves
        XCTAssertEqual(m.step().deaths[.one], .selfHit)
    }

    func testHeadOnSameCellEqualApplesIsDraw() {
        var m = match(snake([(4,5),(3,5)], .right, apples: 2), snake([(6,5),(7,5)], .left, apples: 2))
        let ev = m.step()
        XCTAssertEqual(ev.deaths[.one], .headOn); XCTAssertEqual(ev.deaths[.two], .headOn)
        XCTAssertEqual(m.result, .draw)
    }

    func testHeadOnMoreApplesWins() {
        var m = match(snake([(4,5),(3,5)], .right, apples: 3), snake([(6,5),(7,5)], .left, apples: 1))
        m.step()
        XCTAssertEqual(m.result, .winner(.one, reason: .apples))
    }

    func testHeadSwapIsHeadOn() {
        var m = match(snake([(4,5),(3,5)], .right), snake([(5,5),(6,5)], .left))
        let ev = m.step()
        XCTAssertEqual(ev.deaths[.one], .headOn); XCTAssertEqual(ev.deaths[.two], .headOn)
        XCTAssertEqual(m.result, .draw)
    }

    func testMovingIntoOtherTailThatMovesOutIsSafe() {
        // P2 tail at (5,5) leaves this tick as P1 enters it.
        var m = match(snake([(4,5),(3,5)], .right), snake([(5,7),(5,6),(5,5)], .up))
        let ev = m.step()
        XCTAssertTrue(ev.deaths.isEmpty)
        XCTAssertEqual(m[.one].head, c(5,5))
    }

    func testFollowingOwnTailIsSafe() {
        var m = match(snake([(5,5),(5,4),(6,4),(6,5)], .up), snake([(0,9),(1,9)], .left))
        m.turn(.one, .right) // into (6,5) = own tail, which moves out
        XCTAssertTrue(m.step().deaths.isEmpty)
    }

    func testEatGrowsAndScoresAndRespawns() {
        var m = match(snake([(2,2),(2,1)], .up), snake([(7,7),(7,8)], .down), apple: GridCell(2,3))
        let ev = m.step()
        XCTAssertEqual(ev.ate, [.one])
        XCTAssertEqual(m[.one].apples, 1)
        XCTAssertEqual(m[.one].body.count, 3)
        XCTAssertNotNil(m.apple)
        XCTAssertNotEqual(m.apple, c(2,3))
        XCTAssertFalse(m[.one].body.contains(m.apple!))
    }

    func testSameTickAppleIsHeadOnNoScore() {
        var m = match(snake([(4,5),(3,5)], .right), snake([(6,5),(7,5)], .left), apple: GridCell(5,5))
        let ev = m.step()
        XCTAssertTrue(ev.ate.isEmpty)
        XCTAssertEqual(m.result, .draw)
    }

    func testFirstToGoalWins() {
        let goal = TwoPlayerConfig.applesToWin
        var m = match(snake([(2,2),(2,1)], .up, apples: goal - 1), snake([(7,7),(7,8)], .down), apple: GridCell(2,3))
        m.step()
        XCTAssertEqual(m.result, .winner(.one, reason: .apples))
    }

    func testNeckReversalIgnored() {
        var m = match(snake([(2,2),(2,1)], .up), snake([(7,7),(7,8)], .down))
        m.turn(.one, .down)
        XCTAssertEqual(m[.one].direction, .up)
        m.turn(.one, .left)
        XCTAssertEqual(m[.one].direction, .left)
        m.step()
        XCTAssertEqual(m[.one].head, c(1,2))
    }

    func testNoStepAfterResult() {
        var m = match(snake([(4,5),(3,5)], .right), snake([(5,5),(6,5)], .left))
        m.step()
        let body = m[.one].body
        XCTAssertTrue(m.step().deaths.isEmpty)
        XCTAssertEqual(m[.one].body, body)
    }

    func testSpeedUpIsDeterministicAndFloored() {
        let step = TwoPlayerConfig.applesPerSpeedUp
        XCTAssertEqual(TwoPlayerConfig.tickInterval(totalApples: 0), TwoPlayerConfig.tickInterval, accuracy: 1e-9)
        XCTAssertEqual(TwoPlayerConfig.tickInterval(totalApples: step - 1), TwoPlayerConfig.tickInterval, accuracy: 1e-9)
        XCTAssertEqual(TwoPlayerConfig.tickInterval(totalApples: step),
                       TwoPlayerConfig.tickInterval - TwoPlayerConfig.speedUpStep, accuracy: 1e-9)
        XCTAssertEqual(TwoPlayerConfig.speedLevel(totalApples: step), 2)
        XCTAssertEqual(TwoPlayerConfig.tickInterval(totalApples: 1000), TwoPlayerConfig.minTickInterval, accuracy: 1e-9)
        var prev = TwoPlayerConfig.tickInterval(totalApples: 0)
        for n in 1...100 {
            let t = TwoPlayerConfig.tickInterval(totalApples: n)
            XCTAssertLessThanOrEqual(t, prev); prev = t
        }
        // Combined apples from both players drive the shared tick.
        let m = match(snake([(2,2),(2,1)], .up, apples: 2), snake([(7,7),(7,8)], .down, apples: step - 2))
        XCTAssertEqual(m.totalApples, step)
        XCTAssertEqual(m.speedLevel, 2)
    }

    func testStartSnakesClearOfObstaclesAndApart() {
        let map = MapCatalog.all.first { !$0.obstacles.isEmpty } ?? MapCatalog.all[0]
        let board = VersusBoard(map: map)
        let (a, b) = VersusMatch.startSnakes(board: board)
        XCTAssertEqual(a.body.count, TwoPlayerConfig.startLength)
        XCTAssertTrue(Set(a.body).isDisjoint(with: board.obstacles))
        XCTAssertTrue(Set(b.body).isDisjoint(with: board.obstacles))
        XCTAssertTrue(Set(a.body).isDisjoint(with: Set(b.body)))
    }
}
