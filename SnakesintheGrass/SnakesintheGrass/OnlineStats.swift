//
//  OnlineStats.swift
//  slyme
//
//  Tracks online wins, losses, and draws across devices via iCloud KV store.
//  Records outcomes once per match to prevent double-counting.
//

import Foundation

@MainActor
final class OnlineStats: ObservableObject {
    static let shared = OnlineStats()
    
    private let store = NSUbiquitousKeyValueStore.default
    private enum Key {
        static let wins = "online.wins"
        static let losses = "online.losses"
        static let draws = "online.draws"
        static let recorded = "online.recorded"  // Set<matchID>
    }
    
    @Published private(set) var wins: Int = 0
    @Published private(set) var losses: Int = 0
    @Published private(set) var draws: Int = 0
    
    private var recordedMatches: Set<String> = []
    
    private init() {
        loadStats()
        // Listen for changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
    }
    
    private func loadStats() {
        wins = store.longLong(forKey: Key.wins).asInt
        losses = store.longLong(forKey: Key.losses).asInt
        draws = store.longLong(forKey: Key.draws).asInt
        
        if let data = store.data(forKey: Key.recorded),
           let set = try? JSONDecoder().decode(Set<String>.self, from: data) {
            recordedMatches = set
        }
    }
    
    @objc private func kvStoreChanged(_ notification: Notification) {
        Task { @MainActor in
            loadStats()
        }
    }
    
    /// Total matches played
    var totalMatches: Int { wins + losses + draws }
    
    /// Win rate as percentage (0-100)
    var winRate: Double {
        let total = totalMatches
        guard total > 0 else { return 0 }
        return (Double(wins) / Double(total)) * 100
    }
    
    /// Record a match outcome. Returns true if recorded, false if already counted.
    func recordMatch(id: String, outcome: MatchOutcome) -> Bool {
        guard !recordedMatches.contains(id) else {
            return false  // Already recorded
        }
        
        recordedMatches.insert(id)
        
        switch outcome {
        case .win:
            wins += 1
            store.set(Int64(wins), forKey: Key.wins)
        case .loss:
            losses += 1
            store.set(Int64(losses), forKey: Key.losses)
        case .draw:
            draws += 1
            store.set(Int64(draws), forKey: Key.draws)
        }
        
        // Persist recorded matches set
        if let data = try? JSONEncoder().encode(recordedMatches) {
            store.set(data, forKey: Key.recorded)
        }
        
        store.synchronize()
        return true
    }
    
    /// Reset all stats (for testing/debugging)
    func reset() {
        wins = 0
        losses = 0
        draws = 0
        recordedMatches.removeAll()
        
        store.set(Int64(0), forKey: Key.wins)
        store.set(Int64(0), forKey: Key.losses)
        store.set(Int64(0), forKey: Key.draws)
        store.removeObject(forKey: Key.recorded)
        store.synchronize()
    }
}

enum MatchOutcome {
    case win, loss, draw
}

private extension Int64 {
    var asInt: Int { Int(clamping: self) }
}
