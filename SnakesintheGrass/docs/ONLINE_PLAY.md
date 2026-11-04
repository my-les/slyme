# Online versus (Game Center, real-time)

Two players, each on their own device, one shared board, one apple. Free for everyone (no StoreKit
gating). Same rules as local two-player (`TwoPlayerRules.swift`, `docs/TWO_PLAYER.md`): first to 10
apples, walls/obstacles/bodies kill, head-on with equal apples is a draw, shared speed-up.
Local same-device "2 players" is unchanged and still on the menu. Online results never go to the
single-player "best score" leaderboard.

## Code
| File | Role |
|---|---|
| `OnlineProtocol.swift` | Messages, compact binary codec, `SeededRNG` (SplitMix64), `OnlineConfig` |
| `OnlineSession.swift` | State machine (handshake, rounds, rematch, away/forfeit, ping). Pure Foundation. `OnlineTransport` protocol + `LoopbackLink` in-process transport |
| `OnlineGameKit.swift` | `GameKitTransport` (GKMatch), `OnlineMatchmaker` (GKMatchmakerViewController, GKLocalPlayerListener for invites) |
| `OnlineLobbyScene.swift` | "online" screen: sign-in check, your skin/map, "find match" |
| `OnlineMatchScene.swift` | Renders snapshots, swipes → session, overlays (connecting, away, result, rematch) |
| `slymeTests/OnlineTests.swift` | Codec + two sessions over `LoopbackLink`; no Game Center needed |

## Design: authoritative host, snapshots every tick
- **Host election:** both send `hello` (protocol version, random nonce, skin, selected map, owned maps).
  Higher nonce hosts; equal nonce → lower `gamePlayerID`. Host is always P1.
- **Host** runs the real `VersusMatch` with a `SeededRNG` (seed sent in `start`), ticks at
  `TwoPlayerConfig.tickInterval(totalApples:)` (same speed-up), applies the guest's inputs on arrival,
  and sends the full state (~40 bytes: tick, both bodies, directions, apples, apple, result) every tick.
- **Guest** sends `input(round, tick, dir)` on swipe and draws the newest snapshot (older/duplicate ticks ignored).
- **Why not lockstep:** lockstep needs both sides to wait for each other's input every tick, an input
  delay, and desync detection/recovery. Snakes are tiny, so sending the whole state each tick is cheap
  and self-healing: a lost packet is fixed by the next one, and desync is impossible. Cost: the guest
  sees its own turns ~1 round-trip late (fine at typical 30–80 ms vs a 60–120 ms tick). Host has a
  small latency advantage; documented trade-off.
- **Delivery:** `start`, `input`, `end`, `away`, `forfeit`, `rematch`, `quit`, `hello` are `.reliable`;
  per-tick `state` and `ping/pong` are `.unreliable`.
- **Skins:** each player keeps the skin they picked; the opponent's arrives in `hello`/`start`. Unknown
  skin ids (newer app version) fall back to `og`.
- **Map:** host's selected map if the guest owns it, else `void`.
- **Disconnect / quit:** remaining player wins ("left the match"). `menu`/`leave` sends `quit`.
- **Backgrounding:** the app sends `away(true)`; the host pauses the simulation; the other player sees
  "left the app, forfeits in 10s". After `OnlineConfig.awayGrace` (10 s) they win and the away player
  gets "forfeit." when they return. Coming back in time resumes after a 1 s beat.
- **Latency:** ping every second; HUD shows round-trip ms (green < 80, yellow < 160, red).
- **Rematch:** both tap rematch → host starts round N+1 with a new seed, same map.
- **Version check:** `OnlineConfig.protocolVersion` mismatch ends with "update slyme on both devices".

## What you need to do to test for real
Nothing extra in App Store Connect is needed for GKMatch real-time play beyond Game Center being
enabled for the app (it is: leaderboard `555` is live, entitlement `com.apple.developer.game-center`
is on). No new entitlement, no multiplayer setting, no Game Center "matchmaking rules" are required.
1. Two devices (or one device + one simulator), each signed in to a **different** Game Center
   account (Settings › Game Center; sandbox accounts from App Store Connect › Users and Access ›
   Sandbox work for dev builds).
2. Install the same build on both (Xcode run, or TestFlight).
3. Both: menu › online › find match › "Play Now" (quick match) at about the same time. Or one taps
   "Invite Friends" and picks the other account (they must be Game Center friends); the invitee
   accepts the notification, which opens slyme into the match.
4. Check: both see own skin, apple positions match, swipes on both work, quit/background/rematch.
Optional: "Supports Multiplayer" / "Game Center" capability flags on the App Store listing are
cosmetic. If you later want custom matchmaking rules or cross-version play gates, add App Store
Connect matchmaking rule sets then.

## DEBUG helpers
- `-slymeStart online` lobby, `-slymeStart onlinefinding` lobby in "finding" state,
  `-slymeStart onlinedemo` full match vs a bot over `LoopbackLink` (both snakes on autopilot);
  add `-slymeFreeze` to freeze at tick 28 for screenshots.

## Not done / ideas
- No client-side prediction for the guest's own head; add if guests feel lag.
- No board flip for the guest (guest starts top-right). Could rotate the board 180° and remap swipes.
- Ranked/leaderboard for online wins, Game Center achievements, spectating, best-of-3.
