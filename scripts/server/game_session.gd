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
func drain_events() -> Array:
	var out := _pending_events
	_pending_events = []
	return out

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

func start_first_round() -> Array:
	dealer_seat = randi() % 4
	# The initial random dealer belongs to one team; that seat is that team's
	# current dealer. The other team gets its lower-index seat as a default.
	var starting_team := 0 if dealer_seat in [0, 2] else 1
	_team_dealer[starting_team] = dealer_seat
	_team_dealer[1 - starting_team] = 0 if starting_team == 1 else 1
	_append_session_start()
	_start_round()
	return drain_events()

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

# ── Signal handlers (RoundManager → wire) ─────────────────────────────────────

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

func _on_trump_selection_needed(seat_index: int, _initial_cards: Array) -> void:
	_append_to_all(Protocol.msg(Protocol.MSG_TRUMP_SELECTION_NEEDED, {
		"seat_index": seat_index,
	}))

func _on_trump_declared(suit: int) -> void:
	_append_to_all(Protocol.msg(Protocol.MSG_TRUMP_DECLARED, {"suit": int(suit)}))

func _on_turn_started(seat_index: int, _valid_cards: Array) -> void:
	_append_to_all(Protocol.msg(Protocol.MSG_TURN_STARTED, {"seat_index": seat_index}))

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

func _err(peer_id: int, error_code: String) -> Array:
	return [[peer_id, Protocol.msg(Protocol.MSG_ERROR, {
		"code": error_code,
		"message": String(Protocol.ERROR_MESSAGES.get(error_code, error_code)),
	})]]
