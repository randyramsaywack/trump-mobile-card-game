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
## Set true when RoundManager finishes a round; cleared when host calls
## handle_next_round. Gates `play_card`/`declare_trump` during the window
## where the client is showing the win screen.
## Task 6 note: if the host disconnects while this is true, host migration
## must keep the flag intact so the new host can drive handle_next_round —
## do NOT auto-clear on disconnect.
var between_rounds: bool = false

## Tuple buffer: each entry is [peer_id:int, message:Dictionary]. Signal
## handlers append here; public methods return a drained copy to the caller.
var _pending_events: Array = []

## Per-turn timer (multiplayer only). Server-monotonic seconds remaining for
## the current active turn or trump-selection. <= 0 means no active deadline.
## On expiry tick() runs AI on behalf of the human seat, then resets to 0
## (next turn_started/trump_selection_needed sets it again).
const TURN_TIMEOUT_SECONDS: float = 60.0
var _turn_deadline_sec: float = 0.0

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

func handle_declare_trump(peer_id: int, data: Dictionary) -> Array:
	var seat := _seat_for_peer(peer_id)
	if seat < 0:
		return _err(peer_id, Protocol.ERR_NOT_IN_GAME)
	if between_rounds:
		return _err(peer_id, Protocol.ERR_WRONG_PHASE)
	if round_manager.state != RoundManager.RoundState.TRUMP_SELECTION:
		return _err(peer_id, Protocol.ERR_WRONG_PHASE)
	if seat != round_manager.trump_selector_seat:
		return _err(peer_id, Protocol.ERR_NOT_YOUR_TURN)
	var suit_int := int(data.get("suit", -1))
	if suit_int < 0 or suit_int > 3:
		return _err(peer_id, Protocol.ERR_INVALID_CARD)
	round_manager.declare_trump(suit_int as Card.Suit)
	return drain_events()

func handle_play_card(peer_id: int, data: Dictionary) -> Array:
	var seat := _seat_for_peer(peer_id)
	if seat < 0:
		return _err(peer_id, Protocol.ERR_NOT_IN_GAME)
	if between_rounds:
		return _err(peer_id, Protocol.ERR_WRONG_PHASE)
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
	return drain_events()

## Called every frame by RoomManager.tick → main_server._process.
func tick(delta: float) -> Array:
	# Turn timer: if a deadline is set and it just elapsed, run AI on behalf
	# of the human seat. Reset the deadline so we only fire once — the next
	# turn_started signal will re-arm it. AI seats are skipped (RoundManager
	# already drives them via its own _ai_pending timer).
	if _turn_deadline_sec > 0.0 and _now_sec() >= _turn_deadline_sec:
		_turn_deadline_sec = 0.0
		var seat := _active_seat()
		if seat >= 0 and not (players[seat] is AIPlayer):
			_execute_ai_for_seat(seat)
	round_manager.tick(delta)
	return drain_events()

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _active_seat() -> int:
	if round_manager.state == RoundManager.RoundState.TRUMP_SELECTION:
		return round_manager.trump_selector_seat
	if round_manager.state == RoundManager.RoundState.PLAYER_TURN:
		return round_manager.current_player_seat
	return -1

## Plays a card (or selects trump) on behalf of a human seat using the same
## AIPlayer logic that drives normal AI seats. Hand is shared by reference so
## the temporary AIPlayer modifies the real Player's hand via play_card.
func _execute_ai_for_seat(seat: int) -> void:
	var p := players[seat]
	if p == null or p is AIPlayer:
		return
	var temp_ai := AIPlayer.new(seat, p.display_name)
	temp_ai.hand = p.hand
	if round_manager.state == RoundManager.RoundState.TRUMP_SELECTION:
		round_manager.declare_trump(temp_ai.choose_trump())
	elif round_manager.state == RoundManager.RoundState.PLAYER_TURN:
		var trick := round_manager.current_trick
		if trick == null:
			return
		var valid: Array = p.hand.get_valid_cards(trick.led_suit, round_manager.trump_suit)
		if valid.is_empty():
			return
		var partner_seat := (seat + 2) % 4
		var card := temp_ai.choose_card(valid, trick, partner_seat)
		round_manager.play_card(seat, card)

## Called when a non-host peer drops connection. Swaps the peer's seat to
## AI and broadcasts the takeover to remaining humans. Caller is responsible
## for deciding whether the room collapses (host-left) — this method handles
## only non-host cases.
func handle_player_disconnect(peer_id: int) -> Array:
	return _swap_to_ai(peer_id, "disconnect")

## Called by RoomManager when a peer's username matched a vacant seat. Swaps
## the AIPlayer in that seat back to a real Player (sharing the same hand by
## reference so the round state is preserved), re-registers peer_to_seat, and
## defuses any pending AI action queued for that seat — without this, the
## human's first turn back is stolen by the AI's already-scheduled play.
func handle_player_rejoin(peer_id: int, seat: int) -> void:
	if seat < 0 or seat >= players.size():
		return
	var old := players[seat] as Player
	if old != null and not (old is AIPlayer):
		# Seat is already human-owned — just refresh the mapping defensively.
		peer_to_seat[peer_id] = seat
		return
	var human := Player.new(seat, old.display_name, true)
	human.hand = old.hand
	players[seat] = human
	if round_manager.players.size() > seat:
		round_manager.players[seat] = human
	peer_to_seat[peer_id] = seat
	var active := _active_seat()
	if active == seat:
		round_manager._ai_pending = false
		_arm_turn_timer(seat)

## Called when a non-host peer sends leave_room while a game is live.
func handle_player_leave(peer_id: int) -> Array:
	return _swap_to_ai(peer_id, "left")

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
	return drain_events()

func start_first_round() -> Array:
	dealer_seat = randi() % 4
	# The initial random dealer belongs to one team; record it as that team's
	# current dealer. The other team keeps its default (seat 0 for team 0,
	# seat 1 for team 1) from the `_team_dealer` field init.
	var starting_team := 0 if dealer_seat in [0, 2] else 1
	_team_dealer[starting_team] = dealer_seat
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
	var seconds := _arm_turn_timer(seat_index)
	_append_to_all(Protocol.msg(Protocol.MSG_TRUMP_SELECTION_NEEDED, {
		"seat_index": seat_index,
		"seconds_remaining": seconds,
	}))

func _on_trump_declared(suit: int) -> void:
	_append_to_all(Protocol.msg(Protocol.MSG_TRUMP_DECLARED, {"suit": int(suit)}))

func _on_turn_started(seat_index: int, _valid_cards: Array) -> void:
	var seconds := _arm_turn_timer(seat_index)
	_append_to_all(Protocol.msg(Protocol.MSG_TURN_STARTED, {
		"seat_index": seat_index,
		"seconds_remaining": seconds,
	}))

## AI seats don't need the takeover timer (RoundManager already drives them
## via its own _ai_pending under 1.5s) so we send seconds_remaining=0 for
## them — clients use that as the "no countdown for this turn" signal.
## Returns the seconds-remaining value to broadcast.
func _arm_turn_timer(seat_index: int) -> float:
	if seat_index < 0 or seat_index >= players.size():
		_turn_deadline_sec = 0.0
		return 0.0
	if players[seat_index] is AIPlayer:
		_turn_deadline_sec = 0.0
		return 0.0
	_turn_deadline_sec = _now_sec() + TURN_TIMEOUT_SECONDS
	return TURN_TIMEOUT_SECONDS

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

func _on_round_ended(winning_team: int) -> void:
	session_wins[winning_team] += 1
	_rotate_dealer(1 - winning_team)
	between_rounds = true
	# No active turn between rounds — disarm so tick() can't trigger a
	# spurious AI play during the win-screen window.
	_turn_deadline_sec = 0.0
	var trick_history_serialized := _serialize_trick_history()
	_append_to_all(Protocol.msg(Protocol.MSG_ROUND_ENDED, {
		"winning_team": winning_team,
		"session_wins": session_wins.duplicate(),
		"trick_history": trick_history_serialized,
	}))

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

## Rotate within the losing team's two seats. Mirrors the logic in
## GameState._rotate_dealer (autoloads/game_state.gd lines 72–81).
func _rotate_dealer(losing_team: int) -> void:
	var current: int = int(_team_dealer[losing_team])
	var team_seats: Array = _TEAM_SEATS[losing_team]
	var other_seat: int = int(team_seats[1]) if current == int(team_seats[0]) else int(team_seats[0])
	_team_dealer[losing_team] = other_seat
	dealer_seat = other_seat

func _swap_to_ai(peer_id: int, reason: String) -> Array:
	var seat := _seat_for_peer(peer_id)
	if seat < 0:
		return []
	var old := players[seat] as Player
	# Defence in depth: if a future caller forgets to check peer identity,
	# don't stack a second AI over an existing one.
	if old is AIPlayer:
		peer_to_seat.erase(peer_id)
		return []
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
	return drain_events()

## Build the snapshot a rejoining peer needs to bootstrap a NetGameView mid-
## round. Called by RoomManager after handle_player_rejoin re-registers the
## peer; the resulting dict is wrapped in MSG_FULL_STATE and sent privately.
func build_full_state_for(seat: int) -> Dictionary:
	var seats: Array = []
	var hand_counts: Array = []
	for s in 4:
		var p := players[s]
		seats.append({
			"seat": s,
			"username": seat_display_names[s],
			"is_ai": p is AIPlayer,
		})
		hand_counts.append(int(p.hand.size()) if p != null else 0)
	var trump_int := -1
	if round_manager.state != RoundManager.RoundState.IDLE \
			and round_manager.state != RoundManager.RoundState.DEALING_INITIAL \
			and round_manager.state != RoundManager.RoundState.TRUMP_SELECTION:
		trump_int = int(round_manager.trump_suit)
	var current_trick_cards: Array = []
	if round_manager.current_trick != null:
		for entry in round_manager.current_trick.played:
			current_trick_cards.append({
				"seat": int(entry["player_index"]),
				"card": Protocol.card_to_dict(entry["card"] as Card),
			})
	var your_hand: Array = []
	if seat >= 0 and seat < players.size() and players[seat] != null:
		your_hand = Protocol.cards_to_dicts(players[seat].hand.cards)
	var current_seat := -1
	if round_manager.state == RoundManager.RoundState.PLAYER_TURN:
		current_seat = round_manager.current_player_seat
	elif round_manager.state == RoundManager.RoundState.TRUMP_SELECTION:
		current_seat = round_manager.trump_selector_seat
	var seconds_remaining := 0.0
	if _turn_deadline_sec > 0.0 and current_seat == seat:
		seconds_remaining = maxf(0.0, _turn_deadline_sec - _now_sec())
	return {
		"seats": seats,
		"your_seat": seat,
		"dealer_seat": dealer_seat,
		"trump_selector_seat": round_manager.trump_selector_seat,
		"trump_suit": trump_int,
		"books": round_manager.books.duplicate(),
		"books_by_seat": round_manager.books_by_seat.duplicate(),
		"session_wins": session_wins.duplicate(),
		"current_player_seat": current_seat,
		"state": int(round_manager.state),
		"hand_counts": hand_counts,
		"your_hand": your_hand,
		"current_trick": current_trick_cards,
		"between_rounds": between_rounds,
		"seconds_remaining": seconds_remaining,
		"round_number": round_number,
	}

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

func _err(peer_id: int, error_code: String) -> Array:
	return [[peer_id, Protocol.msg(Protocol.MSG_ERROR, {
		"code": error_code,
		"message": String(Protocol.ERROR_MESSAGES.get(error_code, error_code)),
	})]]
