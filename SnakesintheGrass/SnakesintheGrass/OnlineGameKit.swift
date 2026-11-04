//
//  OnlineGameKit.swift
//  slyme
//
//  Game Center glue for online versus: GKMatch transport, the standard
//  matchmaker UI (quick match + invite friends) and invite acceptance via
//  GKLocalPlayerListener. All game logic is in OnlineSession.
//

import GameKit
import SpriteKit
import UIKit

/// GKMatch as an OnlineTransport.
final class GameKitTransport: NSObject, OnlineTransport, GKMatchDelegate {
    let match: GKMatch
    var onReceive: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?

    init(match: GKMatch) {
        self.match = match
        super.init()
        match.delegate = self
    }

    var remotePlayer: GKPlayer? { match.players.first }

    func send(_ data: Data, reliable: Bool) {
        do { try match.sendData(toAllPlayers: data, with: reliable ? .reliable : .unreliable) }
        catch { print("online send failed: \(error.localizedDescription)") }
    }

    func disconnect() {
        match.delegate = nil
        match.disconnect()
    }

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        DispatchQueue.main.async { self.onReceive?(data) }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        if state == .disconnected { DispatchQueue.main.async { self.onDisconnect?() } }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        DispatchQueue.main.async { self.onDisconnect?() }
    }
}

/// Matchmaking + invites. Free for everyone: no purchase checks here.
final class OnlineMatchmaker: NSObject, GKMatchmakerViewControllerDelegate, GKLocalPlayerListener {
    static let shared = OnlineMatchmaker()
    private var listening = false

    /// Called by GameCenterManager after a successful sign-in.
    func registerListener() {
        guard !listening else { return }
        listening = true
        GKLocalPlayer.local.register(self)
    }

    var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }

    private var topViewController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }

    private var skView: SKView? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        func find(_ v: UIView?) -> SKView? {
            guard let v else { return nil }
            if let s = v as? SKView { return s }
            for c in v.subviews { if let s = find(c) { return s } }
            return nil
        }
        return find(scene?.keyWindow)
    }

    static func request(recipients: [GKPlayer]? = nil) -> GKMatchRequest {
        let r = GKMatchRequest()
        r.minPlayers = 2; r.maxPlayers = 2
        r.recipients = recipients
        r.inviteMessage = "slyme: one board, one apple. race me."
        return r
    }

    /// Standard UI: quick match (auto-match) and invite friends in one sheet.
    func presentMatchmaker() {
        guard isSignedIn, let vc = GKMatchmakerViewController(matchRequest: OnlineMatchmaker.request()) else { return }
        vc.matchmakerDelegate = self
        topViewController?.present(vc, animated: true)
        OnlineLobbyScene.active?.setStatus(.finding)
    }

    // MARK: GKMatchmakerViewControllerDelegate

    func matchmakerViewControllerWasCancelled(_ vc: GKMatchmakerViewController) {
        vc.dismiss(animated: true)
        OnlineLobbyScene.active?.setStatus(.ready)
    }

    func matchmakerViewController(_ vc: GKMatchmakerViewController, didFailWithError error: Error) {
        vc.dismiss(animated: true)
        OnlineLobbyScene.active?.setStatus(.failed(error.localizedDescription))
    }

    func matchmakerViewController(_ vc: GKMatchmakerViewController, didFind match: GKMatch) {
        vc.dismiss(animated: true)
        start(match)
    }

    // MARK: GKLocalPlayerListener (invites)

    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        guard let vc = GKMatchmakerViewController(invite: invite) else { return }
        vc.matchmakerDelegate = self
        topViewController?.present(vc, animated: true)
    }

    func player(_ player: GKPlayer, didRequestMatchWithRecipients recipients: [GKPlayer]) {
        guard let vc = GKMatchmakerViewController(matchRequest: OnlineMatchmaker.request(recipients: recipients)) else { return }
        vc.matchmakerDelegate = self
        topViewController?.present(vc, animated: true)
    }

    // MARK: Start

    private func start(_ match: GKMatch) {
        guard let view = skView else { match.disconnect(); return }
        let transport = GameKitTransport(match: match)
        let store = EntitlementStore.shared
        let owned = MapCatalog.all.filter { store.isUnlocked(mapID: $0.id) }.map(\.id)
        let session = OnlineSession(transport: transport, localID: GKLocalPlayer.local.gamePlayerID,
                                    skin: store.selectedSkin.id, map: store.selectedMap.id, ownedMaps: owned)
        if let remote = transport.remotePlayer { session.setRemoteID(remote.gamePlayerID) }
        let scene = OnlineMatchScene(size: view.bounds.size, session: session,
                                     opponentName: transport.remotePlayer?.displayName ?? "them")
        scene.scaleMode = .resizeFill
        view.presentScene(scene, transition: .fade(withDuration: 0.4))
    }
}
