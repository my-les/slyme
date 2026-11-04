//
//  OnlineProtocol.swift
//  slyme
//
//  Wire format for online versus. Pure Foundation (no GameKit), so it is
//  unit-tested in slymeTests/OnlineTests.swift. See docs/ONLINE_PLAY.md.
//

import Foundation

/// Bump when the wire format changes; mismatched versions refuse to play.
enum OnlineConfig {
    static let protocolVersion: UInt8 = 1
    /// Seconds an opponent may be backgrounded before they forfeit.
    static var awayGrace: TimeInterval = 10
    /// Re-send hello until a start arrives (covers a late GKMatch delegate).
    static var helloInterval: TimeInterval = 1
    static var pingInterval: TimeInterval = 1
    /// Beat before the first move of each round.
    static var startDelay: TimeInterval = 1.0
}

/// Authoritative snapshot the host sends every tick. Host is always P1 (.one).
struct OnlineState: Equatable {
    var round: UInt16
    var tick: UInt32
    var snakes: [VersusSnake]
    var apple: GridCell?
    var result: MatchResult?

    init(round: UInt16, tick: UInt32, match: VersusMatch) {
        self.round = round; self.tick = tick
        snakes = match.snakes; apple = match.apple; result = match.result
    }
    init(round: UInt16, tick: UInt32, snakes: [VersusSnake], apple: GridCell?, result: MatchResult?) {
        self.round = round; self.tick = tick; self.snakes = snakes; self.apple = apple; self.result = result
    }
    var totalApples: Int { snakes.reduce(0) { $0 + $1.apples } }
}

enum OnlineMessage: Equatable {
    case hello(version: UInt8, nonce: UInt32, skin: String, map: String, ownedMaps: [String])
    case start(round: UInt16, seed: UInt64, map: String, hostSkin: String, guestSkin: String)
    case input(round: UInt16, tick: UInt32, dir: Direction)
    case state(OnlineState)
    case end(OnlineState)
    case ping(UInt32)
    case pong(UInt32)
    case away(Bool)
    case forfeit            // "you were away too long"
    case rematch(round: UInt16)
    case quit

    /// Delivery for GKMatch: only per-tick state and pings may be dropped
    /// (the next one supersedes them). Everything else must arrive.
    var reliable: Bool {
        switch self { case .state, .ping, .pong: return false; default: return true }
    }
}

// MARK: - Binary codec

extension Direction {
    var code: UInt8 { switch self { case .up: return 0; case .down: return 1; case .left: return 2; case .right: return 3 } }
    init?(code: UInt8) {
        switch code { case 0: self = .up; case 1: self = .down; case 2: self = .left; case 3: self = .right; default: return nil }
    }
}

enum OnlineCodec {
    private enum Tag: UInt8 { case hello = 1, start, input, state, end, ping, pong, away, forfeit, rematch, quit }

    static func encode(_ m: OnlineMessage) -> Data {
        var w = Writer()
        switch m {
        case let .hello(v, nonce, skin, map, owned):
            w.u8(Tag.hello.rawValue); w.u8(v); w.u32(nonce); w.str(skin); w.str(map)
            w.u8(UInt8(min(owned.count, 255))); owned.prefix(255).forEach { w.str($0) }
        case let .start(round, seed, map, hs, gs):
            w.u8(Tag.start.rawValue); w.u16(round); w.u64(seed); w.str(map); w.str(hs); w.str(gs)
        case let .input(round, tick, dir):
            w.u8(Tag.input.rawValue); w.u16(round); w.u32(tick); w.u8(dir.code)
        case let .state(s): w.u8(Tag.state.rawValue); w.state(s)
        case let .end(s): w.u8(Tag.end.rawValue); w.state(s)
        case let .ping(t): w.u8(Tag.ping.rawValue); w.u32(t)
        case let .pong(t): w.u8(Tag.pong.rawValue); w.u32(t)
        case let .away(a): w.u8(Tag.away.rawValue); w.u8(a ? 1 : 0)
        case .forfeit: w.u8(Tag.forfeit.rawValue)
        case let .rematch(r): w.u8(Tag.rematch.rawValue); w.u16(r)
        case .quit: w.u8(Tag.quit.rawValue)
        }
        return w.data
    }

    static func decode(_ d: Data) -> OnlineMessage? {
        var r = Reader(Array(d))
        guard let raw = r.u8(), let tag = Tag(rawValue: raw) else { return nil }
        let m: OnlineMessage?
        switch tag {
        case .hello:
            guard let v = r.u8(), let n = r.u32(), let s = r.str(), let map = r.str(), let c = r.u8() else { return nil }
            var owned: [String] = []
            for _ in 0..<c { guard let o = r.str() else { return nil }; owned.append(o) }
            m = .hello(version: v, nonce: n, skin: s, map: map, ownedMaps: owned)
        case .start:
            guard let round = r.u16(), let seed = r.u64(), let map = r.str(), let hs = r.str(), let gs = r.str() else { return nil }
            m = .start(round: round, seed: seed, map: map, hostSkin: hs, guestSkin: gs)
        case .input:
            guard let round = r.u16(), let t = r.u32(), let c = r.u8(), let dir = Direction(code: c) else { return nil }
            m = .input(round: round, tick: t, dir: dir)
        case .state: m = r.state().map { .state($0) }
        case .end: m = r.state().map { .end($0) }
        case .ping: m = r.u32().map { .ping($0) }
        case .pong: m = r.u32().map { .pong($0) }
        case .away: m = r.u8().map { .away($0 != 0) }
        case .forfeit: m = .forfeit
        case .rematch: m = r.u16().map { .rematch(round: $0) }
        case .quit: m = .quit
        }
        guard r.atEnd else { return nil }   // trailing junk = malformed
        return m
    }

    // Result: 0 none, 1 draw, 2/3 p1 by apples/opponentDied, 4/5 p2.
    fileprivate static func code(_ r: MatchResult?) -> UInt8 {
        switch r {
        case nil: return 0
        case .draw?: return 1
        case let .winner(p, reason)?: return UInt8(2 + p.rawValue * 2 + (reason == .apples ? 0 : 1))
        }
    }
    fileprivate static func result(_ c: UInt8) -> MatchResult?? {
        switch c {
        case 0: return .some(nil)
        case 1: return .some(.draw)
        case 2...5:
            let p: PlayerID = c < 4 ? .one : .two
            return .some(.winner(p, reason: (c - 2) % 2 == 0 ? .apples : .opponentDied))
        default: return nil
        }
    }

    private struct Writer {
        var data = Data()
        mutating func u8(_ v: UInt8) { data.append(v) }
        mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
        mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
        mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
        mutating func str(_ s: String) {
            let b = Array(s.utf8.prefix(255)); u8(UInt8(b.count)); data.append(contentsOf: b)
        }
        mutating func cell(_ c: GridCell) { u8(UInt8(clamping: c.x)); u8(UInt8(clamping: c.y)) }
        mutating func state(_ s: OnlineState) {
            u16(s.round); u32(s.tick); u8(OnlineCodec.code(s.result))
            if let a = s.apple { u8(1); cell(a) } else { u8(0) }
            u8(UInt8(s.snakes.count))
            for sn in s.snakes {
                u8(sn.direction.code); u8(UInt8(clamping: sn.apples)); u16(UInt16(clamping: sn.body.count))
                sn.body.forEach { cell($0) }
            }
        }
    }

    private struct Reader {
        let b: [UInt8]; var i = 0
        init(_ b: [UInt8]) { self.b = b }
        var atEnd: Bool { i == b.count }
        mutating func u8() -> UInt8? { guard i < b.count else { return nil }; defer { i += 1 }; return b[i] }
        mutating func uint(_ n: Int) -> UInt64? {
            guard i + n <= b.count else { return nil }
            var v: UInt64 = 0
            for k in 0..<n { v = v << 8 | UInt64(b[i + k]) }
            i += n; return v
        }
        mutating func u16() -> UInt16? { uint(2).map { UInt16($0) } }
        mutating func u32() -> UInt32? { uint(4).map { UInt32($0) } }
        mutating func u64() -> UInt64? { uint(8) }
        mutating func str() -> String? {
            guard let n = u8(), i + Int(n) <= b.count else { return nil }
            defer { i += Int(n) }
            return String(decoding: b[i..<i + Int(n)], as: UTF8.self)
        }
        mutating func cell() -> GridCell? {
            guard let x = u8(), let y = u8() else { return nil }; return GridCell(Int(x), Int(y))
        }
        mutating func state() -> OnlineState? {
            guard let round = u16(), let tick = u32(), let rc = u8(), let res = OnlineCodec.result(rc),
                  let hasApple = u8() else { return nil }
            var apple: GridCell?
            if hasApple == 1 { guard let a = cell() else { return nil }; apple = a }
            guard let n = u8(), n <= 2 else { return nil }
            var snakes: [VersusSnake] = []
            for _ in 0..<n {
                guard let dc = u8(), let dir = Direction(code: dc), let apples = u8(), let len = u16() else { return nil }
                var body: [GridCell] = []
                for _ in 0..<len { guard let c = cell() else { return nil }; body.append(c) }
                guard !body.isEmpty else { return nil }
                snakes.append(VersusSnake(body: body, direction: dir, apples: Int(apples)))
            }
            return OnlineState(round: round, tick: tick, snakes: snakes, apple: apple, result: res)
        }
    }
}

/// SplitMix64: tiny, fast, identical on every device for the same seed.
final class SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Deterministic pick (no reliance on stdlib's randomElement algorithm).
    func pick<T>(_ a: [T]) -> T? { a.isEmpty ? nil : a[Int(next() % UInt64(a.count))] }
}
