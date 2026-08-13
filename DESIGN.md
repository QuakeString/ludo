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
| 5 | Design sketch | This document + `docs/mockups/` |
| 6 | Up to 6 players | Hexagonal board for 5–6 seats; 2–4 seats keep the classic cross |
| 7 | Team ("pair") play | 2v2 at four seats; 3v3 or 2v2v2 at six — available in pass-and-play *and* online rooms |

### Mockups

Open these in a browser — every chip is drawn by the same vector routine the app will use.

| File | What it covers |
|------|----------------|
| `docs/mockups/screen-flow.html` | 11 phone screens, splash → home → seats/teams → gameplay → online → result |
| `docs/mockups/chip-and-motion.html` | Chip anatomy, states, stacking, **live movement demos**, both boards |
| `docs/mockups/review-sheet.html` | Commentable checklist of every decision (notes saved on-device) |
| `docs/mockups/overview.html` | One-page summary of stack, modes and roadmap |

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
| **Local vs AI** | 1 human + 1–5 AI | Offline | No | Local RNG | 3 AI difficulty levels |
| **Local multiplayer (pass & play)** | 2–6 humans, one device | Offline | No | Local RNG | Turn hand-off screen between players |
| **Online — random people** | 2–6 | Online | Yes (guest OK) | Server RNG | Matchmaking by seat count + rule preset |
| **Online — friends** | 2–6 | Online | Yes (guest OK) | Server RNG | Private room with a 6-char **room code** / share link; friends list for regulars |

Humans and AI can be mixed freely in any mode — an online room with an empty seat can be
filled by AI rather than blocking the start.

Online details:

- **Matchmaking (random):** queue keyed by `(playerCount, rulePresetHash)` so everyone in
  a match has agreed to the same rules. Fill empty seats with AI after a timeout (optional
  setting).
- **Friends:** friend list + invites via Nakama; a room can also be joined by anyone with
  the room code, no friendship required (great for "share link on WhatsApp" flows).
- **Disconnects:** 60s grace to reconnect (state is server-side, so rejoin is trivial);
  after that the seat is taken over by AI or skipped, per room setting.
- **Anti-cheat:** server-authoritative state + server-side dice → clients can't lie.

### Team ("pair") play

Available in pass-and-play *and* online rooms, at any seat count that divides evenly:

| Seats | Formats |
|-------|---------|
| 4 | `2v2` (partners seated opposite) or free-for-all |
| 6 | `3v3`, `2v2v2`, or free-for-all |

Team behaviour — each item is a `RuleConfig` switch, not a hard-coded rule:

- Partners never capture each other, and don't blockade each other.
- A player whose tokens are all home keeps rolling **for the team** (moving a partner's token).
- The team wins when *every* partner has all tokens home.
- UI: your own team carries a colored rail in the seat list, so friend-vs-foe is readable
  without decoding six hues. Teams are assigned in a dedicated setup screen (local) or by
  dragging players between sides in the lobby (online).

---

## 5. Rules Engine & Custom Rules

### Standard (default) rules

- 4 players × 4 tokens; roll 6 to leave the yard; 6 grants an extra roll; three 6s in a
  row forfeits the turn; landing on an opponent captures (sends home) unless on a safe
  (star) square; exact roll needed to enter home; first to bring all 4 tokens home wins.

### The two boards

| | 2–4 seats | 5–6 seats |
|---|---|---|
| Shape | Classic 15×15 cross | Hexagon, 6 arms at 60° |
| Track squares | 52 (4 × 13) | 78 (6 × 13) |
| Home column | 5 squares | 5 squares |
| Tokens per player (default) | 4 | **3** |
| Token size | 78% of a square | 66% of a square |

Six players × 4 tokens runs long and crowds every square, so six seats default to 3 tokens
each — which keeps a six-player round close to the length of a four-player one. It is a
`RuleConfig` value, so a table that wants four can set it back.

Both boards use the same geometry generator and the same token renderer; only the sector
count and radius change.

### Custom rules = a data object, not code

Every variant is expressed as a `RuleConfig` the engine interprets:

```jsonc
{
  "id": "quick-family",
  "name": "Quick Family Game",
  "seats": 6,                     // 2..6 — 5 or 6 selects the hexagon board
  "teams": [[0, 2, 4], [1, 3, 5]],// null = free-for-all; else seat indices per team
  "partnersCanCapture": false,
  "finishedPlayerMovesPartner": true,
  "tokensPerPlayer": 2,          // 1..4 (defaults to 3 at 5–6 seats, 4 otherwise)
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
Splash ─► Home ──┬─► Play vs AI ────► seats ─┬─► [teams] ─► rules ─► Game Board
                 ├─► Pass & Play ──► seats ──┘
                 ├─► Online ─┬─► Quick Match (matchmaking) ─► Game Board
                 │           ├─► Create Room (seats + teams + rules) ─► Lobby ─► Game Board
                 │           ├─► Join Room (enter code) ─► Lobby ─► Game Board
                 │           └─► Friends (list / invites)
                 ├─► Rules (presets + Rule Builder)
                 └─► Settings (theme, sound, language, account)
                                                        Game Board ─► Result / Rematch
```

Seat count is chosen **before** anything else, because it determines the board shape, the
default token count, and whether teams are possible at all. The teams step appears only for
4 and 6 seats. See `docs/mockups/screen-flow.html` for all 11 screens.

Board screen essentials:

- Board (cross or hexagon per seat count), big tappable dice with roll animation.
- Movable tokens pulse; auto-move when only one legal move exists (toggleable).
- Turn indicator, per-seat finished counters grouped by team, emoji quick-chat in online
  games (no free text → no moderation burden), turn timer ring in online games.
- Portrait-first layout for phones; the board scales to landscape/desktop with side panels.

### Splash

Four-colour diamond mark with a **3D Ludo coin at its centre that tosses and spins** while
the local save loads (~1.2 s), then settles. Skippable on tap; falls back to a static mark
under `prefers-reduced-motion`.

---

## 7a. Token ("chip") Rendering

The token is the single most important object in the game — this is where most Ludo apps
fail, so it is specified rather than left to implementation. Full spec with live motion
demos: `docs/mockups/chip-and-motion.html`.

**Form.** A carrom-style pawn — ball head, collar, flared base — lit from the upper left,
with a hard **white rim** so a blue token stays readable on a blue square. Drawn as vector
geometry in code (no bitmap assets) and recoloured for all six seats from one shape, so it
stays sharp at every density.

**Six seat colours.** Red `#E14B4B`, Green `#3FA35C`, Blue `#3B72D9`, Yellow `#E3B23C`,
Purple `#7E57C2`, Orange `#EF8022` — ordered so no two adjacent seats are confusable, and
so seat position plus the rim (never hue alone) carries the difference for red–green colour
deficiency.

**Several tokens on one square.** Up to two draw in full; three or more collapse to one
token plus a count badge. Same-seat groups stack front-to-back; mixed seats sit side by side
— *whose* tokens are there matters more than how many. Tapping a crowded square fans its
tokens into an arc above the board so each is individually selectable.

**Movement.** One hop per pip — a roll of 5 is five separate ~150 ms arcs, so the move can
be counted as it happens. Landing squashes 1.12 × 0.88 and recovers over 90 ms; the contact
shadow shrinks as the token rises. Captures get a hard squash, then the captured token pops,
spins and arcs back to its yard (~0.7 s). Illegal moves never animate halfway — the token
nudges 4 px, the blocker flashes, and the turn is still yours.

| Element | 4-player board | 6-player board |
|---|---|---|
| Token width | 78% of a square | 66% of a square |
| White rim | 4.5% | 5% (never < 1.5 physical px) |
| Hop height | 70% | 62% |
| Count badge | 36% | 40% |
| Minimum tap target | 44 px (invisible, independent of token size) | 44 px |

---

## 8. Milestones

| Phase | Deliverable |
|-------|-------------|
| **0. Skeleton** | Flutter app boots on all 5 targets; CI builds each platform |
| **1. Engine** | `ludo_engine` with classic rules, full unit tests, deterministic replays |
| **2. Local play** | Board UI (cross), token renderer + motion, pass & play, save/resume |
| **2b. Six seats & teams** | Hexagon board generator, team rules, seat/team setup screens |
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
