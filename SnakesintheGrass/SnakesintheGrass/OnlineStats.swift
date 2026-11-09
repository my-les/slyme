//
//  OnlineStats.swift
//  slyme
//
//  Tracks online wins, losses, and draws locally (UserDefaults).
//  Game Center leaderboard provides cross-device wins.
//

import Foundation

@MainActor
final class OnlineStats: ObservableObject {
    static let shared = OnlineStats()
    
    private let defaults = UserDefaults.standard
    private enum Key {
        static let wins = "online.wins"
        static let losses = "online.losses"
        static let draws = "online.draws"
    }
    
    @Published private(set) var wins: Int
    @Published private(set) var losses: Int
    @Published private(set) var draws: Int
    
    private init() {
        wins = defaults.integer(forKey: Key.wins)
        losses = defaults.integer(forKey: Key.losses)
        draws = defaults.integer(forKey: Key.draws)
    }
    
    /// Total matches played
    var totalMatches: Int { wins + losses + draws }
    
    /// Win rate as percentage (0-100)
    var winRate: Double {
        let total = totalMatches
        guard total > 0 else { return 0 }
        return (Double(wins) / Double(total)) * 100
    }
    
    /// Record a match outcome (called once per scene via matchRecorded flag)
    func recordMatch(outcome: MatchOutcome) {
        switch outcome {
        case .win:
            wins += 1
            defaults.set(wins, forKey: Key.wins)
        case .loss:
            losses += 1
            defaults.set(losses, forKey: Key.losses)
        case .draw:
            draws += 1
            defaults.set(draws, forKey: Key.draws)
        }
    }
    
    /// Reset all stats (for testing/debugging)
    func reset() {
        wins = 0
        losses = 0
        draws = 0
        
        defaults.set(0, forKey: Key.wins)
        defaults.set(0, forKey: Key.losses)
        defaults.set(0, forKey: Key.draws)
    }
}

enum MatchOutcome {
    case win, loss, draw
}
