# Ludo — Cross-Platform Board Game Design

A traditional Ludo board game playable on **Android, iOS, Web, Windows, and Linux**, with
local and online multiplayer, custom rules, and an offline-first experience (no login
required unless playing online).

---

## 1. Goals & Requirements

| # | Requirement | Approach |
|---|-------------|----------|
| 1 | Runs on Android, iOS, Web, Windows, Linux | Single **Flutter** codebase (one UI, five targets) |
| 2 | Local player (vs AI), local multiplayer, online with random people, online with friends | Game-mode system on top of one shared game engine |
| 3 | Custom rules | Data-driven **Rule Config** (JSON) interpreted by the engine; rule presets + rule builder UI + shareable rule codes |
| 4 | Online or offline; login only for online play | Offline-first design; anonymous **guest identity** by default, account only when going online |
| 5 | Design sketch | This document + `docs/` mockups |

---

## 2. Technology Choices

### Client: Flutter (Dart)

- **One codebase → all 5 platforms.** Flutter ships first-class support for Android, iOS,
  Web, Windows, and Linux.
- Ludo is a 2D board game — Flutter's `CustomPainter`/widget system is enough; the
  [Flame](https://flame-engine.org) engine is an optional add-on for dice/token animations
  and particle effects.
- State management: **Riverpod** (simple, testable, works well with an immutable game state).

*Alternatives considered:* Godot (great for games, weaker web/app-store ergonomics for a
UI-heavy app), React Native (no good Linux/Windows story), Unity (heavyweight for a 2D
board game, large web builds).

### Shared Game Engine: pure Dart package

The heart of the project is `packages/ludo_engine` — a **pure Dart package with zero
Flutter dependencies** containing all the rules:

- Board model, token positions, move generation, captures, safe squares, win detection.
- Deterministic: `nextState = engine.apply(state, action, seed)` — same inputs always give
  the same output. This makes it usable **offline on the client** and **authoritatively on
  the server** (the server runs the same package compiled with `dart compile`).
- Fully unit-tested; no rendering, no networking, no I/O.

### Server: Dart (or Nakama) — authoritative online play

Two viable paths; recommendation first:

- **Recommended: Nakama** (open-source game server, self-hostable, free):
  gives matchmaking, friends, parties, auth (email/device/social), realtime match relay,
  and leaderboards out of the box. Game logic runs as a server-side match handler that
  calls into our rules (ported logic or via the authoritative-input model below).
- *Alternative:* a small custom **Dart server** (shelf + web_sockets) reusing
  `ludo_engine` directly — less to learn, more to build (matchmaking, presence, scaling).

Either way the model is **server-authoritative**: clients send *intents* ("roll dice",
"move token 2"), the server validates against the rule config and broadcasts the resulting
state. Dice are rolled server-side (online) or from a local RNG (offline).

### Storage

- **Client:** local save via `drift`/`sqlite` or `shared_preferences` — in-progress games,
  settings, custom rule sets, guest profile. Nothing requires a network.
- **Server:** Postgres (Nakama's default) — accounts, friends, match history, shared rule
  sets.

---

## 3. Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                        Flutter App (one codebase)              │
│  ┌──────────┐ ┌───────────┐ ┌──────────────┐ ┌──────────────┐  │
│  │  UI /    │ │  Screens  │ │ Rule Builder │ │  Settings /  │  │
│  │  Board   │ │  & Menus  │ │      UI      │ │   Profile    │  │
│  └────┬─────┘ └─────┬─────┘ └──────┬───────┘ └──────┬───────┘  │
│       └─────────────┴──────┬───────┴────────────────┘          │
│                    ┌───────▼────────┐                          │
│                    │  Game Session   │  ← one interface,       │
│                    │   Controller    │    many drivers         │
│                    └───────┬────────┘                          │
│        ┌───────────────────┼───────────────────┐               │
│  ┌─────▼─────┐      ┌──────▼──────┐     ┌──────▼──────┐        │
│  │  Local    │      │  Local      │     │  Online     │        │
│  │  vs AI    │      │  Pass&Play  │     │  (WebSocket)│        │
│  └─────┬─────┘      └──────┬──────┘     └──────┬──────┘        │
│        └──────────┬────────┘                   │               │
│           ┌───────▼────────┐                   │               │
│           │  ludo_engine   │ (pure Dart)       │               │
│           └────────────────┘                   │               │
└────────────────────────────────────────────────┼───────────────┘
                                                 │ WSS
                                   ┌─────────────▼─────────────┐
                                   │   Game Server (Nakama)     │
                                   │  auth · matchmaking ·      │
                                   │  friends · match relay     │
                                   │  ┌──────────────────────┐  │
                                   │  │ ludo_engine (same    │  │
                                   │  │ rules, authoritative)│  │
                                   │  └──────────────────────┘  │
                                   │        Postgres            │
                                   └───────────────────────────┘
```

Key idea: **all four game modes drive the same `GameSessionController` interface**, so the
board UI doesn't know or care whether the opponent is an AI, a person on the same device,
or a remote player.

### Repository layout (mono-repo)

```
ludo/
├── app/                    # Flutter application (UI, screens, platform glue)
├── packages/
│   ├── ludo_engine/        # Pure Dart rules engine (no Flutter)
│   └── ludo_protocol/      # Shared client<->server message & rule-config models
├── server/                 # Nakama modules / match handler (or Dart server)
├── docs/                   # Design docs, mockups
└── DESIGN.md
```

---

## 4. Game Modes

| Mode | Players | Network | Login | Dice | Notes |
|------|---------|---------|-------|------|-------|
| **Local vs AI** | 1 human + 1–3 AI | Offline | No | Local RNG | 3 AI difficulty levels |
| **Local multiplayer (pass & play)** | 2–4 humans, one device | Offline | No | Local RNG | Turn hand-off screen between players |
| **Online — random people** | 2–4 | Online | Yes (guest OK) | Server RNG | Matchmaking by player count + rule preset |
| **Online — friends** | 2–4 | Online | Yes (guest OK) | Server RNG | Private room with a 6-char **room code** / share link; friends list for regulars |

Online details:

- **Matchmaking (random):** queue keyed by `(playerCount, rulePresetHash)` so everyone in
  a match has agreed to the same rules. Fill empty seats with AI after a timeout (optional
  setting).
- **Friends:** friend list + invites via Nakama; a room can also be joined by anyone with
  the room code, no friendship required (great for "share link on WhatsApp" flows).
- **Disconnects:** 60s grace to reconnect (state is server-side, so rejoin is trivial);
  after that the seat is taken over by AI or skipped, per room setting.
- **Anti-cheat:** server-authoritative state + server-side dice → clients can't lie.

---

## 5. Rules Engine & Custom Rules

### Standard (default) rules

- 4 players × 4 tokens; roll 6 to leave the yard; 6 grants an extra roll; three 6s in a
  row forfeits the turn; landing on an opponent captures (sends home) unless on a safe
  (star) square; exact roll needed to enter home; first to bring all 4 tokens home wins.

### Custom rules = a data object, not code

Every variant is expressed as a `RuleConfig` the engine interprets:

```jsonc
{
  "id": "quick-family",
  "name": "Quick Family Game",
  "tokensPerPlayer": 2,          // 1..4
  "entryRoll": 6,                 // roll needed to leave yard, or "any"
  "extraRollOnSix": true,
  "tripleSixForfeits": true,
  "captureSendsHome": true,
  "captureGrantsExtraRoll": false,
  "safeSquares": "stars",        // "stars" | "none" | "starts+stars"
  "blockades": true,              // two own tokens block a square
  "exactHomeEntry": true,
  "mustCaptureToWin": false,     // popular Indian variant: need ≥1 capture before finishing
  "turnTimerSeconds": 30,         // 0 = no timer (offline default)
  "diceCount": 1,                 // 1 or 2 dice variants
  "startWithOneOut": false        // begin with one token already on the track
}
```

- **Presets:** Classic, Quick (2 tokens, any-roll entry), Aggressive (capture grants extra
  roll, must-capture-to-win), No-Mercy (no safe squares).
- **Rule Builder UI:** a form of toggles/sliders that produces a `RuleConfig`; live
  summary text ("Roll any number to start · 2 tokens · no safe squares").
- **Sharing:** a rule set serializes to a short **rule code** (base64 of the config) that
  friends can paste, and online rooms embed it so the server enforces identical rules.
- **Validation:** the engine rejects contradictory configs and every `RuleConfig` field is
  covered by engine unit tests, so a custom game can never reach an illegal state.

---

## 6. Offline / Online & Identity

```
first launch ──► play immediately (guest, no login)
                    │
                    ├── Local vs AI / pass & play ──► never needs network or account
                    │
                    └── taps "Online" ──► guest account auto-created (device ID)
                                │
                                └── optional upgrade: email / Google / Apple sign-in
                                    (keeps stats & friends across devices)
```

- **Offline-first:** the app fully works with no network. Games autosave locally and
  resume after app restart.
- **Guest online play:** Nakama device-ID auth means "playing online" still doesn't force
  a signup form — a guest gets a random name (editable) and can matchmake and use room
  codes. Creating a *real* account is only needed to sync across devices / keep friends.
- **Netiquette of data:** nothing personal is collected for offline play; online guests
  store only a display name and device ID.

---

## 7. UI / Screen Flow

```
Splash ─► Home ──┬─► Play vs AI ─────────► Game Board
                 ├─► Pass & Play ─► player setup ─► Game Board
                 ├─► Online ─┬─► Quick Match (matchmaking) ─► Game Board
                 │           ├─► Create Room (rules + code) ─► Lobby ─► Game Board
                 │           ├─► Join Room (enter code) ─► Lobby ─► Game Board
                 │           └─► Friends (list / invites)
                 ├─► Rules (presets + Rule Builder)
                 └─► Settings (theme, sound, language, account)
```

Board screen essentials:

- Classic cross-shaped board, 15×15 grid; 4 colored yards, star safe squares, home column.
- Big tappable dice with roll animation; movable tokens pulse when they have a legal move;
  auto-move when only one legal move exists (toggleable).
- Turn indicator, per-player captured/finished counters, emoji quick-chat in online games
  (no free text → no moderation burden), turn timer ring in online games.
- Portrait-first layout for phones; the board scales to landscape/desktop with side panels.

---

## 8. Milestones

| Phase | Deliverable |
|-------|-------------|
| **0. Skeleton** | Flutter app boots on all 5 targets; CI builds each platform |
| **1. Engine** | `ludo_engine` with classic rules, full unit tests, deterministic replays |
| **2. Local play** | Board UI + animations; pass & play; save/resume |
| **3. AI** | Heuristic AI (capture > progress > safety), 3 difficulty levels |
| **4. Custom rules** | `RuleConfig` in engine, presets, Rule Builder UI, rule codes |
| **5. Online core** | Nakama setup, guest auth, room codes, server-authoritative matches |
| **6. Online social** | Random matchmaking, friends, invites, reconnect handling |
| **7. Polish & ship** | Themes, sounds, i18n, store listings (Play/App Store), web deploy, Windows/Linux packages |

Each phase is releasable on its own — after Phase 2 you already have a playable offline
game to put in people's hands.

---

## 9. Testing Strategy

- **Engine:** exhaustive unit tests per rule flag; property-based tests ("a game with any
  valid config always terminates"); golden replay tests (recorded seed + actions → exact
  final state) that also guard client/server parity.
- **App:** widget tests for screens, golden-image tests for the board renderer.
- **Online:** integration tests driving two headless clients against a local server;
  chaos tests for disconnect/reconnect.
- **CI:** GitHub Actions matrix — analyze + test on every PR, platform builds on tags.
