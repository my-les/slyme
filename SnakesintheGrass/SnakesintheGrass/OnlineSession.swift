//
//  OnlineSession.swift
//  slyme
//
//  Online versus state machine. Pure Foundation: talks to the network only
//  through `OnlineTransport`, so two sessions run in-process in tests over a
//  `LoopbackLink`. Host-authoritative: the host runs VersusMatch and sends a
//  compact snapshot every tick; the guest sends direction inputs and renders
//  snapshots. See docs/ONLINE_PLAY.md.
//

import Foundation

protocol OnlineTransport: AnyObject {
    var onReceive: ((Data) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func send(_ data: Data, reliable: Bool)
    func disconnect()
}

enum OnlineRole: Equatable { case undecided, host, guest }

enum OnlineEnd: Equatable {
    case match(MatchResult)
    case opponentLeft          // quit or dropped mid-match: you win
    case opponentForfeited     // away past the grace period: you win
    case youForfeited
    case versionMismatch
}

final class OnlineSession {
    // Inputs
    let transport: OnlineTransport
    let localSkin: String
    let localMap: String
    let ownedMaps: [String]
    let localID: String               // tie-break for host election
    private let nonce: UInt32

    // State
    private(set) var role: OnlineRole = .undecided
    private(set) var phase: Phase = .handshake
    enum Phase: Equatable { case handshake, countdown, playing, ended }
    private(set) var round: UInt16 = 0
    private(set) var mapID: String = MapCatalog.defaultID
    private(set) var hostSkin = SkinCatalog.defaultID
    private(set) var guestSkin = SkinCatalog.defaultID
    private(set) var state: OnlineState?          // latest snapshot (both sides render this)
    private(set) var end: OnlineEnd?
    private(set) var rtt: TimeInterval?
    private(set) var opponentAway = false
    private(set) var localAway = false
    private(set) var opponentGone = false
    private(set) var rematchLocal = false
    private(set) var rematchRemote = false
    private var remoteHello: (nonce: UInt32, skin: String, map: String, owned: [String])?

    /// Host only: the authoritative match.
    private(set) var match: VersusMatch?
    private var tick: UInt32 = 0
    private var nextTickAt: TimeInterval?
    private var lastHello: TimeInterval = -.infinity
    private var lastPing: TimeInterval = -.infinity
    private var opponentAwaySince: TimeInterval?
    private var now: TimeInterval = 0
    private var pendingRemoteID: String?

    // Callbacks (main thread in the app)
    var onStart: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onEnd: ((OnlineEnd) -> Void)?
    var onStatus: (() -> Void)?     // away / rematch / latency / gone changed

    /// Which snake is mine. Host is always P1.
    var me: PlayerID { role == .guest ? .two : .one }
    var them: PlayerID { me == .one ? .two : .one }
    var mySkin: String { me == .one ? hostSkin : guestSkin }
    var theirSkin: String { me == .one ? guestSkin : hostSkin }

    init(transport: OnlineTransport, localID: String, skin: String, map: String, ownedMaps: [String],
         nonce: UInt32 = UInt32.random(in: 0...UInt32.max)) {
        self.transport = transport; self.localID = localID
        self.localSkin = skin; self.localMap = map; self.ownedMaps = ownedMaps; self.nonce = nonce
        transport.onReceive = { [weak self] d in self?.receive(d) }
        transport.onDisconnect = { [weak self] in self?.remoteDisconnected() }
    }

    /// Tell the remote player's id once known (GKMatch players), for the tie-break.
    func setRemoteID(_ id: String) { pendingRemoteID = id }

    func begin(now t: TimeInterval = 0) { now = t; sendHello() }

    // MARK: Outgoing

    private func send(_ m: OnlineMessage) {
        guard !opponentGone else { return }
        transport.send(OnlineCodec.encode(m), reliable: m.reliable)
    }
    private func sendHello() {
        lastHello = now
        send(.hello(version: OnlineConfig.protocolVersion, nonce: nonce, skin: localSkin, map: localMap, ownedMaps: ownedMaps))
    }

    // MARK: Driving (call from SKScene.update; tests call directly)

    /// Advance clocks: hello retries, pings, away grace, and (host) ticks.
    func advance(now t: TimeInterval) {
        now = t
        if phase == .handshake && role != .host && t - lastHello >= OnlineConfig.helloInterval { sendHello() }
        if phase != .handshake && t - lastPing >= OnlineConfig.pingInterval {
            lastPing = t; send(.ping(UInt32(truncatingIfNeeded: Int(t * 1000))))
        }
        if let since = opponentAwaySince, phase == .playing || phase == .countdown,
           t - since >= OnlineConfig.awayGrace {
            send(.forfeit); finish(.opponentForfeited)
            return
        }
        guard role == .host, phase == .countdown || phase == .playing, !opponentAway, !localAway,
              match != nil else { return }
        if nextTickAt == nil { nextTickAt = t + OnlineConfig.startDelay }
        while let n = nextTickAt, t >= n, phase != .ended {
            hostStep()
            nextTickAt = n + (match?.tickInterval ?? TwoPlayerConfig.tickInterval)
            if t - (nextTickAt ?? t) > 0.5 { nextTickAt = t }   // don't fast-forward after a hitch
        }
    }

    /// Host: one authoritative tick, broadcast, maybe end.
    func hostStep() {
        guard role == .host, var m = match, m.result == nil else { return }
        phase = .playing
        m.step(); match = m; tick &+= 1
        let s = OnlineState(round: round, tick: tick, match: m)
        state = s
        if let r = m.result {
            send(.end(s)); onUpdate?(); finish(.match(r))
        } else {
            send(.state(s)); onUpdate?()
        }
    }

    /// Local swipe.
    func localTurn(_ d: Direction) {
        guard phase == .playing || phase == .countdown else { return }
        if role == .host { match?.turn(.one, d) }
        else if role == .guest { send(.input(round: round, tick: state?.tick ?? 0, dir: d)) }
    }

    func setLocalAway(_ away: Bool, now t: TimeInterval) {
        guard away != localAway else { return }
        now = t; localAway = away
        if !away { nextTickAt = nil }
        send(.away(away))
    }

    func requestRematch() {
        guard phase == .ended, !opponentGone, !rematchLocal else { return }
        if case .youForfeited? = end { } // allowed
        rematchLocal = true
        send(.rematch(round: round))
        onStatus?()
        maybeStartRematch()
    }

    func quit() {
        send(.quit)
        opponentGone = true
        if phase != .ended { phase = .ended }
        transport.disconnect()
    }

    // MARK: Incoming

    func receive(_ data: Data) {
        guard let m = OnlineCodec.decode(data) else { return }
        switch m {
        case let .hello(v, n, skin, map, owned):
            guard v == OnlineConfig.protocolVersion else {
                if phase != .ended { finish(.versionMismatch) }; return
            }
            if remoteHello == nil { remoteHello = (n, skin, map, owned) }
            if role == .undecided { electRole() }
            if role == .host {
                if phase == .handshake { startRound(seed: UInt64.random(in: 0...UInt64.max)) }
                else if phase != .ended { resendStart() }   // guest missed it; harmless otherwise
            }
        case let .start(r, seed, map, hs, gs):
            guard role != .host else { return }
            if role == .undecided { role = .guest }
            guard r > round || phase == .handshake else { return }
            applyStart(round: r, seed: seed, map: map, hostSkin: hs, guestSkin: gs)
        case let .input(r, _, dir):
            guard role == .host, r == round, phase == .countdown || phase == .playing else { return }
            match?.turn(.two, dir)
        case let .state(s):
            guard role == .guest, s.round == round, phase != .ended, s.tick > (state?.tick ?? 0) else { return }
            state = s; phase = .playing; onUpdate?()
        case let .end(s):
            guard role == .guest, s.round == round, phase != .ended else { return }
            state = s; onUpdate?()
            finish(s.result.map { .match($0) } ?? .match(.draw))
        case let .ping(t): send(.pong(t))
        case let .pong(t):
            let ms = Int(UInt32(truncatingIfNeeded: Int(now * 1000)) &- t)
            rtt = Double(ms) / 1000; onStatus?()
        case let .away(a):
            opponentAway = a
            opponentAwaySince = a ? now : nil
            if !a { nextTickAt = nil }
            onStatus?()
        case .forfeit:
            if phase != .ended { finish(.youForfeited) }
        case let .rematch(r):
            guard r == round, phase == .ended else { return }
            rematchRemote = true; onStatus?()
            maybeStartRematch()
        case .quit:
            remoteDisconnected()
        }
    }

    private func remoteDisconnected() {
        guard !opponentGone else { return }
        opponentGone = true
        if phase != .ended { finish(.opponentLeft) } else { onStatus?() }
    }

    // MARK: Rounds

    /// Higher nonce hosts; equal nonce falls back to the lower player id.
    private func electRole() {
        guard let h = remoteHello else { return }
        if h.nonce != nonce { role = nonce > h.nonce ? .host : .guest }
        else { role = localID < (pendingRemoteID ?? "~") ? .host : .guest }
    }

    /// Host's map if the guest owns it too, else the default free map.
    static func chooseMap(hostMap: String, guestOwned: [String]) -> String {
        guard MapCatalog.map(id: hostMap) != nil, guestOwned.contains(hostMap) else { return MapCatalog.defaultID }
        return hostMap
    }

    private var startMessage: OnlineMessage?
    private func resendStart() { if let s = startMessage { send(s) } }

    private func startRound(seed: UInt64) {
        guard let h = remoteHello else { return }
        let r = round &+ 1
        let map = phase == .handshake ? OnlineSession.chooseMap(hostMap: localMap, guestOwned: h.owned) : mapID
        let msg = OnlineMessage.start(round: r, seed: seed, map: map, hostSkin: localSkin, guestSkin: h.skin)
        startMessage = msg
        send(msg)
        applyStart(round: r, seed: seed, map: map, hostSkin: localSkin, guestSkin: h.skin)
    }

    private func applyStart(round r: UInt16, seed: UInt64, map: String, hostSkin hs: String, guestSkin gs: String) {
        round = r; mapID = MapCatalog.map(id: map) != nil ? map : MapCatalog.defaultID
        hostSkin = SkinCatalog.skin(id: hs) != nil ? hs : SkinCatalog.defaultID
        guestSkin = SkinCatalog.skin(id: gs) != nil ? gs : SkinCatalog.defaultID
        let board = VersusBoard(map: MapCatalog.map(id: mapID) ?? MapCatalog.all[0])
        let (a, b) = VersusMatch.startSnakes(board: board)
        let rng = SeededRNG(seed: seed)
        let m = VersusMatch(board: board, p1: a, p2: b, pickApple: { rng.pick($0) })
        tick = 0; nextTickAt = nil
        end = nil; rematchLocal = false; rematchRemote = false
        state = OnlineState(round: r, tick: 0, match: m)
        match = role == .host ? m : nil
        phase = .countdown
        onStart?(); onUpdate?()
    }

    private func maybeStartRematch() {
        guard rematchLocal, rematchRemote, role == .host, phase == .ended else { return }
        startRound(seed: UInt64.random(in: 0...UInt64.max))
    }

    private func finish(_ e: OnlineEnd) {
        guard phase != .ended else { return }
        phase = .ended; end = e; opponentAwaySince = nil
        onEnd?(e)
    }
}

// MARK: - In-process transport (tests + DEBUG demo)

/// Two connected endpoints. Messages queue until `pump()` (tests) or, with
/// `autoDeliver`, the next main-queue turn (DEBUG demo). `dropUnreliable`
/// simulates packet loss for unreliable sends.
final class LoopbackLink {
    final class End: OnlineTransport {
        weak var link: LoopbackLink?
        let index: Int
        var onReceive: ((Data) -> Void)?
        var onDisconnect: (() -> Void)?
        init(index: Int) { self.index = index }
        func send(_ data: Data, reliable: Bool) { link?.enqueue(from: index, data, reliable: reliable) }
        func disconnect() { link?.cut(from: index) }
    }
    let a = End(index: 0), b = End(index: 1)
    var autoDeliver = false
    var dropUnreliable = false
    private(set) var connected = true
    private var queue: [(to: Int, data: Data)] = []
    private(set) var sentCount = 0

    init() { a.link = self; b.link = self }

    private func end(_ i: Int) -> End { i == 0 ? a : b }

    fileprivate func enqueue(from i: Int, _ d: Data, reliable: Bool) {
        guard connected else { return }
        sentCount += 1
        if !reliable && dropUnreliable { return }
        queue.append((1 - i, d))
        if autoDeliver { DispatchQueue.main.async { [weak self] in self?.pump() } }
    }
    fileprivate func cut(from i: Int) {
        guard connected else { return }
        connected = false; queue.removeAll()
        let other = end(1 - i)
        if autoDeliver { DispatchQueue.main.async { other.onDisconnect?() } } else { other.onDisconnect?() }
    }
    /// Deliver everything queued, including messages sent while delivering.
    func pump() {
        var guardCount = 0
        while !queue.isEmpty && guardCount < 10_000 {
            let (to, d) = queue.removeFirst(); guardCount += 1
            end(to).onReceive?(d)
        }
    }
}
