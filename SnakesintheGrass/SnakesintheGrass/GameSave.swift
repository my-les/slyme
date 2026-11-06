//
//  GameSave.swift
//  slyme
//
//  Pure save/restore payload for single-player. Unit-tested in
//  slymeTests/GameSaveTests.swift. GameScene reads/writes UserDefaults via this.
//

import Foundation
import CoreGraphics

struct GameSave: Equatable {
    static let key = "savedGameState"
    static let version = 2

    var score: Int
    var level: Int
    var snake: [(Int, Int)]
    var moveDirection: CGVector
    var elapsedTime: TimeInterval
    var skinID: String
    var mapID: String
    var food: (Int, Int)?
    var columns: Int
    var rows: Int

    static func == (l: GameSave, r: GameSave) -> Bool {
        l.score == r.score && l.level == r.level && l.snake.elementsEqual(r.snake, by: ==)
            && l.moveDirection.dx == r.moveDirection.dx && l.moveDirection.dy == r.moveDirection.dy
            && l.elapsedTime == r.elapsedTime && l.skinID == r.skinID && l.mapID == r.mapID
            && l.food?.0 == r.food?.0 && l.food?.1 == r.food?.1
            && l.columns == r.columns && l.rows == r.rows
    }

    func encode() -> [String: Any] {
        var d: [String: Any] = [
            "version": GameSave.version,
            "columns": columns, "rows": rows,
            "score": score, "level": level,
            "snake": snake.map { ["x": $0.0, "y": $0.1] },
            "moveDirection": ["dx": Double(moveDirection.dx), "dy": Double(moveDirection.dy)],
            "elapsedTime": elapsedTime,
            "skin": skinID, "map": mapID,
        ]
        if let f = food { d["food"] = ["x": f.0, "y": f.1] }
        return d
    }

    /// Returns nil when the payload is corrupt, the wrong version/grid, or the
    /// snake leaves the board / overlaps itself.
    static func decode(_ state: [String: Any],
                       columns: Int = MapCatalog.columns,
                       rows: Int = MapCatalog.rows,
                       blocked: (Int, Int) -> Bool = { _, _ in false }) -> GameSave? {
        guard state["version"] as? Int == version,
              state["columns"] as? Int == columns,
              state["rows"] as? Int == rows,
              let raw = state["snake"] as? [[String: Int]], !raw.isEmpty else { return nil }
        let cells = raw.compactMap { d -> (Int, Int)? in
            guard let x = d["x"], let y = d["y"] else { return nil }
            return (x, y)
        }
        guard cells.count == raw.count,
              cells.allSatisfy({ (0..<columns).contains($0.0) && (0..<rows).contains($0.1) }),
              Set(cells.map { $0.0 * 10_000 + $0.1 }).count == cells.count,
              !cells.contains(where: { blocked($0.0, $0.1) }) else { return nil }

        var dir = CGVector(dx: 1, dy: 0)
        if let d = state["moveDirection"] as? [String: Double],
           let dx = d["dx"], let dy = d["dy"], abs(dx) + abs(dy) == 1 {
            dir = CGVector(dx: dx, dy: dy)
        }
        var food: (Int, Int)?
        if let f = state["food"] as? [String: Int], let x = f["x"], let y = f["y"],
           (0..<columns).contains(x), (0..<rows).contains(y),
           !cells.contains(where: { $0 == (x, y) }), !blocked(x, y) {
            food = (x, y)
        }
        return GameSave(score: max(0, state["score"] as? Int ?? 0),
                        level: max(1, state["level"] as? Int ?? 1),
                        snake: cells, moveDirection: dir,
                        elapsedTime: max(0, state["elapsedTime"] as? TimeInterval ?? 0),
                        skinID: state["skin"] as? String ?? SkinCatalog.defaultID,
                        mapID: state["map"] as? String ?? MapCatalog.defaultID,
                        food: food, columns: columns, rows: rows)
    }
}
