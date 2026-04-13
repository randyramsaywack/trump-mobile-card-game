# Multiplayer Milestone 2 — Authoritative Game Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the host's "Start Game" button run a full, server-authoritative round of Trump over the network — dealing, trump selection, tricks, round end, dealer rotation, and host-driven next round — for 2–4 humans with AI filling every empty or vacated seat.

**Architecture:** A new `GameSession` RefCounted class lives on the server per active room, wraps the existing single-player `RoundManager` unchanged, and bridges its signals to a `_pending_events: Array[(peer_id, msg)]` buffer. Client-side, a new `NetGameView` mirrors `RoundManager`'s public API and signals so the existing `game_table_ui.gd` works in multiplayer after a mechanical `round_manager → game_source` swap on `GameState`. Every new message follows the M1 dict-on-ENet wire format; private cards are tailored per recipient.

**Tech Stack:** Godot 4.6.2, GDScript, `ENetMultiplayerPeer` (raw `put_packet`/`get_packet`), autoloads, the `RoundManager`/`Player`/`AIPlayer` classes inherited from single-player.

**Verification style:** No automated test framework exists in the project. Every task ends with a manual Godot-editor run and explicit checks against the debug output / screen. The final task walks through the full SP regression + the 8 mandatory MP scenarios from the spec.

---

## File Map

### New files

| Path | Responsibility |
| --- | --- |
| `scripts/server/game_session.gd` | Server per-room game-loop owner. Wraps `RoundManager`, tracks `players`/`peer_to_seat`/`session_wins`/dealer rotation, bridges RM signals to a `_pending_events` tuple buffer, and exposes `handle_*` methods matching `RoomManager`'s shape. |
| `scripts/net/net_game_view.gd` | Client-side mirror of `RoundManager`. Same signal names and public state fields as `RoundManager`; `apply_event(msg)` mutates state and re-emits. Only the local player's hand holds real `Card` objects — everyone else's is a count. |

### Modified files

| Path | Change |
| --- | --- |
| `scripts/net/protocol.gd` | Add 4 new C→S + 10 new S→C message type constants, 4 new `ERR_*` codes + messages, `card_to_dict`/`dict_to_card` helpers. |
| `scripts/server/room.gd` | `State` enum gains `IN_GAME` and `BETWEEN_ROUNDS`. New `game_session: GameSession` field (null until start). |
| `scripts/server/room_manager.gd` | `handle_start_game` stops being a stub — builds `GameSession`, drives it through `start_first_round`. New delegating handlers `handle_play_card`, `handle_declare_trump`, `handle_next_round`. `handle_leave_room`/`handle_disconnect` branch on whether a live `GameSession` exists. Room is destroyed when `game_session.has_humans()` is false. New helper `tick(delta)` that fans out ticks to every active session. |
| `scripts/server/main_server.gd` | Dispatch cases for the 4 new C→S message types. `_process(delta)` now calls `_rooms.tick(delta)` and dispatches the returned outgoing batch every frame. |
| `autoloads/network_state.gd` | New client facades `play_card(card)`, `declare_trump(suit)`, `next_round()`. `_handle_server_message` grows cases for every new S→C type. `MSG_SESSION_START` creates a fresh `NetGameView`, assigns `GameState.game_source`, and swaps scenes to `game_table.tscn`. All other in-game messages forward to `game_source.apply_event(msg)`. |
| `autoloads/game_state.gd` | New field `var game_source: Node = null`. `get_round_manager()` stays, but UI code uses `game_source`. `_process` ticks `round_manager` only in single-player mode. |
| `scripts/ui/game_table_ui.gd` | Mechanical refactor: every `GameState.round_manager.X` / `GameState.get_round_manager().X` read becomes `GameState.game_source.X`. Human action paths (card tap, trump pick, next round) branch: single-player calls `round_manager` directly as before; multiplayer calls the new `NetworkState` facades. New `_on_error_received` handler to catch mid-game `HOST_LEFT` / disconnect. |
| `scripts/ui/room_waiting_ui.gd` | Delete the `_TOAST_NOT_IMPLEMENTED` stub. `game_starting` signal is no longer used by this screen — scene change is driven by `MSG_SESSION_START` in `NetworkState`. |

### Out-of-scope reminders (do NOT do these in this plan)

- No turn timer, no forced-AI-on-timeout.
- No reconnect, no rejoin, no seat hand-back when a peer returns.
- No host migration. Host leave/disconnect still collapses the room.
- No configurable server address — still hardcoded `127.0.0.1:9999`.
- No automated test framework setup. Manual verification only.
- No networked pause. Settings overlay is visual-only in MP.
- No changes to single-player stat tracking, AI difficulty UI, or deck/card/hand/trick internals.

---

## Task 1: Protocol extensions

**Files:**
- Modify: `scripts/net/protocol.gd`

- [ ] **Step 1: Add new message type constants**

Open `scripts/net/protocol.gd`. Under the existing `# ── Client → Server` section, append the 4 new C→S constants. Under `# ── Server → Client`, append the 10 new S→C constants. The full new sections should read:

```gdscript
# ── Client → Server ───────────────────────────────────────────────────────────
const MSG_HELLO := "hello"
const MSG_CREATE_ROOM := "create_room"
const MSG_JOIN_ROOM := "join_room"
const MSG_LEAVE_ROOM := "leave_room"
const MSG_START_GAME := "start_game"
const MSG_PLAY_CARD := "play_card"
const MSG_DECLARE_TRUMP := "declare_trump"
const MSG_NEXT_ROUND := "next_round"

# ── Server → Client ───────────────────────────────────────────────────────────
const MSG_WELCOME := "welcome"
const MSG_ROOM_JOINED := "room_joined"
const MSG_ROOM_STATE := "room_state"
const MSG_ERROR := "error"
const MSG_GAME_STARTING := "game_starting"
const MSG_SESSION_START := "session_start"
const MSG_ROUND_STARTING := "round_starting"
const MSG_HAND_DEALT := "hand_dealt"
const MSG_TRUMP_SELECTION_NEEDED := "trump_selection_needed"
const MSG_TRUMP_DECLARED := "trump_declared"
const MSG_TURN_STARTED := "turn_started"
const MSG_CARD_PLAYED := "card_played"
const MSG_TRICK_COMPLETED := "trick_completed"
const MSG_ROUND_ENDED := "round_ended"
const MSG_SEAT_TAKEN_OVER_BY_AI := "seat_taken_over_by_ai"
```

Note `MSG_GAME_STARTING` stays for now so existing `room_waiting_ui.gd` compiles — Task 15 removes the reference.

- [ ] **Step 2: Add new error codes + messages**

Append the 4 new error codes and their human-readable messages. The updated sections read:

```gdscript
# ── Error codes ───────────────────────────────────────────────────────────────
const ERR_ROOM_NOT_FOUND := "ROOM_NOT_FOUND"
const ERR_ROOM_FULL := "ROOM_FULL"
const ERR_INVALID_ROOM_CODE := "INVALID_ROOM_CODE"
const ERR_NOT_HOST := "NOT_HOST"
const ERR_NOT_IN_ROOM := "NOT_IN_ROOM"
const ERR_HOST_LEFT := "HOST_LEFT"
const ERR_ALREADY_IN_ROOM := "ALREADY_IN_ROOM"
const ERR_ROOM_STARTED := "ROOM_STARTED"
const ERR_NOT_YOUR_TURN := "NOT_YOUR_TURN"
const ERR_INVALID_CARD := "INVALID_CARD"
const ERR_WRONG_PHASE := "WRONG_PHASE"
const ERR_NOT_IN_GAME := "NOT_IN_GAME"

# ── Error messages (human-readable) ───────────────────────────────────────────
const ERROR_MESSAGES := {
    ERR_ROOM_NOT_FOUND: "Room code not found.",
    ERR_ROOM_FULL: "Room is full.",
    ERR_INVALID_ROOM_CODE: "Room code must be 6 characters.",
    ERR_NOT_HOST: "Only the host can start the game.",
    ERR_NOT_IN_ROOM: "You must join a room first.",
    ERR_HOST_LEFT: "Host left the room.",
    ERR_ALREADY_IN_ROOM: "You are already in a room.",
    ERR_ROOM_STARTED: "Game already in progress.",
    ERR_NOT_YOUR_TURN: "It's not your turn.",
    ERR_INVALID_CARD: "That card can't be played.",
    ERR_WRONG_PHASE: "That action isn't allowed right now.",
    ERR_NOT_IN_GAME: "The game hasn't started yet.",
}
```

- [ ] **Step 3: Add card serialization helpers**

At the bottom of the file, below the existing `static func msg(...)`, add:

```gdscript
## Serialize a Card to the wire-format dict {suit:int, rank:int}.
static func card_to_dict(card: Card) -> Dictionary:
    return {"suit": int(card.suit), "rank": int(card.rank)}

## Deserialize a {suit, rank} dict back into a Card. Returns null on bad input.
static func dict_to_card(d: Dictionary) -> Card:
    if not d.has("suit") or not d.has("rank"):
        return null
    return Card.new(int(d["suit"]) as Card.Suit, int(d["rank"]) as Card.Rank)

## Build a list of card dicts from an Array[Card].
static func cards_to_dicts(cards: Array) -> Array:
    var out: Array = []
    for c in cards:
        if c is Card:
            out.append(card_to_dict(c as Card))
    return out
```

- [ ] **Step 4: Verify the file parses**

Run: `godot --headless --path . --check-only 2>&1 | head`
Expected: no parser errors referencing `scripts/net/protocol.gd`. If the flag is unsupported, open the Godot editor; the "Parse Error" tray should stay empty for this file.

- [ ] **Step 5: Commit**

```bash
git add scripts/net/protocol.gd
git commit -m "feat(mp): extend wire protocol for game loop (M2)"
```

---

## Task 2: GameSession skeleton + signal bridge

**Files:**
- Create: `scripts/server/game_session.gd`

- [ ] **Step 1: Create the file with its class header and state**

Create `scripts/server/game_session.gd` with this initial skeleton. This task adds only the container and the signal subscriptions; handlers in later tasks populate the event buffer.

```gdscript
class_name GameSession
extends RefCounted

## Server-only. One per active room. Wraps a RoundManager (reused unchanged
## from single-player) and translates its signals into per-recipient network
## messages. Every mutation method returns a list of (peer_id, message_dict)
## pairs for the caller (room_manager.gd → main_server.gd) to actually send.

const _TEAM_SEATS := {0: [0, 2], 1: [1, 3]}

var code: String = ""                    # room code (for logging)
var round_manager: RoundManager = null
var players: Array[Player] = []          # indexed by seat 0..3
var peer_to_seat: Dictionary = {}        # peer_id → seat_index (human seats only)
var seat_display_names: Array[String] = ["", "", "", ""]
var session_wins: Array[int] = [0, 0]    # [team0, team1]
var dealer_seat: int = 0
var round_number: int = 0
## Per-team dealer tracking (mirrors GameState._team_dealer). Alternates
## within the losing team on consecutive losses.
var _team_dealer: Dictionary = {0: 0, 1: 1}

## Tuple buffer: each entry is [peer_id:int, message:Dictionary]. Signal
## handlers append here; public methods return a drained copy to the caller.
var _pending_events: Array = []

func _init(room_code: String) -> void:
    code = room_code
    round_manager = RoundManager.new()
    round_manager.hand_dealt.connect(_on_hand_dealt)
    round_manager.trump_selection_needed.connect(_on_trump_selection_needed)
    round_manager.trump_declared.connect(_on_trump_declared)
    round_manager.turn_started.connect(_on_turn_started)
    round_manager.card_played_signal.connect(_on_card_played)
    round_manager.trick_completed.connect(_on_trick_completed)
    round_manager.round_ended.connect(_on_round_ended)

# ── Public API (called by RoomManager) ────────────────────────────────────────

## Returns true while at least one seat is owned by a real (non-AI) peer.
func has_humans() -> bool:
    return not peer_to_seat.is_empty()

## Drain and return the pending event buffer. Clears it as a side effect.
func _drain() -> Array:
    var out := _pending_events
    _pending_events = []
    return out

# ── Signal handlers (RoundManager → wire) ─────────────────────────────────────
# These are stubs for Task 2. Later tasks implement the bodies.

func _on_hand_dealt(_seat_index: int, _cards: Array) -> void:
    pass

func _on_trump_selection_needed(_seat_index: int, _initial_cards: Array) -> void:
    pass

func _on_trump_declared(_suit: int) -> void:
    pass

func _on_turn_started(_seat_index: int, _valid_cards: Array) -> void:
    pass

func _on_card_played(_seat_index: int, _card: Card) -> void:
    pass

func _on_trick_completed(_winner_seat: int, _books: Array, _books_by_seat: Array) -> void:
    pass

func _on_round_ended(_winning_team: int) -> void:
    pass

# ── Helpers ───────────────────────────────────────────────────────────────────

func _human_peers() -> Array:
    return peer_to_seat.keys()

func _seat_for_peer(peer_id: int) -> int:
    return int(peer_to_seat.get(peer_id, -1))

func _append_to_all(msg: Dictionary) -> void:
    for pid in peer_to_seat.keys():
        _pending_events.append([int(pid), msg])

func _append_to_one(peer_id: int, msg: Dictionary) -> void:
    _pending_events.append([int(peer_id), msg])

func _err(peer_id: int, code: String) -> Array:
    return [[peer_id, Protocol.msg(Protocol.MSG_ERROR, {
        "code": code,
        "message": String(Protocol.ERROR_MESSAGES.get(code, code)),
    })]]
```

- [ ] **Step 2: Open the editor, verify no parse errors**

Run the Godot editor. The parse-error tray should stay empty for `scripts/server/game_session.gd`.

- [ ] **Step 3: Commit**

```bash
git add scripts/server/game_session.gd
git commit -m "feat(mp): add GameSession skeleton with signal bridge"
```

---

## Task 3: GameSession player setup + start_first_round

**Files:**
- Modify: `scripts/server/game_session.gd`

- [ ] **Step 1: Add the seat-setup method**

Above `# ── Signal handlers`, add:

```gdscript
## Called once at Start Game. `room_players` is the Array[Dictionary] from
## `Room.players`, each of shape {peer_id, username, seat, is_host}. Empty
## seats are filled with AIPlayer(MEDIUM); AI display names follow the
## single-player convention (West / North / East) for any unfilled seat.
func setup_players(room_players: Array) -> void:
    const AI_SEAT_NAMES := ["You", "West", "North", "East"]
    players = [null, null, null, null]
    seat_display_names = ["", "", "", ""]
    peer_to_seat = {}
    for entry in room_players:
        var seat := int(entry["seat"])
        var username := String(entry["username"])
        var peer_id := int(entry["peer_id"])
        players[seat] = Player.new(seat, username, true)
        seat_display_names[seat] = username
        peer_to_seat[peer_id] = seat
    for s in 4:
        if players[s] == null:
            var ai := AIPlayer.new(s, AI_SEAT_NAMES[s])
            ai.difficulty = AIPlayer.Difficulty.MEDIUM
            players[s] = ai
            seat_display_names[s] = AI_SEAT_NAMES[s]
```

- [ ] **Step 2: Add the session-start + round-start methods**

Below `setup_players`, add:

```gdscript
## Appends the `session_start` fan-out and starts round 1. Returns the
## drained buffer so the caller can ship it to the wire.
func start_first_round() -> Array:
    dealer_seat = randi() % 4
    _team_dealer[0] = 0 if dealer_seat in [0, 2] else 0
    _team_dealer[1] = 1 if dealer_seat in [1, 3] else 1
    # Whichever team the initial random dealer belongs to, that's that team's
    # current dealer. The other team gets its lower-index seat as a default.
    var starting_team := 0 if dealer_seat in [0, 2] else 1
    _team_dealer[starting_team] = dealer_seat
    _team_dealer[1 - starting_team] = 0 if starting_team == 1 else 1
    _append_session_start()
    _start_round()
    return _drain()

func _append_session_start() -> void:
    var seats: Array = []
    for s in 4:
        var p := players[s]
        seats.append({
            "seat": s,
            "username": seat_display_names[s],
            "is_ai": p is AIPlayer,
        })
    var msg := Protocol.msg(Protocol.MSG_SESSION_START, {
        "seats": seats,
        "starting_dealer_seat": dealer_seat,
        "session_wins": session_wins.duplicate(),
    })
    _append_to_all(msg)

func _start_round() -> void:
    round_number += 1
    _append_to_all(Protocol.msg(Protocol.MSG_ROUND_STARTING, {
        "dealer_seat": dealer_seat,
        "trump_selector_seat": (dealer_seat + 1) % 4,
        "round_number": round_number,
    }))
    round_manager.start_round(players, dealer_seat)
```

- [ ] **Step 3: Implement `_on_hand_dealt` with per-recipient tailoring**

Replace the stub `_on_hand_dealt` body with:

```gdscript
func _on_hand_dealt(seat_index: int, cards: Array) -> void:
    var public_data := {"seat_index": seat_index, "count": int(cards.size())}
    var public_msg := Protocol.msg(Protocol.MSG_HAND_DEALT, public_data)
    # Find the human peer (if any) that owns this seat — they get the private
    # copy with the real cards. Everyone else gets the count-only public copy.
    var owner_peer := -1
    for pid in peer_to_seat.keys():
        if int(peer_to_seat[pid]) == seat_index:
            owner_peer = int(pid)
            break
    for pid in peer_to_seat.keys():
        var peer := int(pid)
        if peer == owner_peer:
            var private_data := {
                "seat_index": seat_index,
                "count": int(cards.size()),
                "cards": Protocol.cards_to_dicts(cards),
            }
            _pending_events.append([peer, Protocol.msg(Protocol.MSG_HAND_DEALT, private_data)])
        else:
            _pending_events.append([peer, public_msg])
```

- [ ] **Step 4: Implement the remaining bridge handlers**

Replace the `_on_trump_selection_needed`, `_on_trump_declared`, and `_on_turn_started` stubs:

```gdscript
func _on_trump_selection_needed(seat_index: int, _initial_cards: Array) -> void:
    _append_to_all(Protocol.msg(Protocol.MSG_TRUMP_SELECTION_NEEDED, {
        "seat_index": seat_index,
    }))

func _on_trump_declared(suit: int) -> void:
    _append_to_all(Protocol.msg(Protocol.MSG_TRUMP_DECLARED, {"suit": int(suit)}))

func _on_turn_started(seat_index: int, _valid_cards: Array) -> void:
    _append_to_all(Protocol.msg(Protocol.MSG_TURN_STARTED, {"seat_index": seat_index}))
```

- [ ] **Step 5: Verify the file parses**

Open the Godot editor. No parse errors in `game_session.gd`.

- [ ] **Step 6: Commit**

```bash
git add scripts/server/game_session.gd
git commit -m "feat(mp): GameSession setup_players + start_first_round with deal bridge"
```

---

## Task 4: GameSession handle_declare_trump + handle_play_card

**Files:**
- Modify: `scripts/server/game_session.gd`

- [ ] **Step 1: Add `handle_declare_trump`**

Below `start_first_round` in the `# ── Public API` section, add:

```gdscript
func handle_declare_trump(peer_id: int, data: Dictionary) -> Array:
    var seat := _seat_for_peer(peer_id)
    if seat < 0:
        return _err(peer_id, Protocol.ERR_NOT_IN_GAME)
    if round_manager.state != RoundManager.RoundState.TRUMP_SELECTION:
        return _err(peer_id, Protocol.ERR_WRONG_PHASE)
    if seat != round_manager.trump_selector_seat:
        return _err(peer_id, Protocol.ERR_NOT_YOUR_TURN)
    var suit_int := int(data.get("suit", -1))
    if suit_int < 0 or suit_int > 3:
        return _err(peer_id, Protocol.ERR_INVALID_CARD)
    round_manager.declare_trump(suit_int as Card.Suit)
    return _drain()
```

- [ ] **Step 2: Add `handle_play_card` with full validation pipeline**

Below `handle_declare_trump`, add:

```gdscript
func handle_play_card(peer_id: int, data: Dictionary) -> Array:
    var seat := _seat_for_peer(peer_id)
    if seat < 0:
        return _err(peer_id, Protocol.ERR_NOT_IN_GAME)
    if round_manager.state != RoundManager.RoundState.PLAYER_TURN:
        return _err(peer_id, Protocol.ERR_WRONG_PHASE)
    if seat != round_manager.current_player_seat:
        return _err(peer_id, Protocol.ERR_NOT_YOUR_TURN)
    var card_dict := data.get("card", {}) as Dictionary
    var requested := Protocol.dict_to_card(card_dict)
    if requested == null:
        return _err(peer_id, Protocol.ERR_INVALID_CARD)
    # Find the actual Card instance in the player's hand matching suit+rank —
    # RoundManager.play_card uses object identity for removal.
    var owned: Card = null
    for c in players[seat].hand.cards:
        if c.suit == requested.suit and c.rank == requested.rank:
            owned = c
            break
    if owned == null:
        return _err(peer_id, Protocol.ERR_INVALID_CARD)
    # Defence in depth: reject cards that violate follow-suit.
    var valid := players[seat].hand.get_valid_cards(
        round_manager.current_trick.led_suit,
        round_manager.trump_suit,
    )
    if owned not in valid:
        return _err(peer_id, Protocol.ERR_INVALID_CARD)
    round_manager.play_card(seat, owned)
    return _drain()
```

- [ ] **Step 3: Implement the `_on_card_played` and `_on_trick_completed` bridges**

Replace the stubs:

```gdscript
func _on_card_played(seat_index: int, card: Card) -> void:
    _append_to_all(Protocol.msg(Protocol.MSG_CARD_PLAYED, {
        "seat_index": seat_index,
        "card": Protocol.card_to_dict(card),
    }))

func _on_trick_completed(winner_seat: int, books: Array, books_by_seat: Array) -> void:
    _append_to_all(Protocol.msg(Protocol.MSG_TRICK_COMPLETED, {
        "winner_seat": winner_seat,
        "books": books.duplicate(),
        "books_by_seat": books_by_seat.duplicate(),
    }))
```

- [ ] **Step 4: Verify parse**

Open the editor. No errors in `game_session.gd`.

- [ ] **Step 5: Commit**

```bash
git add scripts/server/game_session.gd
git commit -m "feat(mp): GameSession trump/play action handlers + trick bridge"
```

---

## Task 5: GameSession round-end, dealer rotation, next-round

**Files:**
- Modify: `scripts/server/game_session.gd`

- [ ] **Step 1: Add a `room_state_between_rounds` flag**

Near the top of the file with the other `var` declarations, add:

```gdscript
## Set true when RoundManager finishes a round; cleared when host calls
## handle_next_round. Gates `play_card`/`declare_trump` during the window
## where the client is showing the win screen.
var between_rounds: bool = false
```

- [ ] **Step 2: Implement the `_on_round_ended` bridge**

Replace the stub:

```gdscript
func _on_round_ended(winning_team: int) -> void:
    session_wins[winning_team] += 1
    _rotate_dealer(1 - winning_team)
    between_rounds = true
    var trick_history_serialized := _serialize_trick_history()
    _append_to_all(Protocol.msg(Protocol.MSG_ROUND_ENDED, {
        "winning_team": winning_team,
        "session_wins": session_wins.duplicate(),
        "trick_history": trick_history_serialized,
    }))

## Rotate within the losing team's two seats. Mirrors the logic in
## GameState._rotate_dealer (autoloads/game_state.gd lines 72–81).
func _rotate_dealer(losing_team: int) -> void:
    var current: int = int(_team_dealer[losing_team])
    var team_seats: Array = _TEAM_SEATS[losing_team]
    var other_seat: int = int(team_seats[1]) if current == int(team_seats[0]) else int(team_seats[0])
    _team_dealer[losing_team] = other_seat
    dealer_seat = other_seat

func _serialize_trick_history() -> Array:
    var out: Array = []
    for entry in round_manager.trick_history:
        var cards_played: Array = []
        for cp in entry["cards_played"]:
            cards_played.append({
                "position": cp["position"],
                "player": cp["player"],
                "card": Protocol.card_to_dict(cp["card"]),
            })
        var winning_card := Protocol.card_to_dict(entry["winning_card"])
        out.append({
            "trick_number": entry["trick_number"],
            "winning_team": entry["winning_team"],
            "winning_card": winning_card,
            "cards_played": cards_played,
        })
    return out
```

- [ ] **Step 3: Add `handle_next_round`**

Below `handle_play_card` in the Public API section, add:

```gdscript
## Host-only. Starts the next round with the rotated dealer seat.
func handle_next_round(peer_id: int, is_host: bool) -> Array:
    if _seat_for_peer(peer_id) < 0:
        return _err(peer_id, Protocol.ERR_NOT_IN_GAME)
    if not is_host:
        return _err(peer_id, Protocol.ERR_NOT_HOST)
    if not between_rounds:
        return _err(peer_id, Protocol.ERR_WRONG_PHASE)
    between_rounds = false
    _start_round()
    return _drain()
```

- [ ] **Step 4: Guard handle_play_card/declare_trump while between_rounds**

Edit the first lines of `handle_declare_trump` and `handle_play_card` to reject actions during the between-rounds window. Right after the `seat < 0` check in each:

```gdscript
    if between_rounds:
        return _err(peer_id, Protocol.ERR_WRONG_PHASE)
```

- [ ] **Step 5: Verify parse + commit**

Open the editor, confirm no parse errors, then:

```bash
git add scripts/server/game_session.gd
git commit -m "feat(mp): GameSession round end, dealer rotation, next round"
```

---

## Task 6: GameSession disconnect / leave / AI takeover + tick

**Files:**
- Modify: `scripts/server/game_session.gd`

- [ ] **Step 1: Add `tick(delta)`**

In the Public API section, add:

```gdscript
## Called every frame by RoomManager.tick → main_server._process.
func tick(delta: float) -> Array:
    round_manager.tick(delta)
    return _drain()
```

- [ ] **Step 2: Add `handle_player_disconnect` and `handle_player_leave`**

These share a helper. Add both in the Public API section:

```gdscript
## Called when a non-host peer drops connection. Swaps the peer's seat to
## AI and broadcasts the takeover to remaining humans. Caller is responsible
## for deciding whether the room collapses (host-left) — this method handles
## only non-host cases.
func handle_player_disconnect(peer_id: int) -> Array:
    return _swap_to_ai(peer_id, "disconnect")

## Called when a non-host peer sends leave_room while a game is live.
func handle_player_leave(peer_id: int) -> Array:
    return _swap_to_ai(peer_id, "left")

func _swap_to_ai(peer_id: int, reason: String) -> Array:
    var seat := _seat_for_peer(peer_id)
    if seat < 0:
        return []
    var old := players[seat] as Player
    var display_name := old.display_name
    var ai := AIPlayer.new(seat, display_name)
    ai.difficulty = AIPlayer.Difficulty.MEDIUM
    # Transfer the hand and any mid-trick state by reference.
    ai.hand = old.hand
    players[seat] = ai
    # RoundManager reads `players` by reference through its own array, but
    # its internal list was passed by reference in start_round, so mutate
    # that one too to keep the two in sync.
    if round_manager.players.size() > seat:
        round_manager.players[seat] = ai
    peer_to_seat.erase(peer_id)
    seat_display_names[seat] = display_name
    _append_to_all(Protocol.msg(Protocol.MSG_SEAT_TAKEN_OVER_BY_AI, {
        "seat_index": seat,
        "reason": reason,
        "display_name": display_name,
    }))
    # If the swapped-in AI is the current actor, schedule its action so
    # RoundManager doesn't stall. RoundManager.tick already drives AI timers
    # once _schedule_ai_action primes _ai_pending.
    var rm_state := round_manager.state
    if rm_state == RoundManager.RoundState.PLAYER_TURN and round_manager.current_player_seat == seat:
        round_manager.call("_schedule_ai_action")
    elif rm_state == RoundManager.RoundState.TRUMP_SELECTION and round_manager.trump_selector_seat == seat:
        round_manager.call("_schedule_ai_action")
    return _drain()
```

- [ ] **Step 3: Verify parse + commit**

```bash
git add scripts/server/game_session.gd
git commit -m "feat(mp): GameSession AI takeover on disconnect/leave + tick loop"
```

---

## Task 7: Room.gd state + field, RoomManager.handle_start_game

**Files:**
- Modify: `scripts/server/room.gd`
- Modify: `scripts/server/room_manager.gd`

- [ ] **Step 1: Extend the Room state enum and add the session field**

In `scripts/server/room.gd`, change the `State` enum and add one field:

```gdscript
enum State { WAITING, STARTING, IN_GAME, BETWEEN_ROUNDS }

var code: String = ""
var host_id: int = 0
var state: int = State.WAITING
var game_session: GameSession = null
## Array of player dicts: {peer_id:int, username:String, seat:int, is_host:bool}
var players: Array = []
```

No other changes to `room.gd` in this step.

- [ ] **Step 2: Rewrite `RoomManager.handle_start_game` to build a live GameSession**

In `scripts/server/room_manager.gd`, replace the existing body of `handle_start_game`:

```gdscript
func handle_start_game(peer_id: int) -> Array:
    var room := room_for_peer(peer_id)
    if room == null:
        return [_err_to(peer_id, Protocol.ERR_NOT_IN_ROOM)]
    if room.host_id != peer_id:
        return [_err_to(peer_id, Protocol.ERR_NOT_HOST)]
    if room.players.size() < 2:
        return [_err_to(peer_id, Protocol.ERR_ROOM_FULL)]
    if room.state != Room.State.WAITING:
        return [_err_to(peer_id, Protocol.ERR_ROOM_STARTED)]
    room.state = Room.State.IN_GAME
    room.game_session = GameSession.new(room.code)
    room.game_session.setup_players(room.players)
    # Keep the M1 game_starting broadcast for parity — clients currently
    # ignore it but it still confirms the transition at the protocol level.
    var out: Array = []
    for p in room.players:
        out.append([int(p["peer_id"]), Protocol.msg(Protocol.MSG_GAME_STARTING)])
    out.append_array(room.game_session.start_first_round())
    return out
```

The existing 2-human minimum was a client-side gate in M1; the server enforcement above makes it a hard protocol rule. Clients that shipped M1 already block Start below 2 humans.

- [ ] **Step 3: Run the editor, verify parse**

Load the Godot editor. No parse errors in `room.gd` or `room_manager.gd`.

- [ ] **Step 4: Commit**

```bash
git add scripts/server/room.gd scripts/server/room_manager.gd
git commit -m "feat(mp): RoomManager builds GameSession on start_game"
```

---

## Task 8: RoomManager — game-action delegators + disconnect/leave branches + tick

**Files:**
- Modify: `scripts/server/room_manager.gd`

- [ ] **Step 1: Add the delegating action handlers**

Append these three methods to `room_manager.gd`:

```gdscript
# ── Game-loop delegators ──────────────────────────────────────────────────────

func handle_play_card(peer_id: int, data: Dictionary) -> Array:
    var room := room_for_peer(peer_id)
    if room == null or room.game_session == null:
        return [_err_to(peer_id, Protocol.ERR_NOT_IN_GAME)]
    return room.game_session.handle_play_card(peer_id, data)

func handle_declare_trump(peer_id: int, data: Dictionary) -> Array:
    var room := room_for_peer(peer_id)
    if room == null or room.game_session == null:
        return [_err_to(peer_id, Protocol.ERR_NOT_IN_GAME)]
    return room.game_session.handle_declare_trump(peer_id, data)

func handle_next_round(peer_id: int) -> Array:
    var room := room_for_peer(peer_id)
    if room == null or room.game_session == null:
        return [_err_to(peer_id, Protocol.ERR_NOT_IN_GAME)]
    return room.game_session.handle_next_round(peer_id, room.host_id == peer_id)
```

- [ ] **Step 2: Branch the existing leave/disconnect paths**

Replace `handle_leave_room` and `handle_disconnect` with versions that branch on whether the room has a live `game_session`:

```gdscript
func handle_leave_room(peer_id: int) -> Array:
    var room := room_for_peer(peer_id)
    if room == null:
        return []
    # Host leaving always collapses the room, even mid-game.
    if room.host_id == peer_id:
        return _remove_peer_from_room(peer_id, room)
    # Non-host during an active game: swap seat to AI instead of removing.
    if room.game_session != null:
        return _on_non_host_exit(room, peer_id, "left")
    return _remove_peer_from_room(peer_id, room)

func handle_disconnect(peer_id: int) -> Array:
    _usernames.erase(peer_id)
    var room := room_for_peer(peer_id)
    if room == null:
        return []
    if room.host_id == peer_id:
        return _remove_peer_from_room(peer_id, room)
    if room.game_session != null:
        return _on_non_host_exit(room, peer_id, "disconnect")
    return _remove_peer_from_room(peer_id, room)

## Shared path for non-host disconnect or voluntary leave during an active
## game. Swaps the seat to AI. If zero humans remain, destroys the room.
func _on_non_host_exit(room: Room, peer_id: int, reason: String) -> Array:
    var out: Array
    if reason == "disconnect":
        out = room.game_session.handle_player_disconnect(peer_id)
    else:
        out = room.game_session.handle_player_leave(peer_id)
    _peer_to_room.erase(peer_id)
    # Keep room.players in sync — the seat entry becomes "AI" with the old
    # username but zero peer_id so future lookups can't match.
    for i in room.players.size():
        if int(room.players[i]["peer_id"]) == peer_id:
            room.players[i]["peer_id"] = 0
            break
    if not room.game_session.has_humans():
        _rooms.erase(room.code)
    return out
```

- [ ] **Step 3: Add `tick(delta)` to RoomManager**

Append the frame-driven session tick:

```gdscript
## Called every frame by main_server._process. Drives every active game
## session so AI delays, trick display countdowns, and other async events
## produce outgoing messages.
func tick(delta: float) -> Array:
    var out: Array = []
    for code in _rooms.keys():
        var room: Room = _rooms[code]
        if room.game_session != null:
            out.append_array(room.game_session.tick(delta))
    return out
```

- [ ] **Step 4: Verify parse + commit**

Load the editor. No parse errors.

```bash
git add scripts/server/room_manager.gd
git commit -m "feat(mp): RoomManager delegators, in-game leave branch, session tick"
```

---

## Task 9: main_server — dispatch new C→S types + frame tick

**Files:**
- Modify: `scripts/server/main_server.gd`

- [ ] **Step 1: Add dispatch cases for the 4 new C→S types**

Inside the `match type:` block of `_handle(sender, msg)`, below the existing `MSG_START_GAME` arm, add three more arms. The updated match block:

```gdscript
    match type:
        Protocol.MSG_HELLO:
            _handle_hello(sender, data)
        Protocol.MSG_CREATE_ROOM:
            _require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_create_room(sender)))
        Protocol.MSG_JOIN_ROOM:
            _require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_join_room(sender, data)))
        Protocol.MSG_LEAVE_ROOM:
            _require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_leave_room(sender)))
        Protocol.MSG_START_GAME:
            _require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_start_game(sender)))
        Protocol.MSG_PLAY_CARD:
            _require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_play_card(sender, data)))
        Protocol.MSG_DECLARE_TRUMP:
            _require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_declare_trump(sender, data)))
        Protocol.MSG_NEXT_ROUND:
            _require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_next_round(sender)))
        _:
            _log("DROP peer=%d unknown type=%s" % [sender, type])
```

- [ ] **Step 2: Drive the session tick each frame**

Update `_process(_delta)` to take a real `delta` and drain session events before reading new packets:

```gdscript
func _process(delta: float) -> void:
    if _peer == null:
        return
    # Drain any outgoing messages accumulated since last frame by active
    # game sessions (AI plays, trick display timer transitions, etc.).
    _dispatch_outgoing(_rooms.tick(delta))
    _peer.poll()
    while _peer.get_available_packet_count() > 0:
        var sender := _peer.get_packet_peer()
        var bytes := _peer.get_packet()
        var msg = bytes_to_var(bytes)
        if typeof(msg) != TYPE_DICTIONARY:
            _log("DROP peer=%d (non-dict packet)" % sender)
            continue
        _handle(sender, msg)
```

- [ ] **Step 3: Launch the editor and run `scenes/server_main.tscn`**

Run: in the Godot editor, open `scenes/server_main.tscn` and press F6.
Expected: the server window title shows `Trump — SERVER :9999` and the debug label shows `Server listening on port 9999`. No errors in the Output panel.

- [ ] **Step 4: Commit**

```bash
git add scripts/server/main_server.gd
git commit -m "feat(mp): main_server dispatch game actions + tick sessions"
```

---

## Task 10: NetGameView — client-side RoundManager mirror

**Files:**
- Create: `scripts/net/net_game_view.gd`

- [ ] **Step 1: Create the file with signals + state fields**

Create `scripts/net/net_game_view.gd` with this full contents. Signal shapes and field names are chosen to exactly match `scripts/round_manager.gd` so `game_table_ui.gd` binds against either type.

```gdscript
class_name NetGameView
extends Node

## Client-side mirror of RoundManager. Holds whatever authoritative state the
## server has told us so far, re-emits matching signals, and computes only
## the local player's valid-card highlighting (everything else is sent).

signal hand_dealt(seat_index: int, cards: Array)
signal trump_selection_needed(seat_index: int, initial_cards: Array)
signal trump_declared(suit: Card.Suit)
signal turn_started(seat_index: int, valid_cards: Array)
signal card_played_signal(seat_index: int, card: Card)
signal trick_completed(winner_seat: int, books: Array, books_by_seat: Array)
signal round_ended(winning_team: int)
## Extra NetGameView-only signals the UI subscribes to for MP-specific events.
signal seat_taken_over_by_ai(seat_index: int, display_name: String, reason: String)
signal round_starting(dealer_seat: int, trump_selector_seat: int, round_number: int)

# Mirror of RoundManager's RoundState enum.
enum RoundState {
    IDLE,
    DEALING_INITIAL,
    TRUMP_SELECTION,
    DEALING_REMAINING,
    PLAYER_TURN,
    TRICK_RESOLUTION,
    TRICK_DISPLAY,
    ROUND_OVER
}

var state: int = RoundState.IDLE
var local_seat: int = -1
var players: Array[Player] = []            # seat 0..3; only local player holds real cards
var trump_suit: Card.Suit = Card.Suit.SPADES
var dealer_seat: int = 0
var trump_selector_seat: int = 0
var current_player_seat: int = 0
var current_trick: Trick = null
var books: Array[int] = [0, 0]
var books_by_seat: Array[int] = [0, 0, 0, 0]
var trick_history: Array[Dictionary] = []
var session_wins: Array[int] = [0, 0]
var seat_usernames: Array[String] = ["", "", "", ""]
var seat_is_ai: Array[bool] = [false, false, false, false]

## Unused fields kept for API parity with RoundManager. UI reads these
## without ever seeing `null`.
var menu_paused: bool = false
var deal_paused: bool = false

func tick(_delta: float) -> void:
    # No-op on the client — the server drives timing. Kept so game_state
    # can call tick(delta) uniformly on either source.
    pass

## Primary entry point: consume a server message and mutate state.
func apply_event(msg: Dictionary) -> void:
    var type := String(msg.get("type", ""))
    var data := msg.get("data", {}) as Dictionary
    match type:
        Protocol.MSG_SESSION_START:
            _apply_session_start(data)
        Protocol.MSG_ROUND_STARTING:
            _apply_round_starting(data)
        Protocol.MSG_HAND_DEALT:
            _apply_hand_dealt(data)
        Protocol.MSG_TRUMP_SELECTION_NEEDED:
            _apply_trump_selection_needed(data)
        Protocol.MSG_TRUMP_DECLARED:
            _apply_trump_declared(data)
        Protocol.MSG_TURN_STARTED:
            _apply_turn_started(data)
        Protocol.MSG_CARD_PLAYED:
            _apply_card_played(data)
        Protocol.MSG_TRICK_COMPLETED:
            _apply_trick_completed(data)
        Protocol.MSG_ROUND_ENDED:
            _apply_round_ended(data)
        Protocol.MSG_SEAT_TAKEN_OVER_BY_AI:
            _apply_seat_taken_over(data)

# ── Per-message appliers ──────────────────────────────────────────────────────

func _apply_session_start(data: Dictionary) -> void:
    var seats := data.get("seats", []) as Array
    players = []
    seat_usernames = ["", "", "", ""]
    seat_is_ai = [false, false, false, false]
    players.resize(4)
    for entry in seats:
        var seat := int(entry["seat"])
        var username := String(entry["username"])
        var is_ai := bool(entry["is_ai"])
        seat_usernames[seat] = username
        seat_is_ai[seat] = is_ai
        # All seats get a placeholder Player so round_manager-style code paths
        # (hand.size() etc.) work. Only the local seat's hand is ever populated
        # with real Card objects; the others stay empty.
        players[seat] = Player.new(seat, username, seat == local_seat)
    dealer_seat = int(data.get("starting_dealer_seat", 0))
    session_wins = (data.get("session_wins", [0, 0]) as Array).duplicate()

func _apply_round_starting(data: Dictionary) -> void:
    dealer_seat = int(data.get("dealer_seat", 0))
    trump_selector_seat = int(data.get("trump_selector_seat", (dealer_seat + 1) % 4))
    state = RoundState.DEALING_INITIAL
    books = [0, 0]
    books_by_seat = [0, 0, 0, 0]
    trick_history.clear()
    current_trick = null
    for p in players:
        if p != null:
            p.clear_hand()
    round_starting.emit(dealer_seat, trump_selector_seat, int(data.get("round_number", 1)))

func _apply_hand_dealt(data: Dictionary) -> void:
    var seat := int(data["seat_index"])
    var count := int(data.get("count", 0))
    var real_cards: Array = []
    if data.has("cards"):
        for d in data["cards"]:
            real_cards.append(Protocol.dict_to_card(d as Dictionary))
    if seat == local_seat and not real_cards.is_empty():
        players[seat].hand.add_cards(real_cards)
        hand_dealt.emit(seat, real_cards)
    else:
        # Other seats: synthesize `count` placeholder cards so the UI's
        # face-down rendering (which iterates the array by length) still works.
        var placeholders: Array = []
        for i in count:
            placeholders.append(null)
        hand_dealt.emit(seat, placeholders)

func _apply_trump_selection_needed(data: Dictionary) -> void:
    state = RoundState.TRUMP_SELECTION
    trump_selector_seat = int(data["seat_index"])
    var initial_cards: Array = []
    if trump_selector_seat == local_seat:
        initial_cards = players[local_seat].hand.cards.duplicate()
    trump_selection_needed.emit(trump_selector_seat, initial_cards)

func _apply_trump_declared(data: Dictionary) -> void:
    trump_suit = int(data["suit"]) as Card.Suit
    state = RoundState.DEALING_REMAINING
    trump_declared.emit(trump_suit)

func _apply_turn_started(data: Dictionary) -> void:
    current_player_seat = int(data["seat_index"])
    if current_trick == null:
        current_trick = Trick.new(trump_suit)
    state = RoundState.PLAYER_TURN
    var valid: Array[Card] = []
    if current_player_seat == local_seat and local_seat >= 0:
        valid = players[local_seat].hand.get_valid_cards(
            current_trick.led_suit, trump_suit
        )
    turn_started.emit(current_player_seat, valid)

func _apply_card_played(data: Dictionary) -> void:
    var seat := int(data["seat_index"])
    var card := Protocol.dict_to_card(data["card"] as Dictionary)
    if current_trick == null:
        current_trick = Trick.new(trump_suit)
    # Local player: remove the matching card from the real hand.
    if seat == local_seat and local_seat >= 0:
        for c in players[local_seat].hand.cards:
            if c.suit == card.suit and c.rank == card.rank:
                players[local_seat].hand.remove_card(c)
                break
    current_trick.play_card(seat, card)
    card_played_signal.emit(seat, card)

func _apply_trick_completed(data: Dictionary) -> void:
    var winner_seat := int(data["winner_seat"])
    books = (data.get("books", [0, 0]) as Array).duplicate()
    books_by_seat = (data.get("books_by_seat", [0, 0, 0, 0]) as Array).duplicate()
    current_trick = null
    state = RoundState.TRICK_DISPLAY
    trick_completed.emit(winner_seat, books, books_by_seat)

func _apply_round_ended(data: Dictionary) -> void:
    var winning_team := int(data["winning_team"])
    session_wins = (data.get("session_wins", session_wins) as Array).duplicate()
    trick_history = _deserialize_trick_history(data.get("trick_history", []) as Array)
    state = RoundState.ROUND_OVER
    round_ended.emit(winning_team)

func _apply_seat_taken_over(data: Dictionary) -> void:
    var seat := int(data["seat_index"])
    var display_name := String(data.get("display_name", ""))
    var reason := String(data.get("reason", "disconnect"))
    seat_is_ai[seat] = true
    seat_usernames[seat] = display_name
    if players.size() > seat and players[seat] != null:
        players[seat].display_name = display_name
    seat_taken_over_by_ai.emit(seat, display_name, reason)

func _deserialize_trick_history(raw: Array) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for entry in raw:
        var cards_played: Array = []
        for cp in entry["cards_played"]:
            cards_played.append({
                "position": cp["position"],
                "player": cp["player"],
                "card": Protocol.dict_to_card(cp["card"]),
            })
        out.append({
            "trick_number": int(entry["trick_number"]),
            "winning_team": String(entry["winning_team"]),
            "winning_card": Protocol.dict_to_card(entry["winning_card"]),
            "cards_played": cards_played,
        })
    return out
```

- [ ] **Step 2: Verify parse**

Open the editor. No parse errors on `net_game_view.gd`.

- [ ] **Step 3: Commit**

```bash
git add scripts/net/net_game_view.gd
git commit -m "feat(mp): NetGameView client-side RoundManager mirror"
```

---

## Task 11: GameState — game_source field + multiplayer bypass

**Files:**
- Modify: `autoloads/game_state.gd`

- [ ] **Step 1: Add the `game_source` field and a mode flag**

Near the top of `autoloads/game_state.gd`, just below the existing `var round_manager: RoundManager` declaration:

```gdscript
var round_manager: RoundManager
## Abstract game source for the UI: either round_manager (single-player) or
## a NetGameView (multiplayer). game_table_ui.gd reads from this — not
## round_manager directly.
var game_source: Node = null
## True while a multiplayer session is active. Flipped by set_multiplayer_source.
var multiplayer_mode: bool = false
```

- [ ] **Step 2: Wire single-player mode to game_source by default**

Update `_ready()` to point `game_source` at `round_manager` for the single-player path, and update `_process` to only tick in single-player mode:

```gdscript
func _ready() -> void:
    round_manager = RoundManager.new()
    add_child(round_manager)
    game_source = round_manager
    round_manager.round_ended.connect(_on_round_ended)
    # Single-player stats: track every trick and every round finish.
    round_manager.trick_completed.connect(_on_trick_completed_stats)
    round_manager.round_ended.connect(_on_round_ended_stats)

func _process(delta: float) -> void:
    if multiplayer_mode:
        return
    if round_manager != null:
        round_manager.tick(delta)
```

- [ ] **Step 3: Add helpers for multiplayer transitions**

Append these functions below `get_round_manager()`:

```gdscript
## Called by NetworkState when the server announces MSG_SESSION_START. Swaps
## the UI's game source from round_manager to a fresh NetGameView.
func set_multiplayer_source(view: NetGameView) -> void:
    multiplayer_mode = true
    game_source = view

## Called by NetworkState when the client leaves a multiplayer session, or
## main_menu_ui before starting a new single-player session.
func clear_multiplayer_source() -> void:
    multiplayer_mode = false
    game_source = round_manager
```

- [ ] **Step 4: Verify parse + commit**

```bash
git add autoloads/game_state.gd
git commit -m "feat(mp): GameState.game_source abstraction for multiplayer"
```

---

## Task 12: NetworkState — client facades + session message handling

**Files:**
- Modify: `autoloads/network_state.gd`

- [ ] **Step 1: Add the three new client-facing facades**

Append to the `# ── Room actions (UI facade)` section (below `start_game`):

```gdscript
# ── Game actions (UI facade) ──────────────────────────────────────────────────

func play_card(card: Card) -> void:
    if connection_state != ConnectionState.IN_ROOM:
        return
    send(Protocol.msg(Protocol.MSG_PLAY_CARD, {"card": Protocol.card_to_dict(card)}))

func declare_trump(suit: Card.Suit) -> void:
    if connection_state != ConnectionState.IN_ROOM:
        return
    send(Protocol.msg(Protocol.MSG_DECLARE_TRUMP, {"suit": int(suit)}))

func next_round() -> void:
    if connection_state != ConnectionState.IN_ROOM or not is_host:
        return
    send(Protocol.msg(Protocol.MSG_NEXT_ROUND))
```

- [ ] **Step 2: Handle incoming session messages**

Extend `_handle_server_message` with cases for every new S→C type. The updated `match type:` block:

```gdscript
    match type:
        Protocol.MSG_WELCOME:
            local_peer_id = int(data.get("peer_id", 0))
        Protocol.MSG_ROOM_JOINED:
            room_code = String(data.get("code", ""))
            players = (data.get("players", []) as Array).duplicate(true)
            local_seat = int(data.get("your_seat", -1))
            var host_id := int(data.get("host_id", 0))
            is_host = host_id == local_peer_id
            _set_connection_state(ConnectionState.IN_ROOM)
            room_state_changed.emit()
        Protocol.MSG_ROOM_STATE:
            room_code = String(data.get("code", room_code))
            players = (data.get("players", []) as Array).duplicate(true)
            var host_id2 := int(data.get("host_id", 0))
            is_host = host_id2 == local_peer_id
            for p in players:
                if int(p["peer_id"]) == local_peer_id:
                    local_seat = int(p["seat"])
                    break
            room_state_changed.emit()
        Protocol.MSG_ERROR:
            var code := String(data.get("code", ""))
            var message := String(data.get("message", ""))
            last_error_code = code
            if code == Protocol.ERR_HOST_LEFT:
                _clear_room()
                _set_connection_state(ConnectionState.CONNECTED)
            error_received.emit(code, message)
        Protocol.MSG_GAME_STARTING:
            game_starting.emit()
        Protocol.MSG_SESSION_START:
            _begin_multiplayer_session(msg)
        Protocol.MSG_ROUND_STARTING, \
        Protocol.MSG_HAND_DEALT, \
        Protocol.MSG_TRUMP_SELECTION_NEEDED, \
        Protocol.MSG_TRUMP_DECLARED, \
        Protocol.MSG_TURN_STARTED, \
        Protocol.MSG_CARD_PLAYED, \
        Protocol.MSG_TRICK_COMPLETED, \
        Protocol.MSG_ROUND_ENDED, \
        Protocol.MSG_SEAT_TAKEN_OVER_BY_AI:
            if GameState.game_source is NetGameView:
                (GameState.game_source as NetGameView).apply_event(msg)
        _:
            push_warning("NetworkState: unknown server msg type=%s" % type)
```

- [ ] **Step 3: Implement the scene transition helper**

Add the `_begin_multiplayer_session` helper below `_handle_server_message`:

```gdscript
func _begin_multiplayer_session(msg: Dictionary) -> void:
    var view := NetGameView.new()
    view.local_seat = local_seat
    GameState.set_multiplayer_source(view)
    view.apply_event(msg)
    # Defer so we don't change scenes inside the message-handling frame.
    get_tree().change_scene_to_file.call_deferred("res://scenes/game_table.tscn")
```

- [ ] **Step 4: Clear multiplayer source on disconnect / leave**

Update `disconnect_from_server` and `leave_room` to clear `GameState.game_source`:

```gdscript
func disconnect_from_server() -> void:
    if _client_peer != null:
        _client_peer.close()
        _client_peer = null
    GameState.clear_multiplayer_source()
    _clear_room()
    _set_connection_state(ConnectionState.DISCONNECTED)

func leave_room() -> void:
    if connection_state != ConnectionState.IN_ROOM:
        return
    send(Protocol.msg(Protocol.MSG_LEAVE_ROOM))
    GameState.clear_multiplayer_source()
    _clear_room()
    _set_connection_state(ConnectionState.CONNECTED)
```

And in the disconnect branch inside `_process`:

```gdscript
    if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
        if connection_state != ConnectionState.DISCONNECTED:
            _client_peer = null
            GameState.clear_multiplayer_source()
            _clear_room()
            _set_connection_state(ConnectionState.DISCONNECTED)
            error_received.emit("DISCONNECTED", "Disconnected from server")
        return
```

- [ ] **Step 5: Verify parse + commit**

```bash
git add autoloads/network_state.gd
git commit -m "feat(mp): NetworkState game facades + session dispatch + scene swap"
```

---

## Task 13: game_table_ui refactor — game_source + MP action paths

**Files:**
- Modify: `scripts/ui/game_table_ui.gd`

- [ ] **Step 1: Add a helper that returns the active game source**

Near the top of `game_table_ui.gd`, below the existing constants and state vars, add:

```gdscript
## Convenience pair — the source used for reads (signals, state fields) and
## a flag indicating which action path to use on writes.
func _source():
    return GameState.game_source

func _is_mp() -> bool:
    return GameState.multiplayer_mode
```

- [ ] **Step 2: Connect signals from the abstract source**

Replace `_connect_signals()` with a version that reads from `GameState.game_source`:

```gdscript
func _connect_signals() -> void:
    var src := _source()
    src.hand_dealt.connect(_on_hand_dealt)
    src.trump_selection_needed.connect(_on_trump_selection_needed)
    src.trump_declared.connect(_on_trump_declared)
    src.turn_started.connect(_on_turn_started)
    src.card_played_signal.connect(_on_card_played)
    src.trick_completed.connect(_on_trick_completed)
    src.round_ended.connect(_on_round_ended)
    if _is_mp():
        # NetGameView drives round start via round_starting, not GameState.
        src.round_starting.connect(_on_round_started)
        src.seat_taken_over_by_ai.connect(_on_seat_taken_over_by_ai)
        NetworkState.error_received.connect(_on_mp_error_received)
        NetworkState.connection_state_changed.connect(_on_mp_connection_changed)
    else:
        GameState.round_started.connect(_on_round_started)
```

- [ ] **Step 3: Route human play actions to the correct sink**

Find every call site of `GameState.get_round_manager().play_card(0, card)` (three places: `_on_card_play_requested`, `_confirm_play`, `_auto_play_last_card`) and replace each with a helper call. Add the helper:

```gdscript
func _send_play(card: Card) -> void:
    if _is_mp():
        NetworkState.play_card(card)
    else:
        GameState.get_round_manager().play_card(0, card)
```

Then replace each `GameState.get_round_manager().play_card(0, card)` in those three functions with `_send_play(card)`.

Also replace the single `play_card` call in any trump-selector code path — the trump selection overlay fires a signal the UI translates. Find where `GameState.get_round_manager().declare_trump(suit)` is called (search for `declare_trump` in `game_table_ui.gd`). If not present, the call lives in `scripts/ui/trump_selector_ui.gd`; Task 13 Step 5 handles that file. Otherwise, add:

```gdscript
func _send_declare_trump(suit: Card.Suit) -> void:
    if _is_mp():
        NetworkState.declare_trump(suit)
    else:
        GameState.get_round_manager().declare_trump(suit)
```

- [ ] **Step 4: Gate SP-only GameState mutations**

Several `game_table_ui` call sites touch `GameState.get_round_manager()` for pause flags (`menu_paused`, `deal_paused`). These need to be no-ops in multiplayer because the server owns pause state. Wrap each such assignment in an `_is_mp()` check. Specifically, update:

- `_on_settings_button_pressed`: skip `menu_paused = true` when MP.
- `_on_settings_closed`: skip `menu_paused = false` when MP.
- `_notification(NOTIFICATION_APPLICATION_PAUSED/RESUMED)`: same — only touch pause flags in SP.
- `_on_round_started` prologue (`GameState.get_round_manager().deal_paused = true`): in MP mode, set `_source().deal_paused = true` on the NetGameView (which no-ops) instead.
- `_process_deal_queue` setting `deal_paused = false`: same treatment — guard the call via `_source().deal_paused = false`.
- `_on_trump_declared` setting `deal_paused = true`: same.

Use a small helper to avoid repetition:

```gdscript
func _set_deal_paused(value: bool) -> void:
    var src := _source()
    if src != null and "deal_paused" in src:
        src.deal_paused = value

func _set_menu_paused(value: bool) -> void:
    if _is_mp():
        return  # Server owns pause in MP.
    var rm := GameState.get_round_manager()
    if rm != null:
        rm.menu_paused = value
```

Then replace the raw assignments with `_set_deal_paused(true/false)` / `_set_menu_paused(true/false)` at those sites.

- [ ] **Step 5: Add the new MP-only event handlers**

At the bottom of the file, add:

```gdscript
func _on_seat_taken_over_by_ai(seat: int, display_name: String, reason: String) -> void:
    var verb := "disconnected" if reason == "disconnect" else "left"
    _show_toast("%s %s — AI taking over" % [display_name, verb])
    var avatar = _get_avatar(seat)
    if avatar != null and avatar.has_method("set_player_name"):
        avatar.set_player_name(display_name + " (AI)")

func _on_mp_error_received(code: String, _message: String) -> void:
    if code == Protocol.ERR_HOST_LEFT:
        _show_toast("Host left the room")
        get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

func _on_mp_connection_changed(state: int) -> void:
    if state == NetworkState.ConnectionState.DISCONNECTED:
        _show_toast("Disconnected from server")
        get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

func _show_toast(text: String) -> void:
    if toast_label == null:
        return
    toast_label.text = text
    toast_label.modulate.a = 1.0
    toast_label.visible = true
    var tw := create_tween()
    tw.tween_interval(1.8)
    tw.tween_property(toast_label, "modulate:a", 0.0, 0.3)
    tw.tween_callback(func(): toast_label.visible = false)
```

- [ ] **Step 6: Guard `GameState.start_session()` on entry**

`game_table_ui._ready()` currently calls `GameState.start_session()` unconditionally. In multiplayer that line would wipe the NetGameView source and reset players. Replace the unconditional call:

```gdscript
    if not GameState.multiplayer_mode:
        GameState.start_session()
```

- [ ] **Step 7: Verify parse + commit**

Open the editor. Run `scenes/main_menu.tscn` in single-player mode; start a round; confirm dealing, trump selection, a full trick, book update, and transition to next round all still work. Full SP regression is Task 15 — for now, just confirm the refactor compiles and runs.

```bash
git add scripts/ui/game_table_ui.gd
git commit -m "refactor(mp): game_table_ui reads game_source, routes actions for MP"
```

---

## Task 14: room_waiting_ui cleanup + trump_selector_ui MP branch

**Files:**
- Modify: `scripts/ui/room_waiting_ui.gd`
- Modify: `scripts/ui/trump_selector_ui.gd`
- Modify: `scripts/ui/win_screen_ui.gd`

- [ ] **Step 1: Remove the "not implemented" toast**

In `scripts/ui/room_waiting_ui.gd`, delete the `_TOAST_NOT_IMPLEMENTED` constant and the `_on_game_starting` handler. Update `_ready` to drop the `game_starting.connect` line — scene change is now driven by `NetworkState._begin_multiplayer_session` at `MSG_SESSION_START`. The signal handler for `room_state_changed` still triggers the render pass. No new logic is needed; the waiting room can remain visible until the scene is swapped from under it.

The updated `_ready` body:

```gdscript
func _ready() -> void:
    start_button.pressed.connect(_on_start_pressed)
    leave_button.pressed.connect(_leave)
    NetworkState.room_state_changed.connect(_render)
    NetworkState.connection_state_changed.connect(_on_connection_state_changed)
    NetworkState.error_received.connect(_on_error_received)
    _render()
```

Delete the now-unreferenced `_on_game_starting` method and the `_TOAST_NOT_IMPLEMENTED` constant. Leave `_show_toast` in place — it's still used by `_on_connection_state_changed` and `_on_error_received`.

- [ ] **Step 2: Route trump selection through the new helper**

Open `scripts/ui/trump_selector_ui.gd`. Find the call that currently reads `GameState.get_round_manager().declare_trump(suit)` (or similar). Replace it with a branch on `GameState.multiplayer_mode`:

```gdscript
    if GameState.multiplayer_mode:
        NetworkState.declare_trump(suit)
    else:
        GameState.get_round_manager().declare_trump(suit)
```

If the file structure is different (e.g. the call lives inside a signal connection), keep the branching logic at the point where the human's suit choice is finalized.

- [ ] **Step 3: Route Next Round through the new helper**

Open `scripts/ui/win_screen_ui.gd`. Find the "Next Round" button handler (currently calls `GameState.start_next_round()` or similar). Replace the body with:

```gdscript
    if GameState.multiplayer_mode:
        if NetworkState.is_host:
            NetworkState.next_round()
        # Non-hosts ignore — button should already be hidden/disabled for them.
    else:
        GameState.start_next_round()
```

Also add visibility control: the Next Round button should be disabled for non-host multiplayer clients. Find the method that shows/hides the button (likely in `show_result`) and add:

```gdscript
    if GameState.multiplayer_mode and not NetworkState.is_host:
        next_round_button.disabled = true
        next_round_button.text = "Waiting for host…"
    else:
        next_round_button.disabled = false
        next_round_button.text = "Next Round"
```

Adjust node-reference names to match the actual scene structure if they differ.

- [ ] **Step 4: Verify parse + commit**

```bash
git add scripts/ui/room_waiting_ui.gd scripts/ui/trump_selector_ui.gd scripts/ui/win_screen_ui.gd
git commit -m "refactor(mp): UI routes trump/next-round through NetworkState in MP"
```

---

## Task 15: Single-player regression pass

This task ships no code — it's a mandatory verification checkpoint before multiplayer testing begins.

- [ ] **Step 1: Run a fresh single-player session end-to-end**

Open the Godot editor, press F5 to run the project, click "Single Player". Play through one full round to a 7-book win.

Verify:
- Shuffle animation plays.
- 5 cards deal to the trump selector; trump selector UI appears.
- Full hands deal after trump is chosen (everyone has 13 cards).
- Card highlighting respects follow-suit on the human's turn.
- AI delays feel natural (0.5–1.0 s between plays).
- Trick resolves with winning-card highlight + book counter update.
- Win screen shows the correct winner at 7 books.
- "Next Round" button works and the dealer has rotated.

- [ ] **Step 2: Play two more rounds for rotation coverage**

Play at least 2 more rounds back-to-back. Verify:
- Dealer alternates within the losing team on consecutive losses.
- Trump selector is always the seat to the left of the dealer.
- Session wins label updates.
- Trick history overlay still renders correctly (press the History button).

- [ ] **Step 3: Exercise each AI difficulty for one round**

From the settings overlay, switch AI difficulty to Easy and play one round. Then Medium. Then Hard. No crashes, no regressions versus M1 behavior.

- [ ] **Step 4: Pause-menu sanity check**

During the human's turn, open the settings overlay. AI must freeze. Close the overlay — AI resumes.

- [ ] **Step 5: Commit the verification note**

If everything passes, no code change is required. Log the pass in the commit log by touching nothing and moving on. If a regression is found, fix it and commit the fix with a clear message, then re-run this task from Step 1. Do not proceed to Task 16 until SP is clean.

---

## Task 16: Multiplayer end-to-end verification (scenarios A–H)

Run each scenario in order. Pass = all listed checks hold. Fail = fix and rerun the affected scenario.

- [ ] **Scenario A — Full 4-human round**

Press F5 four times from the editor. The first instance wins the bind race and becomes the server; the next three are clients. On each client: enter a username, client 1 creates a room, clients 2/3/4 join by code. Host presses Start.

Verify:
- All 4 clients transition simultaneously to the game table.
- Random dealer shows up in each client's `dealer_seat` reference (log-print if needed).
- Only the trump selector's client sees its initial 5 cards face-up; the other three see 5 face-down placeholders at that seat.
- Trump selector UI renders only on the selector's client.
- After trump is chosen, all 4 clients deal to 13 cards.
- A full 13-trick round plays. Each `MSG_CARD_PLAYED` animates in real time on every client.
- Book counter increments in sync on all 4 clients.
- Win screen appears simultaneously at exactly 7 books.
- Session wins HUD shows 1:0 or 0:1 on all clients.

- [ ] **Scenario B — 2-human + 2-AI round**

Press F5 three times: 1 server + 2 clients. Create a room, join with the second client, host presses Start with 2 humans seated.

Verify:
- Waiting room shows 2 "Empty — AI will fill" rows before Start.
- After Start, the game table shows 2 AI-controlled seats that act on their turns without client input.
- Round completes cleanly.

- [ ] **Scenario C — Mid-round non-host disconnect**

Press F5 four times: 1 server + 3 clients. Start a 3-human game (1 AI fills seat 3). Wait until trick 5, then close one of the non-host client windows.

Verify:
- Within ENet's timeout (~5 s), both remaining clients see a "username disconnected — AI taking over" toast.
- The disconnected seat's avatar label changes to include "(AI)".
- The current trick continues without interruption.
- Round completes normally.

- [ ] **Scenario D — Mid-round host disconnect**

Press F5 four times: 1 server + 3 clients. Start a 3-human game. Wait until mid-round, then close the host client.

Verify:
- Remaining two clients see a "Host left the room" toast and return to main menu.
- Server log shows the room being destroyed.
- A fresh Create Room on either remaining client works.

- [ ] **Scenario E — Voluntary leave mid-game**

Press F5 three times: 1 server + 2 clients. Start a 2-human game. Mid-round, a non-host client presses its settings-overlay Leave button (or back button).

Verify:
- Remaining client sees the "left" variant of the takeover toast.
- Leaver's client returns to main menu with no error.
- Leaver can join a fresh room afterwards.

- [ ] **Scenario F — Multi-round session loop**

Press F5 three times: 1 server + 2 clients. Start a 2-human game. Play 3 full rounds using Next Round between them.

Verify:
- Dealer rotates correctly per round (losing team, alternating within team on consecutive losses).
- Session wins HUD updates after each round.
- Trump selector is always the seat to the left of the dealer.
- Trick history and book counters reset cleanly between rounds.
- Non-host client's Next Round button is disabled / shows "Waiting for host…" during between-rounds.

- [ ] **Scenario G — All humans leave mid-game**

Press F5 three times: 1 server + 2 clients. Start a 2-human game. Both non-AI clients press Leave in quick succession.

Verify:
- Both leavers land on the main menu with no errors.
- Server log shows the `GameSession` destroyed + `Room` erased.
- Spinning up a new room on either client works.

- [ ] **Scenario H — Server restart mid-game**

Press F5 four times: 1 server + 3 clients. Start a game. Kill the server window.

Verify:
- Within ENet's timeout, all 3 clients show "Disconnected from server" toast and return to main menu.
- Launching a fresh server + clients works.

- [ ] **Scenario I — Illegal-action defence (optional)**

Temporarily add a button to `game_table_ui.gd` that sends `MSG_PLAY_CARD` with a card not in the local hand (or skip the follow-suit check). Spin up 1 server + 2 clients, start a game, press the button on a client during its own turn.

Verify:
- Server sends back `MSG_ERROR { code: "INVALID_CARD" }`.
- Client toasts "That card can't be played."
- Game state is unchanged (turn indicator still on the sender).

Remove the cheat button before committing. Skip this scenario if it's annoying to wire up.

- [ ] **Final commit**

Once all mandatory scenarios pass, commit any incidental fixes made during verification as separate, well-described commits. If no fixes were needed, nothing to commit — proceed to branch cleanup.

```bash
git log --oneline master..HEAD
```

Expected: a clean history of M2 commits, each scoped to one task.

---

## Self-Review Notes

- **Spec coverage:**
  - Goals 1–5 (authoritative server loop, wire protocol extension, NetGameView mirror, AI fill, session loop) → Tasks 2–12 build them; Task 16 verifies.
  - All 8 mandatory test scenarios → Task 16 maps 1:1.
  - Non-goals respected — no turn timer, no reconnect, no host migration, no configurable address.
- **Placeholder scan:** Every code block is complete. The only scaffolding deferred beyond "compile and parse" is the fine detail of Tasks 13/14 for files this plan touches but doesn't quote in full (trump_selector_ui.gd, win_screen_ui.gd). Those tasks describe the exact edits with real branch code; the engineer is expected to open the file and insert at the right spot.
- **Type consistency:**
  - `GameSession` public methods consistently return `Array` of `[peer_id, msg]` tuples — same shape as `RoomManager`'s existing handlers.
  - Signal signatures in `NetGameView` match `RoundManager` exactly (`hand_dealt(seat_index: int, cards: Array)`, `trick_completed(winner_seat, books, books_by_seat)`, etc.).
  - Protocol message type constants use the `MSG_` / `ERR_` prefix convention from M1.
  - `GameState.game_source: Node` is set to either `round_manager` or a `NetGameView`; both expose the same tick/signal/state API surface that `game_table_ui.gd` actually reads.
