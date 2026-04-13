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
