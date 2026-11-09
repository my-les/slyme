import SwiftUI
import GameKit

/// Game Center wrapper. Manages single-player best score and online wins leaderboards.
final class GameCenterManager: NSObject, GKGameCenterControllerDelegate, ObservableObject {
    static let shared = GameCenterManager()

    /// Must match the leaderboard IDs in App Store Connect.
    let bestScoreLeaderboardID = "555"
    let onlineWinsLeaderboardID = "com.ysdwysd.online.wins"

    private let localBestKey = "localBestScore"

    /// Best score finished on this device, kept so we can retry/skip redundant submits.
    var localBest: Int { UserDefaults.standard.integer(forKey: localBestKey) }

    private var topViewController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    func authenticatePlayer() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let viewController = viewController {
                self?.topViewController?.present(viewController, animated: true)
            } else if GKLocalPlayer.local.isAuthenticated {
                // Online versus: listen for invites, and unblock the lobby.
                OnlineMatchmaker.shared.registerListener()
                OnlineLobbyScene.active?.setStatus(.ready)
                // Push any score earned while signed out.
                self?.submitScore(self?.localBest ?? 0)
            } else if let error = error {
                OnlineLobbyScene.active?.setStatus(.signedOut)
                print("Game Center auth error: \(error.localizedDescription)")
            }
        }
    }

    /// Submit a finished run. Game Center keeps only the player's best (set the
    /// leaderboard to "Best Score" in App Store Connect).
    func submitScore(_ score: Int) {
        guard score > 0 else { return }
        if score > localBest {
            UserDefaults.standard.set(score, forKey: localBestKey)
        }
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [bestScoreLeaderboardID]) { error in
            if let error = error {
                print("Error submitting score: \(error.localizedDescription)")
            }
        }
    }

    /// Opens the single best-score leaderboard directly.
    func showLeaderboard() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let vc = GKGameCenterViewController(leaderboardID: bestScoreLeaderboardID,
                                            playerScope: .global,
                                            timeScope: .allTime)
        vc.gameCenterDelegate = self
        topViewController?.present(vc, animated: true)
    }
    
    /// Opens the online wins leaderboard.
    func showOnlineLeaderboard() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let vc = GKGameCenterViewController(leaderboardID: onlineWinsLeaderboardID,
                                            playerScope: .global,
                                            timeScope: .allTime)
        vc.gameCenterDelegate = self
        topViewController?.present(vc, animated: true)
    }
    
    /// Submit online wins to Game Center. Called after recording each match.
    func submitOnlineWins(_ wins: Int) async {
        guard wins > 0, GKLocalPlayer.local.isAuthenticated else { return }
        
        do {
            try await GKLeaderboard.submitScore(
                wins,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [onlineWinsLeaderboardID]
            )
        } catch {
            print("Error submitting online wins: \(error.localizedDescription)")
        }
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
