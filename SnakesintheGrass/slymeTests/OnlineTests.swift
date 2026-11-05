//
//  OnlineTests.swift
//  slymeTests
//
//  Online versus without Game Center: codec round-trips, and two OnlineSessions
//  talking over an in-process LoopbackLink.
//

import XCTest
@testable import slyme

final class OnlineCodecTests: XCTestCase {
    private func roundTrip(_ m: OnlineMessage, file: StaticString = #filePath, line: UInt = #line) {
        let d = OnlineCodec.encode(m)
        XCTAssertEqual(OnlineCodec.decode(d), m, file: file, line: line)
    }

    func testAllMessagesRoundTrip() {
        let s1 = VersusSnake(body: [GridCell(3, 4), GridCell(3, 3), GridCell(3, 2)], direction: .up, apples: 4)
        let s2 = VersusSnake(body: [GridCell(17, 31), GridCell(0, 31)], direction: .right, apples: 9)
        let st = OnlineState(round: 3, tick: 70_000, snakes: [s1, s2], apple: GridCell(9, 16), result: nil)
        roundTrip(.hello(version: 1, nonce: 0xDEADBEEF, skin: "gold", map: "pillars", ownedMaps: ["void", "lawn", "concrete"]))
        roundTrip(.hello(version: 1, nonce: 0, skin: "", map: "void", ownedMaps: []))
        roundTrip(.start(round: 1, seed: .max, map: "void", hostSkin: "og", guestSkin: "ember"))
        for d in Direction.allCases { roundTrip(.input(round: 2, tick: 12, dir: d)) }
        roundTrip(.state(st))
        var noApple = st; noApple.apple = nil
        roundTrip(.state(noApple))
        for r: MatchResult in [.draw, .winner(.one, reason: .apples), .winner(.one, reason: .opponentDied),
                               .winner(.two, reason: .apples), .winner(.two, reason: .opponentDied)] {
            var e = st; e.result = r
            roundTrip(.end(e))
        }
        roundTrip(.ping(123)); roundTrip(.pong(.max))
        roundTrip(.away(true)); roundTrip(.away(false))
        roundTrip(.forfeit); roundTrip(.rematch(round: 9)); roundTrip(.quit)
    }

    func testMalformedIsRejected() {
        XCTAssertNil(OnlineCodec.decode(Data()))
        XCTAssertNil(OnlineCodec.decode(Data([0xFF])))
        let good = OnlineCodec.encode(.input(round: 1, tick: 1, dir: .up))
        XCTAssertNil(OnlineCodec.decode(good.dropLast()))           // truncated
        XCTAssertNil(OnlineCodec.decode(good + Data([0])))          // trailing junk
        var badDir = good; badDir[badDir.count - 1] = 9
        XCTAssertNil(OnlineCodec.decode(badDir))
    }

    func testStateIsCompact() {
        let body = (0..<13).map { GridCell($0, 0) }
        let st = OnlineState(round: 1, tick: 1, snakes: [VersusSnake(body: body, direction: .up),
                                                         VersusSnake(body: body, direction: .down)],
                             apple: GridCell(1, 1), result: nil)
        XCTAssertLessThan(OnlineCodec.encode(.state(st)).count, 100)
    }

    func testSeededRNGIsDeterministic() {
        let a = SeededRNG(seed: 42), b = SeededRNG(seed: 42)
        let xs = (0..<50).map { _ in a.next() }, ys = (0..<50).map { _ in b.next() }
        XCTAssertEqual(xs, ys)
        XCTAssertNotEqual(xs, (0..<50).map { _ in SeededRNG(seed: 43).next() })
    }

    func testMapChoice() {
        XCTAssertEqual(OnlineSession.chooseMap(hostMap: "pillars", guestOwned: ["void", "pillars"]), "pillars")
        XCTAssertEqual(OnlineSession.chooseMap(hostMap: "pillars", guestOwned: ["void", "lawn"]), "void")
        XCTAssertEqual(OnlineSession.chooseMap(hostMap: "nope", guestOwned: ["nope"]), "void")
    }
}

final class OnlineSessionTests: XCTestCase {
    private var link: LoopbackLink!
    private var host: OnlineSession!
    private var guest: OnlineSession!
    private var saved: (Int, TimeInterval) = (0, 0)

    override func setUp() {
        saved = (TwoPlayerConfig.applesToWin, OnlineConfig.awayGrace)
        link = LoopbackLink()
        // Higher nonce hosts. Guest begins first to show order doesn't matter.
        host = OnlineSession(transport: link.a, localID: "A", skin: "gold", map: "lawn",
                             ownedMaps: ["void", "lawn", "concrete"], nonce: 900)
        guest = OnlineSession(transport: link.b, localID: "B", skin: "ember", map: "void",
                              ownedMaps: ["void", "lawn", "concrete"], nonce: 100)
    }
    override func tearDown() {
        TwoPlayerConfig.applesToWin = saved.0; OnlineConfig.awayGrace = saved.1
    }

    private func connect() {
        guest.begin(now: 0); host.begin(now: 0); link.pump()
    }

    func testHandshakeElectsHostAndAgreesOnRound() {
        connect()
        XCTAssertEqual(host.role, .host); XCTAssertEqual(guest.role, .guest)
        XCTAssertEqual(host.me, .one); XCTAssertEqual(guest.me, .two)
        XCTAssertEqual(host.phase, .countdown); XCTAssertEqual(guest.phase, .countdown)
        XCTAssertEqual(guest.mapID, "lawn")          // guest owns it
        XCTAssertEqual(guest.mySkin, "ember"); XCTAssertEqual(guest.theirSkin, "gold")
        XCTAssertEqual(host.mySkin, "gold"); XCTAssertEqual(host.theirSkin, "ember")
        XCTAssertEqual(host.state, guest.state)
    }

    func testTieBreakOnEqualNonce() {
        let l = LoopbackLink()
        let a = OnlineSession(transport: l.a, localID: "zzz", skin: "og", map: "void", ownedMaps: ["void"], nonce: 5)
        let b = OnlineSession(transport: l.b, localID: "aaa", skin: "og", map: "void", ownedMaps: ["void"], nonce: 5)
        a.setRemoteID("aaa"); b.setRemoteID("zzz")
        a.begin(); b.begin(); l.pump()
        XCTAssertEqual(a.role, .guest); XCTAssertEqual(b.role, .host)
    }

    func testUnknownSkinFallsBackToOgAndUnownedMapToVoid() {
        let l = LoopbackLink()
        let h = OnlineSession(transport: l.a, localID: "A", skin: "og", map: "pillars", ownedMaps: ["void", "pillars"], nonce: 2)
        let g = OnlineSession(transport: l.b, localID: "B", skin: "future_skin_v9", map: "void", ownedMaps: ["void"], nonce: 1)
        h.begin(); g.begin(); l.pump()
        XCTAssertEqual(h.theirSkin, SkinCatalog.defaultID)
        XCTAssertEqual(g.mySkin, SkinCatalog.defaultID)
        XCTAssertEqual(g.mapID, "void"); XCTAssertEqual(h.mapID, "void")
    }

    func testGuestMirrorsHostEveryTickAndInputsApply() {
        connect()
        guest.localTurn(.right); link.pump()
        for _ in 0..<5 { host.hostStep(); link.pump() }
        XCTAssertEqual(guest.phase, .playing)
        XCTAssertEqual(guest.state, host.state)
        XCTAssertEqual(host.match?[.two].direction, .right)
        XCTAssertEqual(guest.state?.tick, 5)
    }

    func testLostStatePacketsRecoverOnNextTick() {
        connect()
        link.dropUnreliable = true
        host.hostStep(); host.hostStep(); link.pump()
        XCTAssertEqual(guest.state?.tick, 0)
        link.dropUnreliable = false
        host.hostStep(); link.pump()
        XCTAssertEqual(guest.state, host.state)
    }

    func testSameSeedSameApplesDeterministic() {
        // Two hosts with the same seed and inputs produce identical games.
        func run() -> [OnlineState] {
            let board = VersusBoard(map: MapCatalog.all[0])
            let (a, b) = VersusMatch.startSnakes(board: board)
            let rng = SeededRNG(seed: 77)
            var m = VersusMatch(board: board, p1: a, p2: b, pickApple: { rng.pick($0) })
            var out: [OnlineState] = []
            for t in 0..<60 {
                if t % 7 == 0 { m.turn(.one, t % 14 == 0 ? .right : .up) }
                m.step(); out.append(OnlineState(round: 1, tick: UInt32(t), match: m))
            }
            return out
        }
        XCTAssertEqual(run(), run())
    }

    func testMatchEndReachesBothWithSameResult() {
        TwoPlayerConfig.applesToWin = 1
        connect()
        // Put the apple right in front of the host's snake.
        var ends: [OnlineEnd] = []
        host.onEnd = { ends.append($0) }; guest.onEnd = { ends.append($0) }
        var n = 0
        while host.phase != .ended && n < 2000 {
            if let st = host.state, let a = st.apple {
                let h = st.snakes[0].head
                let d: Direction = a.x > h.x ? .right : (a.x < h.x ? .left : (a.y > h.y ? .up : .down))
                host.localTurn(d)
            }
            host.hostStep(); link.pump(); n += 1
        }
        XCTAssertEqual(host.phase, .ended); XCTAssertEqual(guest.phase, .ended)
        XCTAssertEqual(host.end, guest.end)
        XCTAssertEqual(ends.count, 2)
        XCTAssertEqual(host.state, guest.state)
    }

    func testAdvanceTicksAtTickRateAfterStartDelay() {
        connect()
        host.advance(now: 0); link.pump()
        host.advance(now: OnlineConfig.startDelay - 0.01); link.pump()
        XCTAssertEqual(host.state?.tick, 0)
        host.advance(now: OnlineConfig.startDelay); link.pump()
        XCTAssertEqual(host.state?.tick, 1)
        host.advance(now: OnlineConfig.startDelay + TwoPlayerConfig.tickInterval * 3 + 0.001); link.pump()
        XCTAssertEqual(host.state?.tick, 4)
        XCTAssertEqual(guest.state?.tick, 4)
    }

    func testDisconnectMidMatchGivesWin() {
        connect()
        guest.quit(); link.pump()
        XCTAssertEqual(host.end, .opponentLeft)
        XCTAssertTrue(host.opponentGone)
    }

    func testAwayPausesThenForfeitsAfterGrace() {
        OnlineConfig.awayGrace = 10
        connect()
        host.advance(now: 2); link.pump()
        let t0 = host.state?.tick ?? 0
        guest.setLocalAway(true, now: 2); link.pump()
        host.advance(now: 3); link.pump()            // host learns "away" at its clock 3
        host.advance(now: 8); link.pump()
        XCTAssertEqual(host.state?.tick, t0, "simulation pauses while opponent is away")
        XCTAssertEqual(host.phase == .ended, false)
        host.advance(now: 13.5); link.pump()
        XCTAssertEqual(host.end, .opponentForfeited)
        XCTAssertEqual(guest.end, .youForfeited)
    }

    func testAwayAndBackResumes() {
        connect()
        guest.setLocalAway(true, now: 0); link.pump()
        guest.setLocalAway(false, now: 1); link.pump()
        host.advance(now: 5); host.advance(now: 5 + OnlineConfig.startDelay); link.pump()
        XCTAssertNil(host.end)
        XCTAssertGreaterThan(host.state?.tick ?? 0, 0)
    }

    func testRematchNeedsBothThenStartsNewRound() {
        TwoPlayerConfig.applesToWin = 1
        connect()
        // Drive the host toward the apple until the match ends.
        var n = 0
        while host.phase != .ended && n < 3000 {
            if let st = host.state, let a = st.apple {
                let h = st.snakes[0].head
                host.localTurn(a.x > h.x ? .right : (a.x < h.x ? .left : (a.y > h.y ? .up : .down)))
            }
            host.hostStep(); link.pump(); n += 1
        }
        XCTAssertEqual(guest.phase, .ended)
        host.requestRematch(); link.pump()
        XCTAssertEqual(host.phase, .ended)
        XCTAssertTrue(guest.rematchRemote)
        guest.requestRematch(); link.pump()
        XCTAssertEqual(host.round, 2); XCTAssertEqual(guest.round, 2)
        XCTAssertEqual(host.phase, .countdown); XCTAssertEqual(guest.phase, .countdown)
        XCTAssertEqual(host.state, guest.state)
        XCTAssertEqual(host.state?.totalApples, 0)
    }

    func testVersionMismatchEndsCleanly() {
        let l = LoopbackLink()
        let a = OnlineSession(transport: l.a, localID: "A", skin: "og", map: "void", ownedMaps: ["void"], nonce: 2)
        a.begin()
        l.b.onReceive = { _ in }
        l.b.send(OnlineCodec.encode(.hello(version: 99, nonce: 1, skin: "og", map: "void", ownedMaps: [])), reliable: true)
        l.pump()
        XCTAssertEqual(a.end, .versionMismatch)
    }

    func testLatencyMeasured() {
        connect()
        host.advance(now: 2)        // sends ping stamped 2000ms (queued)
        host.advance(now: 2.05)     // 50ms pass before anything is delivered
        link.pump()                 // guest pongs, host receives at 2.05
        XCTAssertEqual(host.rtt ?? -1, 0.05, accuracy: 0.002)
    }
}

final class OnlineViewFlipTests: XCTestCase {
    func testCellFlipIsInvolution() {
        let cells = [GridCell(0, 0), GridCell(17, 31), GridCell(4, 12), GridCell(9, 16)]
        for c in cells {
            XCTAssertEqual(OnlineViewFlip.cell(OnlineViewFlip.cell(c)), c)
        }
    }

    func testCornersSwap() {
        XCTAssertEqual(OnlineViewFlip.cell(GridCell(0, 0)), GridCell(17, 31))
        XCTAssertEqual(OnlineViewFlip.cell(GridCell(17, 31)), GridCell(0, 0))
        XCTAssertEqual(OnlineViewFlip.cell(GridCell(0, 31)), GridCell(17, 0))
        XCTAssertEqual(OnlineViewFlip.cell(GridCell(17, 0)), GridCell(0, 31))
    }

    func testGuestStartAppearsAtBottom() {
        // Host P1 starts low-left; guest P2 starts high-right. After flip the
        // guest's head is in the low-left quadrant of THEIR screen.
        let board = VersusBoard()
        let (_, p2) = VersusMatch.startSnakes(board: board)
        let v = OnlineViewFlip.cell(p2.head)
        XCTAssertLessThan(v.x, MapCatalog.columns / 2)
        XCTAssertLessThan(v.y, MapCatalog.rows / 2)
    }

    func testDirectionsAreOpposites() {
        for d in Direction.allCases {
            XCTAssertEqual(OnlineViewFlip.direction(d), d.opposite)
            XCTAssertEqual(OnlineViewFlip.boardDirection(fromScreen: d), d.opposite)
            XCTAssertEqual(OnlineViewFlip.direction(OnlineViewFlip.direction(d)), d)
        }
    }

    func testSwipeUpOnGuestScreenIsBoardDown() {
        // Guest wants the snake to move toward the top of THEIR screen when
        // they swipe up. Top of their screen is board-down after the flip.
        XCTAssertEqual(OnlineViewFlip.boardDirection(fromScreen: .up), .down)
        XCTAssertEqual(OnlineViewFlip.boardDirection(fromScreen: .down), .up)
        XCTAssertEqual(OnlineViewFlip.boardDirection(fromScreen: .left), .right)
        XCTAssertEqual(OnlineViewFlip.boardDirection(fromScreen: .right), .left)
    }

    func testObstacleFlipKeepsRelativeAlignment() {
        // An obstacle and a snake cell that share a board neighbour stay
        // neighbours after the view flip (map art rotates with the snakes).
        let a = GridCell(4, 6), b = GridCell(5, 6)
        let fa = OnlineViewFlip.cell(a), fb = OnlineViewFlip.cell(b)
        XCTAssertEqual(abs(fa.x - fb.x) + abs(fa.y - fb.y), abs(a.x - b.x) + abs(a.y - b.y))
        XCTAssertEqual(OnlineViewFlip.cell(GridCell(4, 6)), GridCell(13, 25)) // pillars corner sample
    }
}
