# Local two-player (versus)

Two snakes, one board, one apple. Code: `TwoPlayerRules.swift` (pure rules, unit-tested in
`slymeTests/TwoPlayerRulesTests.swift`), `TwoPlayerScene.swift` (match), `TwoPlayerSetupScene.swift` (pre-match).
Main menu → **2 players**.

## Rules as implemented
- Both snakes move on the **same tick**, simultaneously.
- **First to 10 apples wins** (`applesToWin`). Each apple grows the snake that ate it.
- Hitting a **wall** (box/yard maps only; other maps wrap), an **obstacle**, **your own body**, or the
  **other snake's body** loses immediately; the survivor wins.
- Tails move out on the same tick, so entering a cell a tail is leaving is safe (own or opponent's).
- **Head-on** (both heads into the same cell, or heads swapping places) kills both. Both snakes
  dying on the same tick: more apples wins, **equal apples is a draw**.
- Both heads reaching the apple on the same tick counts as head-on: nobody scores.
- Turning back into your own neck is ignored.
- New apples spawn only on free cells (not on either snake or an obstacle).
- **Speed-up:** the shared tick starts at 0.12 s and drops 0.01 s for every 3 apples eaten by
  both players combined, down to a 0.06 s floor (level 1 → 7). Deterministic: it depends only on
  the combined apple count. The HUD shows a faint `spd N` next to P1's score (flat) or under the
  pause button (folded).
- Versus scores never go to the Game Center leaderboard. Single-player is unchanged.

## Controls
- Flat screen: P1 swipes anywhere on the bottom half, P2 on the top half (multi-touch, both at once).
- Swipes are always in **screen directions**, also for P2 when "p2 faces p1" is on; that toggle only
  rotates P2's score label 180° so it reads from across the table.
- Pause button sits in P1's HUD strip (flat) or on the line between the pads (folded).

## Pre-match
Each player picks from their **unlocked** skins (locked ones are dimmed), the map cycles through
unlocked maps, and the "p2 faces p1" toggle. Picks are remembered.

## TwoPlayerConfig
| constant | default | meaning |
|---|---|---|
| `applesToWin` | 10 | apples to win |
| `tickInterval` | 0.12 | starting seconds per move |
| `applesPerSpeedUp` | 3 | combined apples per speed level |
| `speedUpStep` | 0.01 | seconds removed per level |
| `minTickInterval` | 0.06 | fastest tick |
| `startLength` | 3 | starting length |
| `growOnApple` | true | apples grow the snake |
| `defaultFacing` | true | P2 label rotated by default |
| `swipeThreshold` | 22 pt | finger travel before a swipe counts |

## Duo fold layout
- **Flat:** the board fills the screen between two HUD strips (P2 on top, P1 at the bottom).
- **Partly folded:** the board stays whole on one side of the hinge (never split across the fold);
  the other side becomes two thumb pads, one per player, each showing that player's score.
  Rationale: a board split across a hinge is hard to read, and the pads give both players a
  dedicated, comfortable swipe area. Not yet verified on a physically folded simulator.

## Debug launch args (DEBUG builds only)
`-slymeStart twoplayer` (setup screen), `-slymeStart twoplayermatch` (straight into a match),
`-slymeTwoDemo` (seeds a mid-match board for screenshots).

## Ideas for later
- **Online** via GameKit real-time matches (`GKMatchmaker` + `GKMatch`): one device is host and runs
  `VersusMatch.step()`, sending turns/state each tick; invites and matchmaking come free with Game Center.
- **Survival / shrinking arena:** walls close in every N seconds; last snake alive wins.
- **Co-op:** shared apple score against a timer or a hazard.
- **Ghost races:** race a recorded replay of a friend's best run (replays are tiny: seed + turn list).
- Best-of-3 sets, power-up apples, a "versus" pack in the store.
