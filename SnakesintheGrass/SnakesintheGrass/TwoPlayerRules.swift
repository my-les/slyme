//
//  TwoPlayerRules.swift
//  slyme
//
//  Pure, deterministic rules for local two-player. No SpriteKit, no UIKit,
//  so the collision / winner logic is unit-tested (slymeTests/TwoPlayerRulesTests).
//  See docs/TWO_PLAYER.md.
//

import Foundation

/// Every tunable in one place.
enum TwoPlayerConfig {
    /// First to this many apples wins the match.
    static var applesToWin = 10
    /// Seconds per move at the start of a match. Both snakes always share one tick.
    static var tickInterval: TimeInterval = 0.15
    /// Speed-up: every `applesPerSpeedUp` apples eaten (both players combined)
    /// the tick shrinks by `speedUpStep`, never below `minTickInterval`.
    static var applesPerSpeedUp = 3
    static var speedUpStep: TimeInterval = 0.01
    static var minTickInterval: TimeInterval = 0.06

    /// Speed level (1-based) for a combined apple count. Deterministic.
    static func speedLevel(totalApples: Int) -> Int {
        let maxLevel = Int(((tickInterval - minTickInterval) / speedUpStep).rounded()) + 1
        return min(maxLevel, 1 + max(0, totalApples) / max(1, applesPerSpeedUp))
    }
    /// Shared tick interval for a combined apple count.
    static func tickInterval(totalApples: Int) -> TimeInterval {
        max(minTickInterval, tickInterval - Double(speedLevel(totalApples: totalApples) - 1) * speedUpStep)
    }
    /// Starting snake length (head included).
    static var startLength = 3
    /// Does each apple grow the snake that ate it.
    static var growOnApple = true
    /// Default: P2's labels face across the table (rotated 180) on a flat screen.
    static var defaultFacing = true
    /// Minimum finger travel (pt) before a touch counts as a swipe.
    static var swipeThreshold: Double = 22
}

enum Direction: CaseIterable {
    case up, down, left, right
    var dx: Int { self == .left ? -1 : (self == .right ? 1 : 0) }
    var dy: Int { self == .down ? -1 : (self == .up ? 1 : 0) }
    var opposite: Direction {
        switch self { case .up: return .down; case .down: return .up; case .left: return .right; case .right: return .left }
    }
}

enum PlayerID: Int { case one = 0, two = 1 }

struct VersusSnake: Equatable {
    var body: [GridCell]            // head first
    var direction: Direction
    var apples = 0
    var head: GridCell { body[0] }
}

/// Why a snake lost.
enum DeathCause: Equatable { case wall, obstacle, selfHit, otherBody, headOn }

enum MatchResult: Equatable {
    case winner(PlayerID, reason: Reason)
    case draw
    enum Reason: Equatable { case apples, opponentDied }
}

struct StepEvents: Equatable {
    var ate: [PlayerID] = []
    var deaths: [PlayerID: DeathCause] = [:]
}

struct VersusBoard {
    let columns: Int
    let rows: Int
    let obstacles: Set<GridCell>
    let wraps: Bool

    init(columns: Int = MapCatalog.columns, rows: Int = MapCatalog.rows,
         obstacles: Set<GridCell> = [], wraps: Bool = true) {
        self.columns = columns; self.rows = rows; self.obstacles = obstacles; self.wraps = wraps
    }

    init(map: GameMap) {
        self.init(obstacles: map.obstacles, wraps: map.edges == .wrap)
    }

    /// Next cell, or nil if it leaves a kill-edge board.
    func next(_ c: GridCell, _ d: Direction) -> GridCell? {
        let x = c.x + d.dx, y = c.y + d.dy
        if (0..<columns).contains(x) && (0..<rows).contains(y) { return GridCell(x, y) }
        guard wraps else { return nil }
        return GridCell((x + columns) % columns, (y + rows) % rows)
    }
}

/// Whole match state. `step()` advances both snakes simultaneously.
struct VersusMatch {
    let board: VersusBoard
    var snakes: [VersusSnake]       // index = PlayerID.rawValue
    var apple: GridCell?
    var result: MatchResult?
    /// Injected so tests are deterministic. Gets the list of free cells.
    var pickApple: ([GridCell]) -> GridCell? = { $0.randomElement() }

    init(board: VersusBoard, p1: VersusSnake, p2: VersusSnake, apple: GridCell? = nil,
         pickApple: (([GridCell]) -> GridCell?)? = nil) {
        self.board = board
        self.snakes = [p1, p2]
        if let pickApple { self.pickApple = pickApple }
        self.apple = apple
        if apple == nil { spawnApple() }
    }

    var totalApples: Int { snakes.reduce(0) { $0 + $1.apples } }
    var speedLevel: Int { TwoPlayerConfig.speedLevel(totalApples: totalApples) }
    var tickInterval: TimeInterval { TwoPlayerConfig.tickInterval(totalApples: totalApples) }

    subscript(p: PlayerID) -> VersusSnake {
        get { snakes[p.rawValue] }
        set { snakes[p.rawValue] = newValue }
    }

    /// Ignore reversals into your own neck; everything else applies on the next step.
    mutating func turn(_ p: PlayerID, _ d: Direction) {
        let s = self[p]
        if s.body.count > 1, let neck = board.next(s.head, d), neck == s.body[1] { return }
        if d == s.direction.opposite && s.body.count > 1 { return }
        self[p].direction = d
    }

    func freeCells() -> [GridCell] {
        let used = Set(snakes.flatMap { $0.body })
        var out: [GridCell] = []
        for x in 0..<board.columns { for y in 0..<board.rows {
            let c = GridCell(x, y)
            if !used.contains(c) && !board.obstacles.contains(c) { out.append(c) }
        } }
        return out
    }

    mutating func spawnApple() { apple = pickApple(freeCells()) }

    /// One simultaneous tick. Returns what happened; sets `result` when the match ends.
    @discardableResult
    mutating func step() -> StepEvents {
        var ev = StepEvents()
        guard result == nil else { return ev }
        let ids: [PlayerID] = [.one, .two]
        var newHeads: [PlayerID: GridCell] = [:]
        for p in ids {
            if let h = board.next(self[p].head, self[p].direction) { newHeads[p] = h }
            else { ev.deaths[p] = .wall }
        }
        // Who eats (both arriving on the apple is a head-on, handled below).
        var eats: Set<PlayerID> = []
        for p in ids where newHeads[p] != nil && newHeads[p] == apple { eats.insert(p) }

        // Bodies after the move: tail leaves unless that snake eats.
        var moved: [PlayerID: [GridCell]] = [:]
        for p in ids {
            guard let h = newHeads[p] else { moved[p] = self[p].body; continue }
            var b = [h] + self[p].body
            if !(eats.contains(p) && TwoPlayerConfig.growOnApple) { b.removeLast() }
            moved[p] = b
        }

        if let h1 = newHeads[.one], let h2 = newHeads[.two] {
            let swapped = h1 == self[.two].head && h2 == self[.one].head
            if h1 == h2 || swapped {
                ev.deaths[.one] = .headOn; ev.deaths[.two] = .headOn
            }
        }
        for p in ids where ev.deaths[p] == nil {
            let other: PlayerID = p == .one ? .two : .one
            guard let h = newHeads[p] else { continue }
            if board.obstacles.contains(h) { ev.deaths[p] = .obstacle }
            else if moved[p]!.dropFirst().contains(h) { ev.deaths[p] = .selfHit }
            else if moved[other]!.contains(h) { ev.deaths[p] = .otherBody }
        }

        for p in ids { self[p].body = moved[p]! }
        for p in eats where ev.deaths[p] == nil {
            self[p].apples += 1
            ev.ate.append(p)
        }
        if !ev.ate.isEmpty { spawnApple() }
        result = VersusMatch.decide(snakes: snakes, deaths: ev.deaths)
        return ev
    }

    /// Death ends the match at once: the survivor wins. Both die on the same
    /// tick: more apples wins, equal is a draw. Otherwise first to applesToWin.
    static func decide(snakes: [VersusSnake], deaths: [PlayerID: DeathCause]) -> MatchResult? {
        let a = snakes[0].apples, b = snakes[1].apples
        switch (deaths[.one] != nil, deaths[.two] != nil) {
        case (true, true): return a == b ? .draw : .winner(a > b ? .one : .two, reason: .apples)
        case (true, false): return .winner(.two, reason: .opponentDied)
        case (false, true): return .winner(.one, reason: .opponentDied)
        default: break
        }
        if a >= TwoPlayerConfig.applesToWin { return .winner(.one, reason: .apples) }
        if b >= TwoPlayerConfig.applesToWin { return .winner(.two, reason: .apples) }
        return nil
    }

    /// Start positions: P1 low-left heading up, P2 high-right heading down, both
    /// toward the middle, nudged to the nearest spot clear of obstacles.
    static func startSnakes(board: VersusBoard, length: Int = TwoPlayerConfig.startLength) -> (VersusSnake, VersusSnake) {
        func place(preferred: GridCell, dir: Direction) -> VersusSnake {
            func cells(from h: GridCell) -> [GridCell]? {
                var out = [h]
                for i in 1..<max(1, length) {
                    let c = GridCell(h.x - dir.dx * i, h.y - dir.dy * i)
                    guard (0..<board.columns).contains(c.x), (0..<board.rows).contains(c.y) else { return nil }
                    out.append(c)
                }
                // Clear lane ahead too.
                for i in 1...4 {
                    let c = GridCell(h.x + dir.dx * i, h.y + dir.dy * i)
                    guard (0..<board.columns).contains(c.x), (0..<board.rows).contains(c.y) else { return nil }
                    out.append(c)
                }
                return out.contains(where: board.obstacles.contains) ? nil : Array(out.prefix(max(1, length)))
            }
            if let b = cells(from: preferred) { return VersusSnake(body: b, direction: dir) }
            var best: [GridCell]?; var bestD = Int.max
            for x in 0..<board.columns { for y in 0..<board.rows {
                let d = abs(x - preferred.x) + abs(y - preferred.y)
                if d < bestD, let b = cells(from: GridCell(x, y)) { best = b; bestD = d }
            } }
            return VersusSnake(body: best ?? [preferred], direction: dir)
        }
        let p1 = place(preferred: GridCell(board.columns / 4, board.rows / 4), dir: .up)
        let p2 = place(preferred: GridCell(board.columns - 1 - board.columns / 4, board.rows - 1 - board.rows / 4), dir: .down)
        return (p1, p2)
    }
}
