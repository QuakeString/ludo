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
| 4 | Online or offline; login only for online play | Offline-first; **an account is never required** — an anonymous guest ID plays everything, online included |
| 5 | Design sketch | This document + `docs/mockups/` |
| 6 | Up to 6 players | **12-sided** board with triangular yards for 5–6 seats; 2–4 seats keep the classic cross |
| 7 | Team ("pair") play | 2v2 at four seats; 3v3 or 2v2v2 at six — available in pass-and-play *and* online rooms |
| 8 | Pair move (opt-in) | Two tokens on one square link into a **pair** and move together on an even roll, advancing half the pips; may pair across partners |
| 9 | Profile &amp; friends | Photo, display name and level for guests; friend **requests**, and your own **nicknames** for friends |
| 10 | Light &amp; dark theme | Both from day one — follows the system, overridable by hand |

### Mockups

Open these in a browser — every chip is drawn by the same vector routine the app will use.

| File | What it covers |
|------|----------------|
| `docs/mockups/screen-flow.html` | 18 phone screens, splash → home → seats/teams → gameplay → online → profile → result, light **and** dark |
| `docs/mockups/chip-and-motion.html` | Chip anatomy, states, stacking, pairs, **live movement demos**, both boards, both themes |
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

### Server: a small Dart server — authoritative online play

**Decision (changed from the original recommendation).** This document first recommended
**Nakama**, the open-source game server, for matchmaking, friends and match relay. That
recommendation is withdrawn, and it is worth writing down why rather than quietly editing
it away.

Nakama's authoritative match handlers run in **Go, Lua or TypeScript** — not Dart. The
rules could not have been *called*; they would have had to be **reimplemented** in a second
language. That would have thrown away the single most valuable property of this codebase:
client and server run the *same* `ludo_engine`, so an offline game and an online game
cannot disagree about the rules. That parity is currently held up by 121 engine tests. A
second implementation would mean two rule sets to keep in step, two places for a pair-move
or a home-column edge case to drift, and a whole class of "the server says that move is
illegal but the app let me make it" bugs that simply cannot occur today.

What is actually built is the *alternative*: a small **Dart server** (`shelf` +
`shelf_web_socket`) that imports `ludo_engine` directly. The features Nakama would have
given for free — room codes, presence, reconnect, matchmaking — turned out to be a few
hundred lines each, because a Ludo room is a small thing: a handful of seats, one
`GameState`, and a turn clock.

The model is **server-authoritative**: clients send *intents* (`roll`, `move token 2`,
`pass`, `breakPair`), never state. The server matches each intent against what the engine
actually offers — a move is looked up in `engine.legalMoves()` rather than trusted — applies
it, and broadcasts the result. Dice are rolled server-side (online) or from the game's own
seeded RNG (offline), so there is nothing for a modified client to lie about.

The turn clock lives on the server too, for the same reason: a phone must not be able to
grant itself more thinking time by lying about its own stopwatch. When the 30 seconds run
out the server plays the turn itself and moves on. A dropped player's seat is **held for
five minutes** and covered by the computer meanwhile, so a disconnection never stops the
table; past that window the seat is given up for good.

### Storage

- **Client:** local save via `drift`/`sqlite` or `shared_preferences` — in-progress games,
  settings, custom rule sets, guest profile. Nothing requires a network.
- **Server:** Postgres — accounts, friends, match history, shared rule sets. Rooms are
  *not* stored: a room only matters while it is being played, and a match that outlived a
  restart would be a match everybody had already left.

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
                                   │   Game Server (Dart)       │
                                   │  guest auth · room codes · │
                                   │  turn clock · reconnect    │
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
├── server/                 # Dart WebSocket game server (imports ludo_engine)
├── docs/                   # Design docs, mockups
└── DESIGN.md
```

---

## 4. Game Modes

| Mode | Players | Network | Login | Dice | Notes |
|------|---------|---------|-------|------|-------|
| **Local vs AI** | 1 human + 1–5 AI | Offline | No | Local RNG | 3 AI difficulty levels |
| **Local multiplayer (pass & play)** | 2–6 humans, one device | Offline | No | Local RNG | Turn hand-off screen between players |
| **Online — random people** | 2–6 | Online | **No** (anonymous guest) | Server RNG | Matchmaking by seat count + rule preset |
| **Online — friends** | 2–6 | Online | **No** (anonymous guest) | Server RNG | Private room with a 6-char **room code** / share link; friends list for regulars |

Humans and AI can be mixed freely in any mode. Whether an empty online seat is filled by AI
is the host's choice, never automatic.

Online details:

- **Matchmaking (random):** queue keyed by `(playerCount, rulePresetHash)` so everyone in
  a match has agreed to the same rules. Fill empty seats with AI after a timeout (optional
  setting).
- **Friends:** friend list + invites; a room can also be joined by anyone with
  the room code, no friendship required (great for "share link on WhatsApp" flows).
- **Disconnects:** **5 minutes** to reconnect (state is server-side, so rejoin is trivial).
  The game does not freeze while waiting: AI plays the absent player's turns from the moment
  they drop, and they reclaim the seat mid-game the instant they return, with the moves made
  in their absence shown in the turn log.
- **Empty seats:** filling them with AI is a **room setting, not automatic** — `Fill with AI`
  or `Leave empty`. Choosing the latter simply starts the match a player short.
- **Turn timer:** every online turn runs **30 seconds, shown as six dots, one per five
  seconds**, beside the player's name. It covers both halves of a turn — not rolling, and
  rolling but not moving. When the last dot goes out, **auto-play makes the move and the turn
  passes on**.
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

### Pair move (opt-in rule)

Two tokens sharing a square may be **linked into a pair**:

- The pair moves as one, and only on an **even roll**, advancing **half the pips** (a 6 moves
  the pair 3 squares).
- In team games a pair may be formed from your token **and a partner's token**
  (`pairAcrossPartners`).
- A pair is drawn with a gold link and a `÷2` tag — deliberately *not* like a blockade, which
  keeps its dashed-wall treatment. Both are two tokens on one square, so they must not look
  alike.

- **Locked until safe:** once linked, a pair **cannot be broken until it reaches a safe
  square** — a star square or its own home column. Pairing is a commitment, not a per-turn
  toggle.
- **Capture:** a pair can only be taken by an **opposing pair**; a single token cannot
  capture it.
- Linking is manual (tap to link) so pairing never steals a move you wanted.

- **Odd roll:** a locked pair **cannot move at all**. Move another token instead; if there is
  no other legal move the turn passes. The pair may only split once standing on a safe square.

---

## 5. Rules Engine & Custom Rules

### Standard (default) rules

- 4 players × 4 tokens; roll 6 to leave the yard; 6 grants an extra roll; three 6s in a
  row forfeits the turn; landing on an opponent captures (sends home) unless on a safe
  (star) square; exact roll needed to enter home; first to bring all 4 tokens home wins.

### The two boards

| | 2–4 seats | 5–6 seats |
|---|---|---|
| Shape | Classic 15×15 cross | **12-sided plate**, 6 arms at 60° |
| Track squares | 52 (4 × 13) | 78 (6 × 13) |
| Home column | 5 squares | 5 squares |
| Centre | 4 triangles | **Hexagon**, 6 wedges (flat edge meets each arm) |
| Yard shape | Square, 4 slots | **Triangle** (apex toward centre), 4 slots |
| Tokens per player | **2, 3 or 4 — player's choice** | **2, 3 or 4 — player's choice** |
| Token size | 78% of a square | 66% of a square |

Tokens per player is a `RuleConfig` selector at *every* seat count, not a fixed default: 3
keeps a six-seat round close to the length of a four-seat one, 4 is the traditional game.
The yard is always drawn with **four slots** regardless, so changing the count never changes
the board.

Both boards use the same geometry generator and the same token renderer; only the sector
count and radius change.

**Six-seat geometry** (viewBox 660×660, centre 330,330, cell `c` = 30):

| Element | Value | Why |
|---|---|---|
| Track rows | radius 252, 222, 192, 162, 132, **102** | 3 lanes per arm at lateral −c, 0, +c |
| Arm clearance | inner edge 87 → half-angle `atan(45/87)` = 27.4° | Under 30°, so **adjacent arms cannot collide** |
| Centre | **Hexagon**, circumradius **100** (apothem 86.6) | Flat edge meets each arm; large enough that the paths no longer collide |
| Plate | 12-gon, circumradius **282** | Vertices at ±15° off each arm, so **6 edges face the arms and 6 face the homes** |
| Yard | triangle, apex r=**100** → base r=247, half-width 70 | Apex lands **on a corner of the centre hexagon**, so three corners meet at one point |
| Yard slots | (183, 0) (211, ±24) (223, 0) | Four resting places, always drawn |
| Dice place | radius **297** on each yard axis | One per seat, just outside that seat's own corner |

Each home column carries a **coloured arrow on its turn-in square**, pointing at the centre,
so the way into home is never ambiguous.

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
  "pairMove": true,               // two tokens on one square may link into a pair
  "pairMoveEvenOnly": true,       // pair advances only on an even roll, by roll / 2
  "pairAcrossPartners": true,     // in team games, pair with a partner's token
  "pairLockedUntilSafe": true,    // cannot unpair until a star square or the home column
  "pairCapturableBy": "pair",     // only an opposing pair may capture a pair
  "turnTimerDots": 6,             // 6 dots x 5s = 30s, then auto-play
  "fillEmptySeatsWithAI": true,   // host's choice, never automatic
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
- **Anonymous online play:** an account is **never required**. A guest id minted on first
  connect creates
  a guest ID silently; guests are matched with other guests, can use room codes, and can hold
  a friends list. Signing in is offered exactly once, as an optional way to copy the profile
  to a second device.

### Profile, friends and levels

Even an anonymous guest is somebody:

- **Profile:** display name, **profile photo** (or a generated avatar), and a **level** that
  grows with matches played and won. Stored on-device unless an account is linked.
- **Friend requests:** you send a request, it lands in the other player's inbox, and it only
  sticks if they accept.
- **Nicknames:** because guest IDs are arbitrary, every friend can be given **your own
  nickname**; the list shows your name for them with the real ID underneath.
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

### Dice placement and seating

- **One dice place per seat.** The die is never parked in the centre; it **travels to whoever
  is on turn** and rests at that seat's own place — inside the home yard on the four-seat
  board, just outside the seat's corner on the six-seat board.
- **Pass & play** seats players *facing each other*: 2 at opposite ends, 4 as two opposite
  pairs, 6 spread evenly around the hexagon. Each player's name and die face their own edge
  of the device, so nobody plays upside down.
- **Online**, you are always at the **bottom-left** and the board rotates around you; every
  player sees themselves in the same place, with opponents filling the rest in turn order.

Board screen essentials:

- Board (cross or hexagon per seat count), big tappable dice with roll animation.
- Movable tokens pulse; auto-move when only one legal move exists (toggleable).
- Turn indicator, per-seat finished counters grouped by team, emoji quick-chat in online
  games (no free text → no moderation burden), turn timer ring in online games.
- Portrait-first layout for phones; the board scales to landscape/desktop with side panels.

### Splash

Four-colour diamond mark with **the game token itself standing at its centre**, tossing and
spinning in 3D while the local save loads (~1.2 s), then settling. Using the real token
rather than a generic coin means the first thing a player ever sees is the object they will
spend the whole game moving. Skippable on tap; falls back to a static mark under
`prefers-reduced-motion`.

### Theming

**Light and dark are both first-class from day one** — not a later phase. The app follows the
system theme and can be overridden by hand (`System / Light / Dark`) in settings. Dark is its
own palette, not a filter: surface, grid lines and yard interiors are all redrawn. The token
is unchanged between themes — its white rim is precisely what lets one design work on both
grounds.

| Token | Light | Dark |
|---|---|---|
| Plate | `#FDFBF7` | `#232830` |
| Track square | `#FFFFFF` | `#2E343F` |
| Grid line | `#C9C1B2` | `#4A5260` |
| Yard interior | `#FFFFFF` | `#1B1F26` |

Seat colours are identical in both themes.

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

**Legal-move ring.** The moment the dice lands, **every token of the player on turn that has a
legal move is ringed in that player's colour** — a 3.5 px ring with a soft tint and a slow
outward pulse. It answers where your tokens are and which of them this roll can move, in one
glance. Tokens with no legal move stay plain; the ring clears as soon as a move is made.

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
| **2. Local play** | Board UI (cross), token renderer + motion, **light/dark theming**, pass & play, save/resume |
| **2b. Six seats & teams** | Hexagon board generator (triangular yards), team rules, pair move, seat/team setup screens |
| **3. AI** | Heuristic AI (capture > progress > safety), 3 difficulty levels |
| **4. Custom rules** | `RuleConfig` in engine, presets, Rule Builder UI, rule codes |
| **5. Online core** | Dart server, guest auth, room codes, server-authoritative matches |
| **6. Online social** | Random matchmaking, profiles &amp; levels, friend requests &amp; nicknames, invites, 5-minute reconnect |
| **7. Polish & ship** | Sounds, i18n, store listings (Play/App Store), web deploy, Windows/Linux packages |

Each phase is releasable on its own — after Phase 2 you already have a playable offline
game to put in people's hands.

---

## 8a. Deploying the server

Yes — Docker, and deliberately a very boring one.

### The image

`server/Dockerfile` is two stages:

1. **Build** on `dart:3.13`. Manifests are copied first so `dart pub get` is cached and
   does not re-run on every source edit, then `dart compile exe` turns the server into a
   single native binary.
2. **Ship** `FROM scratch` — the Dart runtime's few shared objects (`/runtime/`) plus that
   one binary. No SDK, **no shell**, no package manager. Tens of megabytes rather than the
   ~700 MB of a full SDK image, less to patch, and nothing for anyone who does get in to
   run.

Because there is no shell, the container cannot health-check itself with `curl`. Instead
the binary checks itself: `ludo-server --health` asks the running server on `127.0.0.1:$PORT`
and reports through its exit code. That is what `docker-compose.yml` and any orchestrator's
liveness probe call.

`.dockerignore` keeps the Flutter app, git history and every local `.dart_tool` out of the
build context — the last of those matters for correctness, not just speed, since a
`package_config.json` written with host paths would point the container's package
resolution at directories that do not exist inside it.

### Running it

```bash
docker compose up --build     # server on :8080, WebSocket at ws://localhost:8080/ws
```

Postgres is in the compose file for what comes next (accounts, friends, match history).
The game server does not touch it yet — rooms live in memory on purpose.

### Where it goes

One process holds every live room, so the first deployment is **one container**: any VPS,
Fly.io, Railway, Render, or a small Cloud Run/ECS service. A 6-player Ludo room is a few
kilobytes and a couple of messages per turn; a single small instance holds thousands of
concurrent rooms long before CPU matters.

Scaling out is the one thing the current design does *not* do for free. Rooms are in
process memory, so two replicas behind a round-robin load balancer would put a room's
players on different servers. When that day comes there are two honest options, in
increasing order of effort:

- **Sticky routing by room code** — hash the code to a replica at the edge. Cheap, works,
  loses a room's live matches if that replica restarts.
- **Move room state to Redis** and make servers stateless. More machinery; only worth it
  when a single box is genuinely the limit.

Neither is needed to launch, and neither changes the protocol, so this is a decision that
can wait for evidence rather than be guessed at now.

TLS terminates at the proxy in front of the container (Caddy, nginx, or the platform's own
router). The client connects over `wss://` in production; the server itself speaks plain
HTTP inside the network.

---

## 9. Testing Strategy

- **Engine:** exhaustive unit tests per rule flag; property-based tests ("a game with any
  valid config always terminates"); golden replay tests (recorded seed + actions → exact
  final state) that also guard client/server parity.
- **App:** widget tests for screens, golden-image tests for the board renderer.
- **Online:** integration tests driving two headless clients against a local server;
  chaos tests for disconnect/reconnect.
- **CI:** GitHub Actions matrix — analyze + test on every PR, platform builds on tags.
