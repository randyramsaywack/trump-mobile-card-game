# Multiplayer Milestone 2 — Authoritative Game Loop — Design Spec

## Problem

Milestone 1 stood up a dedicated ENet server, locked in the dict-based wire protocol, and shipped a working lobby — username entry, create/join room, waiting room. But the host's "Start Game" button currently just shows a `"Milestone 1: game logic not implemented"` toast on every client and nothing else happens. No game logic crosses the wire.

This spec covers M2: turning "Start Game" into an actual playable round-over-the-network experience, driven by a server-authoritative game loop. After this milestone, 2–4 humans in a room can play full rounds of Trump back-to-back against each other (with AI filling any empty seats), with dealing, trump selection, trick play, scoring, dealer rotation, and a host-driven next-round button all working correctly. The server owns the game state; clients are pure display + input.

## Goals

1. Run `RoundManager` authoritatively on the server, per room, reusing the existing single-player implementation without forking it.
2. Ship a wire protocol extension that streams every game event the client needs — dealing, trump selection, card plays, trick resolution, round end — with per-recipient tailoring so private cards stay private.
3. Build a client-side game-state mirror (`NetGameView`) that presents the same API and signals as `RoundManager`, so the existing `game_table_ui.gd` works in multiplayer with a mechanical refactor rather than a rewrite.
4. Fill empty seats (and seats vacated by disconnect or leave) with server-side `AIPlayer` instances. A room with 2 humans plays a legal game against 2 AIs with no visible distinction from single-player AI behaviour.
5. Implement a full session loop: round 1 → win screen → host presses "Next Round" → round 2 with rotated dealer → repeat, until the host leaves or the room collapses.

## Non-Goals

- **Turn timer.** No 60-second move deadline, no timer UI, no forced AI play on inactivity. Humans can think forever.
- **Reconnect / rejoin.** A dropped human is replaced by AI and cannot return. The AI owns that seat for the rest of the session.
- **Host migration.** Host disconnect or leave always collapses the room, same as M1.
- **Host-picks-AI-difficulty.** AI difficulty is hardcoded to `MEDIUM`. No waiting-room dropdown, no protocol field.
- **Configurable server address.** Client still connects to hardcoded `127.0.0.1:9999`. Production domain wiring is a separate deployment milestone.
- **Networked pause.** A client opening its settings menu does not pause the game. Pause overlay is visual-only in multiplayer.
- **Stats / leaderboards / match history.** `StatsManager` stays single-player-only.
- **Chat, spectator mode, lobby browser, friend invites, replays, ranked matchmaking, cosmetics.**
- **Encryption, rate limiting, anti-cheat beyond basic server validation.** The server trusts its clients to behave within the wire protocol. Malformed messages are silently dropped (M1 behavior).
- **Graceful server shutdown broadcast.** Server dying just closes sockets; clients return to main menu via ENet timeout.
- **Mobile device testing over the real network.** All verification is local against `127.0.0.1:9999`.
- **State snapshot messages.** Every event is a delta. No `MSG_FULL_STATE` that lets a client catch up mid-session. When M3 adds reconnect, the snapshot format gets designed then.

## Scope

One working local dev loop: you press F5 in Godot several times (first instance = server, the rest = clients), 2–4 clients enter the multiplayer menu, one creates a room, the rest join by code, the host presses Start, everyone transitions to the game table, a full round plays out end-to-end with correct dealing / trump / trick / scoring, a team reaches 7 books, the win screen appears on all clients, the host presses "Next Round", and a second round plays out with the dealer correctly rotated. Any non-host can leave or disconnect mid-game and AI takes their seat cleanly; the host leaving still collapses the room. Single-player continues to work unchanged.

---

## Architecture

### Authority model

The server owns every piece of authoritative game state. Each room with an active game holds exactly one `RoundManager` instance (reused from single-player, unchanged) wrapped by a new `GameSession` class that handles the network concerns. Clients are pure renderers + input: they hold a `NetGameView` that tracks whatever state the server has told them about, re-emits matching signals, and forwards player actions back to the server for validation.

The existing `autoloads/game_state.gd` gains a new `game_source: Node` field that's either:
- A `RoundManager` (single-player mode — unchanged behavior)
- A `NetGameView` (multiplayer mode — new)

`game_table_ui.gd` reads from `GameState.game_source` instead of `GameState.round_manager`. This is the only place the UI has to know about the abstraction. Every existing signal hookup works unchanged because `NetGameView` exposes the same signal names and argument shapes as `RoundManager`.

### RoundManager reuse

`scripts/round_manager.gd` has zero references to `GameState` and exactly one autoload reference (`Settings.anim_multiplier()` at line 233, used for trick display timing). The server already has `Settings` as an autoload from M1, defaulting to Normal speed, so `RoundManager` instantiates and runs on the server with no code changes.

`start_round(players, dealer)` takes its player list by parameter, so a single server process can host multiple concurrent games — each room has its own `RoundManager` with its own `players` array of a mix of `Player` and `AIPlayer` instances.

### Signal-to-message bridge

`GameSession` subscribes to every relevant `RoundManager` signal in its constructor. Each signal handler builds per-recipient messages and appends them to a `_pending_events: Array` buffer. The buffer is drained in two places:

- **After any mutation driven by a client action** — `handle_play_card`, `handle_declare_trump`, `handle_next_round` — the caller returns the drained buffer as `Array[(peer_id, msg)]`, matching the existing `RoomManager` handler shape.
- **From the main server tick loop** — `main_server._process()` now calls `tick(delta)` on every room's `GameSession`, which in turn ticks its `RoundManager` (driving AI delays and trick display timers), then drains the buffer and dispatches any accumulated messages.

This keeps the server's "pure function" handler style from M1 intact while letting asynchronous events (AI plays, timer-driven transitions) flow naturally.

### Per-recipient message tailoring

The `GameSession._pending_events` buffer stores `(peer_id, msg)` tuples directly rather than "one public message" objects. A single `RoundManager.hand_dealt` signal typically produces several entries — one per human peer — each with a tailored payload. The owner of the hand receives a message with the full `cards` array; every other peer receives the same message with only a `count` field. This matches the existing `RoomManager` return-shape convention, so `main_server.gd`'s dispatcher doesn't need to learn anything new about delivery.

---

## File Layout

### Server — new files

**`scripts/server/game_session.gd`** (~200 lines). RefCounted, one per active room. Owns:

- `round_manager: RoundManager` (reused unchanged from single-player).
- `players: Array[Player]` — mix of real `Player` and `AIPlayer`, indexed by seat 0–3. `AIPlayer` instances fill any seat not owned by a connected human peer.
- `peer_to_seat: Dictionary[int, int]` — reverse lookup for validating incoming actions.
- `session_wins: Array[int]` — `[team0, team1]`, persists across rounds until the room dies.
- Dealer rotation state — mirrors the logic currently living in `autoloads/game_state.gd` lines 19–81 (per-team dealer tracking, rotating within the losing team).
- `_pending_events: Array` — the `(peer_id, msg)` tuple buffer signal handlers write to.

Public methods:

- `start_first_round(starting_dealer: int)` — appends the `MSG_SESSION_START` and `MSG_ROUND_STARTING` messages, calls `round_manager.start_round(players, starting_dealer)`, returns the drained buffer.
- `handle_play_card(peer_id, card_data) -> Array` — validates sender, phase, turn, and card legality, calls `round_manager.play_card(seat, card)`, returns the drained buffer. On validation failure, returns `[[peer_id, error_msg]]`.
- `handle_declare_trump(peer_id, suit) -> Array` — same pattern for trump selection.
- `handle_next_round(peer_id) -> Array` — host-only. Advances dealer rotation, appends `MSG_ROUND_STARTING`, calls `round_manager.start_round`.
- `handle_player_disconnect(peer_id) -> Array` — swaps the seat's `Player` for an `AIPlayer(MEDIUM)`, transfers the hand, appends `MSG_SEAT_TAKEN_OVER_BY_AI`. If the seat was the current active turn, nothing else needs to happen — `RoundManager`'s next tick picks up the new AI.
- `handle_player_leave(peer_id) -> Array` — identical path to disconnect, different reason field in the broadcast.
- `tick(delta) -> Array` — calls `round_manager.tick(delta)`, returns drained buffer.
- `has_humans() -> bool` — returns true if any seat is still owned by a real peer. Used by `RoomManager` to collapse empty games.

**`scripts/server/room_manager.gd`** (modified). `handle_start_game` stops being a stub — it constructs the `GameSession`, stores it on the room, calls `start_first_round` with a randomly-selected starting dealer, and returns the initial event batch to `main_server`. New delegating handlers for `play_card`, `declare_trump`, `next_round` forward to the room's `GameSession`. `handle_leave_room` gets a branch: if the room has a live `GameSession`, call `handle_player_leave` on it; if the leaving player is the host, still fall through to the M1 `HOST_LEFT` collapse path. `handle_disconnect` gets the same game-aware branch. After either disconnect or leave, `RoomManager` checks `game_session.has_humans()` and destroys the session + room if no humans remain.

**`scripts/server/room.gd`** (modified). Gets a `game_session: GameSession` field (null during `WAITING`, set when the game starts). The `State` enum gains two new values: `IN_GAME` (during an active round) and `BETWEEN_ROUNDS` (after round end, before host presses Next Round).

**`scripts/server/main_server.gd`** (modified). `_process(delta)` gets a new section: iterate every active `Room`, call `room.game_session.tick(delta)` if non-null, and dispatch any returned `(peer_id, msg)` tuples via the existing send path. Also gains dispatch cases for the four new C→S message types.

### Client — new files

**`scripts/net/net_game_view.gd`** (~150 lines). `extends Node`. The mirror of `RoundManager`'s public API. Declares the same signals (`hand_dealt`, `trump_selection_needed`, `trump_declared`, `turn_started`, `card_played_signal`, `trick_completed`, `round_ended`) and the same public state fields (`state`, `trump_suit`, `dealer_seat`, `trump_selector_seat`, `current_player_seat`, `players`, `books`, `books_by_seat`, `trick_history`).

Only the local player's hand is stored as a real `Array[Card]`; every other seat's `Hand` stores card counts only. `NetGameView` computes valid-card highlighting locally during `turn_started` events using the owner's own hand and the trick's led suit + trump, so no `valid_cards` list has to cross the wire.

Primary public method: `apply_event(msg: Dictionary) -> void`, which matches on `msg.type`, mutates state, and re-emits the matching signal.

### Client — modified files

**`autoloads/game_state.gd`**. New field `var game_source: Node = null`. The existing `round_manager` reference stays but becomes a backing field that's set alongside `game_source` in single-player mode. In multiplayer, `round_manager` is null and `game_source` holds a `NetGameView`. `GameState`'s session-wins, dealer-rotation, and player-list management stays intact for single-player but is bypassed in multiplayer (the server owns those).

**`scripts/ui/game_table_ui.gd`**. Mechanical refactor: every `GameState.round_manager.X` becomes `GameState.game_source.X`. Signal connections in `_ready` read off `game_source`. No behavior changes — same signals, same properties, just a different source object. Any places that push *state mutations* back into `round_manager` (e.g. when the human taps a card) need to branch: in single-player, call `round_manager.play_card(...)` directly as before; in multiplayer, call `NetworkState.play_card(...)` which sends `MSG_PLAY_CARD` and lets the server round-trip the change back through `game_source`.

**`autoloads/network_state.gd`**. Four new client-facing facades: `play_card(card)`, `declare_trump(suit)`, `next_round()`, `leave_game()` (which reuses `MSG_LEAVE_ROOM`). `_handle_server_message` grows cases for every new S→C message, most of which just forward to `GameState.game_source.apply_event(msg)`. Two exceptions — `MSG_SESSION_START` creates a fresh `NetGameView`, assigns it to `GameState.game_source`, and calls `get_tree().change_scene_to_file("res://scenes/game_table.tscn")`; `MSG_ROUND_ENDED` is forwarded to `game_source` but also triggers the win-screen UI transition.

**`scripts/net/protocol.gd`**. Extended with the new `MSG_*` and `ERR_*` constants and a helper `card_to_dict(card)` / `dict_to_card(d)` for the card serialization shape.

**`scripts/ui/room_waiting_ui.gd`**. Minor — remove the "Milestone 1: game logic not implemented" toast on `game_starting`. The waiting room now waits for `MSG_SESSION_START` instead, which triggers scene transition via `NetworkState`. The Start button's 2-human minimum check stays unchanged.

---

## Protocol

All new messages follow the M1 wire format: `{ "type": String, "data": Dictionary }`, serialized with `var_to_bytes`, channel 0 reliable.

### Client → Server (4 new)

| Message | Data | Notes |
|---|---|---|
| `MSG_PLAY_CARD` | `{ "card": { "suit": int, "rank": int } }` | Validated server-side: sender owns the seat that's currently active, card is in their hand, card is legal under follow-suit rules. |
| `MSG_DECLARE_TRUMP` | `{ "suit": int }` | Sender must be the trump selector, phase must be `TRUMP_SELECTION`. |
| `MSG_NEXT_ROUND` | `{}` | Host-only, phase must be `BETWEEN_ROUNDS`. |
| `MSG_LEAVE_ROOM` | `{}` | **Reused from M1.** Server branches on whether the room is in-game: if yes, sender's seat swaps to AI via the same path as disconnect; if no, falls back to M1's remove-seat behavior. Host leaving still collapses the room. |

### Server → Client (10 new)

| Message | Data | Recipient | Notes |
|---|---|---|---|
| `MSG_SESSION_START` | `{ "seats": [{"seat", "username", "is_ai"}, ...], "starting_dealer_seat": int, "session_wins": [int, int] }` | All | Triggers client scene change from `room_waiting` → `game_table`. Carries the full seat roster. |
| `MSG_ROUND_STARTING` | `{ "dealer_seat": int, "trump_selector_seat": int, "round_number": int }` | All | Also used for rounds 2+. Clients clear per-round state and dismiss the between-rounds screen if shown. |
| `MSG_HAND_DEALT` | Public: `{ "seat_index": int, "count": int }`<br>Private to owner: `{ "seat_index": int, "count": int, "cards": [{"suit", "rank"}, ...] }` | **Tailored** | Per-recipient copy. Owners get their card list; others see only the count. |
| `MSG_TRUMP_SELECTION_NEEDED` | `{ "seat_index": int }` | All | Everyone knows who's choosing. Initial 5 cards already arrived via `MSG_HAND_DEALT` — not re-sent. |
| `MSG_TRUMP_DECLARED` | `{ "suit": int }` | All | Triggers the "Trump is X" HUD update on all clients. |
| `MSG_TURN_STARTED` | `{ "seat_index": int }` | All | Valid-card highlighting is computed locally by `NetGameView`. |
| `MSG_CARD_PLAYED` | `{ "seat_index": int, "card": {"suit", "rank"} }` | All | Drives the card-fly animation. |
| `MSG_TRICK_COMPLETED` | `{ "winner_seat": int, "books": [int, int], "books_by_seat": [int, int, int, int] }` | All | Mirrors `RoundManager.trick_completed` signal shape. |
| `MSG_ROUND_ENDED` | `{ "winning_team": int, "session_wins": [int, int], "trick_history": [...] }` | All | Triggers the between-rounds win screen. |
| `MSG_SEAT_TAKEN_OVER_BY_AI` | `{ "seat_index": int, "reason": "disconnect" \| "left", "display_name": String }` | All | Clients update the seat label and show a short toast. |

### New error codes

Added to `Protocol.ERROR_MESSAGES`:

| Code | Message | When |
|---|---|---|
| `ERR_NOT_YOUR_TURN` | `"It's not your turn."` | `play_card`/`declare_trump` from a seat that isn't currently active. |
| `ERR_INVALID_CARD` | `"That card can't be played."` | Card not in hand, or doesn't follow led suit, or wrong phase. |
| `ERR_WRONG_PHASE` | `"That action isn't allowed right now."` | Phase-mismatch catch-all. |
| `ERR_NOT_IN_GAME` | `"The game hasn't started yet."` | Game-phase action sent before `SESSION_START`, or after the sender's seat became AI. |

### Card serialization

Two helpers in `Protocol`:

```gdscript
static func card_to_dict(card: Card) -> Dictionary:
    return { "suit": card.suit, "rank": card.rank }

static func dict_to_card(d: Dictionary) -> Card:
    return Card.new(int(d["suit"]), int(d["rank"]))
```

These are used wherever a card crosses the wire (in `MSG_HAND_DEALT` and `MSG_CARD_PLAYED` server-side, and in `MSG_PLAY_CARD` client-side).

---

## Round Lifecycle Walkthrough

Representative setup: 3 humans (Alice=host=seat 0, Bob=seat 1, Carol=seat 2) and 1 AI (seat 3). Alice presses Start. Random dealer picks seat 0 (Alice), so the trump selector is seat 1 (Bob).

### 1. Host presses Start

- **Server.** `RoomManager.handle_start_game` constructs `GameSession` on the room, seats the three humans as `Player` and seat 3 as `AIPlayer(MEDIUM)`. Picks a random dealer. Appends one `MSG_SESSION_START` per human peer with the full seat roster. Calls `game_session.start_first_round(dealer=0)`.
- **Clients.** `NetworkState` sees `session_start`, creates a fresh `NetGameView`, assigns `GameState.game_source = net_game_view`, calls `change_scene_to_file("game_table.tscn")`. The existing `game_table_ui.gd` wakes up, connects signals on `game_source`, and renders the initial table layout.

### 2. Round begins (deal initial)

- **Server.** `GameSession` appends `MSG_ROUND_STARTING { dealer_seat: 0, trump_selector_seat: 1, round_number: 1 }` synthetically (this isn't emitted by `RoundManager` — `GameSession` creates it to give clients a dismissal signal for the between-rounds screen when it applies). Then calls `round_manager.start_round(players, dealer=0)`, which transitions to `DEALING_INITIAL` and emits `hand_dealt(seat_index=1, cards=[5 cards])`. `GameSession`'s signal handler produces three tailored messages — Alice and Carol get `{ seat_index: 1, count: 5 }`; Bob gets the full `cards` list.
- **Clients.** `NetGameView.apply_event` stores cards (Bob) or counts (Alice, Carol), re-emits `hand_dealt`. UI renders 5 face-down cards at seat 1 for Alice/Carol; Bob sees his actual hand face-up.

### 3. Trump selection

- **Server.** `RoundManager` transitions to `TRUMP_SELECTION`, emits `trump_selection_needed(seat=1, initial_cards=[...])`. `GameSession` strips the cards (Bob already holds them locally) and fans out `MSG_TRUMP_SELECTION_NEEDED { seat_index: 1 }` to all three humans. Then waits — no further `RoundManager` ticks advance trump selection until someone calls `declare_trump`.
- **Clients.** Bob's UI shows the trump-selection overlay with his 5 cards and 4 suit buttons. Alice and Carol see "Bob is choosing trump…" on the HUD.
- **Bob taps Hearts.** Client sends `MSG_DECLARE_TRUMP { suit: 2 }`.
- **Server.** `GameSession.handle_declare_trump` validates (Bob owns seat 1, seat 1 is trump selector, phase is `TRUMP_SELECTION`), calls `round_manager.declare_trump(Hearts)`. `RoundManager` emits `trump_declared(Hearts)`, transitions to `DEALING_REMAINING`, deals the remaining cards — emitting `hand_dealt` again for each seat as it completes. `GameSession` fans out tailored copies. `RoundManager` then transitions to `PLAYER_TURN` with `current_player_seat = 1` and emits `turn_started(seat=1, valid_cards=...)`. `GameSession` fans out `MSG_TURN_STARTED { seat_index: 1 }` (dropping `valid_cards` — computed locally).
- **Clients.** Everyone sees "Trump is Hearts" on the HUD, hands update to full, Bob's valid cards get highlighted (computed from his local hand + led suit + trump).

### 4. Trick play (×13)

- **Bob taps a card.** Client sends `MSG_PLAY_CARD { card: {suit, rank} }`.
- **Server.** `GameSession.handle_play_card` runs the full validation pipeline (turn, phase, card in hand, legal under follow-suit), calls `round_manager.play_card(seat=1, card)`. `RoundManager` emits `card_played_signal`, advances `current_player_seat = 2`, emits `turn_started(seat=2, ...)`.
- **Clients.** Card flies from seat 1 to the table centre. "Carol's turn" appears on the HUD.
- **Carol plays, seat 3 (AI) plays, seat 0 plays.** The AI play happens entirely server-side — `RoundManager.tick(delta)` runs the AI delay timer, then the AI's `choose_card()` is invoked internally, and `RoundManager` fires `card_played_signal` without client input. Humans see `MSG_CARD_PLAYED` events arrive paced by the server's tick loop.
- **Trick resolves.** `RoundManager` detects 4 cards played, transitions `PLAYER_TURN → TRICK_RESOLUTION → TRICK_DISPLAY`, emits `trick_completed(winner_seat, books, books_by_seat)`. `GameSession` fans out `MSG_TRICK_COMPLETED`. Clients animate the book counter, show the trick for ~2 s, then clear. `RoundManager.tick` runs the `TRICK_DISPLAY_DURATION` timer, then transitions back to `PLAYER_TURN` with the trick winner leading, emits `turn_started`. Loop repeats.

### 5. Round ends

- **Server.** When a team hits 7 books, `RoundManager` emits `round_ended(winning_team)` and transitions to `ROUND_OVER`. `GameSession` updates `session_wins[winning_team] += 1`, advances dealer rotation (next dealer is the other member of the losing team), sets `room.state = BETWEEN_ROUNDS`, and appends `MSG_ROUND_ENDED { winning_team, session_wins, trick_history }` per peer.
- **Clients.** `NetGameView.apply_event(round_ended)` re-emits the signal. `game_table_ui.gd` transitions to the win screen. Alice (host) sees "Next Round" and "Leave"; Bob and Carol see "Waiting for host…" and "Leave".

### 6. Next round

- **Alice presses Next Round.** Client sends `MSG_NEXT_ROUND {}`.
- **Server.** `GameSession.handle_next_round` validates (sender is host, phase is `BETWEEN_ROUNDS`), appends `MSG_ROUND_STARTING` with the rotated dealer, calls `round_manager.start_round(players, new_dealer)`. Events flow from step 2 again.

### Disconnect path (non-host, mid-round)

Bob's ENet connection drops during trick 5.

- **Server.** `main_server._on_peer_disconnected(peer_Bob)` fires. `RoomManager.handle_disconnect` finds the live `GameSession`, calls `game_session.handle_player_disconnect(peer_Bob)`. `GameSession` constructs `AIPlayer(MEDIUM, username="Bob")` and swaps it in at seat 1 in both `players[]` and `round_manager.players[]`, transferring the existing hand. If it was Bob's turn, nothing else needs to happen — `RoundManager`'s next tick picks up the new AI. Appends `MSG_SEAT_TAKEN_OVER_BY_AI { seat_index: 1, reason: "disconnect", display_name: "Bob" }` to all remaining humans. `_peer_to_room.erase(peer_Bob)`.
- **Clients.** Alice and Carol see a "Bob disconnected — AI taking over" toast (1.5 s, auto-dismiss). Seat-1 label stays as "Bob" with an "(AI)" suffix. Game continues without interruption.

**Key invariant:** `RoundManager` doesn't know or care whether a seat is human or AI at the moment it needs to act — it asks `players[seat]` for its type and routes accordingly. Hot-swapping `players[1]` from `Player` to `AIPlayer` mid-round is a legal operation that `RoundManager` already supports.

---

## Error Handling & Edge Cases

### Per-action validation pipeline

Every incoming game-phase message goes through uniform checks on the server:

1. **Peer is in a room with a live `GameSession`?** If not → `ERR_NOT_IN_GAME`.
2. **Peer's seat still belongs to them?** If the seat has become AI (disconnect, leave), reject → `ERR_NOT_IN_GAME`. This also handles "lingering message from a just-disconnected peer" races.
3. **Phase accepts this action?** `play_card` only during `PLAYER_TURN`/`TRICK_RESOLUTION`; `declare_trump` only during `TRUMP_SELECTION`; `next_round` only during `BETWEEN_ROUNDS`. Otherwise → `ERR_WRONG_PHASE`.
4. **Is it the sender's turn?** For `play_card`, sender's seat must equal `round_manager.current_player_seat`. For `declare_trump`, sender's seat must equal `trump_selector_seat`. For `next_round`, sender must be the room host. Failures: `ERR_NOT_YOUR_TURN` (or `ERR_NOT_HOST` from M1 for next-round).
5. **Is the card legal?** For `play_card`, card must be in the sender's hand and, if they hold any cards of the led suit, must match it. `GameSession` does this itself before calling `round_manager.play_card` — defence in depth. Fail → `ERR_INVALID_CARD`.

Failure sends `MSG_ERROR` only to the offending peer. Game state is not mutated. Other clients see nothing.

### Disconnect race conditions

ENet delivers messages in-order per peer. Two orderings within a single server tick are possible:

- **Play processes first, then disconnect.** Card goes on the table, game advances, then seat swaps to AI. `MSG_CARD_PLAYED` and `MSG_SEAT_TAKEN_OVER_BY_AI` both reach remaining humans in order.
- **Disconnect processes first, then a lingering message from the disconnected peer.** Validation step 2 catches it — the peer no longer owns any seat, message is dropped with an `MSG_ERROR` that ENet can't actually deliver.

### All humans disconnect

If a `handle_disconnect` or `handle_player_leave` call results in zero humans in `players[]`, `GameSession` destroys itself and `RoomManager` erases the `Room`. No broadcast (nobody to broadcast to).

### Host disconnects / host leaves mid-game

Same as M1's host-left rule, extended to the game phase. `handle_disconnect`/`handle_leave_room` detects `was_host`, destroys the `GameSession`, destroys the `Room`, broadcasts `MSG_ERROR { code: HOST_LEFT }` to all remaining peers. `game_table_ui.gd` gains the same `_on_error_received` handler that `room_waiting_ui.gd` already has so it can react identically when the error arrives mid-game.

### Server crash / server process dies

ENet's connection layer detects the dropped socket and fires `peer_disconnected` on every client within its keepalive timeout. `NetworkState._on_connection_state_changed` transitions to `DISCONNECTED`. `game_table_ui.gd`'s new error handler catches this state and force-returns to the main menu with a "Disconnected from server" toast.

### Client crash

Symmetrically: server's `peer_disconnected` fires after ENet timeout, seat becomes AI, game continues.

### Malformed or unknown messages

Same policy as M1: `main_server.gd` drops any packet that doesn't deserialize into a `Dictionary` with a known `type`. No error response, no log spam beyond the existing dev-time `push_warning`. The server never crashes on hostile input.

### Client-side error reaction taxonomy

| Server error | Client reaction |
|---|---|
| `NOT_YOUR_TURN`, `INVALID_CARD`, `WRONG_PHASE`, `NOT_IN_GAME` | Toast the message over the game table, stay in-game. |
| `NOT_HOST` | Toast, stay on the between-rounds screen. |
| `HOST_LEFT` | Toast, return to main menu. Same as M1. |
| Connection `DISCONNECTED` (transport event) | Toast "Disconnected from server", return to main menu. |

### Phase-transition races

Narrow windows exist where the server is `BETWEEN_ROUNDS` but the client is still showing the trick-display animation for the last trick. If a client sends something during this gap, the validation pipeline catches it — the client's UI shouldn't let it happen anyway, but defence in depth matters.

---

## Testing Strategy

No automated framework exists (M1 relied on manual Runs A–D), and Godot's test story is weak enough that M2 isn't the right place to set one up. Testing leans on manual scenarios with two targeted automated checks for logic that's hard to eyeball.

### Tier 1: Single-player regression (mandatory)

M2 touches `game_table_ui.gd` via the `game_source` refactor. Before any multiplayer test runs, single-player must be re-verified end-to-end:

1. Launch single-player, play one full round to a 7-book win.
2. Verify: dealing animation, trump selection UI, card highlighting on the human's turn, AI delays feel natural, trick resolution + book counter animate, win screen transitions correctly, "Next Round" rotates dealer properly.
3. Play at least two more rounds to exercise dealer rotation and session-wins tracking.
4. Verify: pause menu works, settings (animation speed) still affects pacing, trick history overlay still renders.
5. Run all three AI difficulties (Easy/Medium/Hard) for one full round each.

The refactor passes if a single-player session is indistinguishable from before M2. Fix any regression before moving on.

### Tier 2: Multiplayer smoke tests (mandatory)

Spin up the server (one instance bound to 9999), then spin up 1–3 additional client instances in separate terminals. Run each scenario and verify what's expected.

| Scenario | Setup | Verify |
|---|---|---|
| **A. Full 4-human round** | 1 server + 4 clients (Alice host, Bob, Carol, Dave). Host starts. | All 4 clients transition simultaneously. Random dealer. Trump selector's initial 5 cards visible only on their own screen. Trump UI renders only for the trump selector; others see "Foo is choosing trump…". Full deal completes. All 13 tricks play out — each `card_played` animates everywhere. Book counter increments in sync. Win screen at exactly 7 books. Session wins HUD shows `1:0` or `0:1`. |
| **B. 2-human + 2-AI round** | 1 server + 2 clients. Host starts with 2 seats filled. | Server fills seats 2 and 3 with `AIPlayer(MEDIUM)`. Waiting room and game table both show AI placeholders at those positions. AI seats act on their turns without client input. Round completes. |
| **C. Mid-round non-host disconnect** | 1 server + 3 clients. Kill one non-host client mid-trick-5. | Remaining two clients receive `SEAT_TAKEN_OVER_BY_AI` toast within ENet's timeout. Dropped seat continues via server AI. Round completes. |
| **D. Mid-round host disconnect** | 1 server + 3 clients. Kill the host. | Remaining two clients receive `HOST_LEFT` error, return to main menu. Server destroys `GameSession` and `Room`. Starting a new room works. |
| **E. Voluntary leave mid-game** | 1 server + 3 clients. Non-host presses Leave during a round. | Same visible outcome as disconnect (AI takes over), but the leaver's client transitions cleanly back to main menu. Leaver can re-enter a new room. |
| **F. Multi-round session loop** | 1 server + 2–4 clients. Play 3 full rounds via "Next Round". | Dealer rotates correctly (losing team, alternating within team on consecutive losses). Session wins HUD updates. Trump selector is always left of dealer. Each round clears per-round state. |
| **G. All humans leave** | 1 server + 2 clients. Start a round. Both non-AI players press Leave. | Server detects zero humans, destroys `GameSession` and `Room`. Leavers land on main menu. New rooms work. |
| **H. Server restart mid-game** | 1 server + 3 clients. Kill the server. | All clients see "Disconnected from server" toast, return to main menu. Reconnecting to a fresh server works. |
| **I. Illegal-action defence (optional)** | 1 server + 2 clients. Hacked build sends `MSG_PLAY_CARD` with a card not in hand. | Server rejects with `ERR_INVALID_CARD`; client toasts. Skip if hacked build is annoying to wire up. |

Scenarios A–H are mandatory. Scenario I is optional.

### Tier 3: Targeted automated checks (optional)

- **`tests/net/protocol_roundtrip.gd`** (~30 lines). Builds one message of each new `MSG_*` type with representative data, serialises via `var_to_bytes`, deserialises, asserts equality. Catches field-name typos. Run via `godot --headless --script tests/net/protocol_roundtrip.gd`.
- **`tests/client/net_game_view_apply.gd`** (~80 lines). Instantiates a `NetGameView`, feeds a scripted message sequence (session start → round starting → hand dealt → trump selection → trick events → round ended), asserts state fields match expected values after each event.

Both are "nice to have." If painful, cut or defer.

### Explicit non-goals for testing

- No load testing (single-room focus).
- No network chaos testing (trust the reliable channel).
- No AI quality benchmarking (same AIs as single-player).

---

## Open Questions

None. All product decisions were made during brainstorming:

1. **Scope** — full session loop + AI fills empty seats. Turn timer and reconnect deferred.
2. **Disconnect behavior** — AI takeover for non-host disconnects; host-left still collapses the room.
3. **Post-round flow** — host-driven "Next Round" button.
4. **AI difficulty** — hardcoded to `MEDIUM`.
5. **Client architecture** — parallel game source (`NetGameView` mirroring `RoundManager`'s API), selected over snapshot-based and mirrored-RoundManager alternatives.

The first two decisions are the load-bearing ones: everything else in the design follows from them. If either gets revisited, most of this spec gets rewritten.

---

## Dependencies

This spec assumes M1 is landed and merged. Specifically it depends on:

- `scripts/net/protocol.gd` with the M1 constants and `Protocol.msg(type, data)` helper.
- `autoloads/network_state.gd` with connection management, send/receive pipeline, and the M1 client-facing facades (`connect_to_server`, `create_room`, `join_room`, `leave_room`, `start_game`).
- `scripts/server/main_server.gd` with its polling loop, `Room`/`RoomManager` structure, and `_dispatch_outgoing` pattern.
- `scripts/ui/room_waiting_ui.gd` reacting to `NetworkState` signals.
- The existing `Bootstrap` autoload that detects server vs client role at startup.

None of these are being replaced, only extended.
