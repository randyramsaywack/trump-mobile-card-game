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
## Matches GameState.round_started's arity so _on_round_started can be connected
## to either source without a wrapper.
signal round_starting(dealer_seat: int, trump_selector_seat: int)
## Fired once at the end of apply_full_state, after every other field has
## been populated and the per-seat hand_dealt signals have been emitted.
## game_table_ui uses this to finalize the resume: snap trick cards into the
## trick area, show the win screen if between_rounds, etc.
signal full_state_applied(snapshot: Dictionary)

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

## The local player's true seat on the server (0..3). Used only internally
## to rotate incoming events so the UI always sees the local player at
## display seat 0 — matching single-player's "you are always seat 0"
## assumption. Set by NetworkState._begin_multiplayer_session BEFORE any
## events are applied.
var _server_local_seat: int = 0

## Always 0 in display-seat terms once a session is live. Exposed as a
## public field because some call sites read game_source.local_seat.
var local_seat: int = 0
var players: Array[Player] = []            # display seat 0..3; only players[0] holds real cards
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

## Local-clock deadline for the active turn (Time.get_ticks_msec() value).
## Set when the server delivers MSG_TURN_STARTED / MSG_TRUMP_SELECTION_NEEDED
## with seconds_remaining; cleared when the turn ends or the round wraps. UI
## reads this every frame and shows a countdown; 0 means "no active turn".
var current_turn_deadline_msec: int = 0

## True only while game_table_ui is bootstrapping from a MSG_FULL_STATE
## snapshot. The UI checks this to skip the shuffle/deal animation and snap
## cards directly into hands and trick slots — animating a mid-round resume
## from scratch would replay tricks that have already happened.
var is_resuming: bool = false

## Position labels used at every display seat in every mode. Display seat 0
## is always the local player (NetGameView rotates incoming events, SP puts
## the human at seat 0 directly), so this mapping is shared between SP and MP.
const DISPLAY_SEAT_NAMES := ["You", "Left", "Partner", "Right"]

# ── Seat-rotation helpers ─────────────────────────────────────────────────────
# Server seats are absolute (0..3). The UI was built for single-player where
# seat 0 is always the human, so we rotate every incoming seat index by
# `_server_local_seat` to present local at display seat 0.

func _to_display_seat(server_seat: int) -> int:
	return (server_seat - _server_local_seat + 4) % 4

## Server teams: team 0 = seats 0 & 2, team 1 = seats 1 & 3. If the local
## player sits on an odd server seat, local is on server-team 1 but must be
## display-team 0 (your team = team 0), so we swap.
func _to_display_team(server_team: int) -> int:
	if _server_local_seat % 2 == 0:
		return server_team
	return 1 - server_team

## Rotate a length-4 seat-indexed array so result[display_seat] == input[server_seat].
func _rotate_seat_array(server_array: Array) -> Array:
	var out: Array = [null, null, null, null]
	for s in 4:
		out[_to_display_seat(s)] = server_array[s]
	return out

## Rotate a seat-indexed int array into a typed Array[int].
func _rotate_seat_int_array(server_array: Array) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0]
	for s in 4:
		out[_to_display_seat(s)] = int(server_array[s])
	return out

## Swap a 2-element team array if the local player is on an odd team.
func _swap_team_array(server_array: Array) -> Array[int]:
	var a := int(server_array[0])
	var b := int(server_array[1])
	if _server_local_seat % 2 == 0:
		return [a, b]
	return [b, a]

## Unused fields kept for API parity with RoundManager. UI reads these
## without ever seeing `null`.
var menu_paused: bool = false
var deal_paused: bool = false

## Event buffering. The server dispatches the initial burst of session-start
## messages (MSG_SESSION_START + MSG_ROUND_STARTING + MSG_HAND_DEALT ×4 +
## MSG_TRUMP_SELECTION_NEEDED) in a single packet flight. NetworkState processes
## all of them in one _process tick, but the scene change to game_table.tscn is
## deferred — so signals emitted during apply_event() would fire into a void.
## We queue events here until game_table_ui._ready() calls begin_live().
var _event_queue: Array[Dictionary] = []
var _live: bool = false

func tick(_delta: float) -> void:
	# No-op on the client — the server drives timing. Kept so game_state
	# can call tick(delta) uniformly on either source.
	pass

## Primary entry point: consume a server message and mutate state.
## Before begin_live() is called, events are buffered and replayed in order.
func apply_event(msg: Dictionary) -> void:
	if not _live:
		_event_queue.append(msg)
		return
	_dispatch_event(msg)

## Called by game_table_ui._ready() after all signal listeners are wired up.
## Drains any buffered events in the order they arrived.
func begin_live() -> void:
	if _live:
		return
	_live = true
	var drain := _event_queue
	_event_queue = []
	for msg in drain:
		_dispatch_event(msg)

func _dispatch_event(msg: Dictionary) -> void:
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
		Protocol.MSG_FULL_STATE:
			_apply_full_state(data)

# ── Per-message appliers ──────────────────────────────────────────────────────

func _apply_session_start(data: Dictionary) -> void:
	var seats := data.get("seats", []) as Array
	players = []
	seat_usernames = ["", "", "", ""]
	seat_is_ai = [false, false, false, false]
	players.resize(4)
	for entry in seats:
		var server_seat := int(entry["seat"])
		var display_seat := _to_display_seat(server_seat)
		var is_ai := bool(entry["is_ai"])
		seat_is_ai[display_seat] = is_ai
		# Local seat is always "You". AI-filled seats use the position label
		# (the server's AI naming is from its own coordinate space, which
		# wouldn't match this client's perspective). Real human opponents
		# show their actual username from the server payload.
		var label: String
		if display_seat == 0:
			label = "You"
		elif is_ai:
			label = DISPLAY_SEAT_NAMES[display_seat]
		else:
			label = String(entry.get("username", DISPLAY_SEAT_NAMES[display_seat]))
		seat_usernames[display_seat] = label
		# All seats get a placeholder Player so round_manager-style code paths
		# (hand.size() etc.) work. Only display seat 0 — the local player —
		# ever has real Card objects; the others stay empty.
		players[display_seat] = Player.new(display_seat, label, display_seat == 0)
	dealer_seat = _to_display_seat(int(data.get("starting_dealer_seat", 0)))
	session_wins = _swap_team_array(data.get("session_wins", [0, 0]) as Array)

func _apply_round_starting(data: Dictionary) -> void:
	dealer_seat = _to_display_seat(int(data.get("dealer_seat", 0)))
	trump_selector_seat = _to_display_seat(int(data.get("trump_selector_seat", (dealer_seat + 1) % 4)))
	state = RoundState.DEALING_INITIAL
	books = [0, 0]
	books_by_seat = [0, 0, 0, 0]
	trick_history.clear()
	current_trick = null
	for p in players:
		if p != null:
			p.clear_hand()
	round_starting.emit(dealer_seat, trump_selector_seat)

func _apply_hand_dealt(data: Dictionary) -> void:
	var display_seat := _to_display_seat(int(data["seat_index"]))
	var count := int(data.get("count", 0))
	var real_cards: Array[Card] = []
	if data.has("cards"):
		for d in data["cards"]:
			real_cards.append(Protocol.dict_to_card(d as Dictionary))
	if display_seat == 0 and not real_cards.is_empty():
		players[0].hand.add_cards(real_cards)
		hand_dealt.emit(0, real_cards)
	else:
		# Other seats: synthesize `count` placeholder cards so the UI's
		# face-down rendering (which iterates the array by length) still works.
		var placeholders: Array = []
		for i in count:
			placeholders.append(null)
		hand_dealt.emit(display_seat, placeholders)

func _apply_trump_selection_needed(data: Dictionary) -> void:
	state = RoundState.TRUMP_SELECTION
	trump_selector_seat = _to_display_seat(int(data["seat_index"]))
	_arm_local_deadline(float(data.get("seconds_remaining", 0)))
	var initial_cards: Array = []
	if trump_selector_seat == 0:
		initial_cards = players[0].hand.cards.duplicate()
	trump_selection_needed.emit(trump_selector_seat, initial_cards)

func _apply_trump_declared(data: Dictionary) -> void:
	trump_suit = int(data["suit"]) as Card.Suit
	state = RoundState.DEALING_REMAINING
	current_turn_deadline_msec = 0
	trump_declared.emit(trump_suit)

func _apply_turn_started(data: Dictionary) -> void:
	current_player_seat = _to_display_seat(int(data["seat_index"]))
	if current_trick == null:
		current_trick = Trick.new(trump_suit)
	state = RoundState.PLAYER_TURN
	_arm_local_deadline(float(data.get("seconds_remaining", 0)))
	var valid: Array[Card] = []
	if current_player_seat == 0:
		valid = players[0].hand.get_valid_cards(
			current_trick.led_suit, trump_suit
		)
	turn_started.emit(current_player_seat, valid)

## Server sends seconds_remaining; client converts to a local deadline so we
## don't have to do clock-sync. Drift between client/server clocks is bounded
## by the network round-trip (sub-second), well within the 60s budget.
func _arm_local_deadline(seconds: float) -> void:
	if seconds <= 0:
		current_turn_deadline_msec = 0
		return
	current_turn_deadline_msec = Time.get_ticks_msec() + int(seconds * 1000.0)

func _apply_card_played(data: Dictionary) -> void:
	var display_seat := _to_display_seat(int(data["seat_index"]))
	var card := Protocol.dict_to_card(data["card"] as Dictionary)
	if current_trick == null:
		current_trick = Trick.new(trump_suit)
	# Local player: remove the matching card from the real hand.
	if display_seat == 0:
		for c in players[0].hand.cards:
			if c.suit == card.suit and c.rank == card.rank:
				players[0].hand.remove_card(c)
				break
	current_trick.play_card(display_seat, card)
	# Active turn just ended; next MSG_TURN_STARTED will re-arm.
	current_turn_deadline_msec = 0
	card_played_signal.emit(display_seat, card)

func _apply_trick_completed(data: Dictionary) -> void:
	var winner_seat := _to_display_seat(int(data["winner_seat"]))
	books = _swap_team_array(data.get("books", [0, 0]) as Array)
	books_by_seat = _rotate_seat_int_array(data.get("books_by_seat", [0, 0, 0, 0]) as Array)
	current_trick = null
	state = RoundState.TRICK_DISPLAY
	current_turn_deadline_msec = 0
	trick_completed.emit(winner_seat, books, books_by_seat)

func _apply_round_ended(data: Dictionary) -> void:
	var winning_team := _to_display_team(int(data["winning_team"]))
	if data.has("session_wins"):
		session_wins = _swap_team_array(data["session_wins"] as Array)
	trick_history = _deserialize_trick_history(data.get("trick_history", []) as Array)
	state = RoundState.ROUND_OVER
	current_turn_deadline_msec = 0
	round_ended.emit(winning_team)

## Bootstrap from a MSG_FULL_STATE snapshot. Populates every field a fresh
## joiner would normally accumulate from the SESSION_START + ROUND_STARTING +
## HAND_DEALT×4 + TRUMP_DECLARED + TURN_STARTED burst, then fires a single
## full_state_applied so game_table_ui can do an atomic snap render. We
## deliberately do NOT route through the per-message _apply helpers — those
## emit signals that would trigger the shuffle/deal animation pipeline.
func _apply_full_state(data: Dictionary) -> void:
	# Seats / usernames / display roster.
	var seats := data.get("seats", []) as Array
	players = []
	players.resize(4)
	seat_usernames = ["", "", "", ""]
	seat_is_ai = [false, false, false, false]
	for entry in seats:
		var server_seat := int(entry["seat"])
		var display_seat := _to_display_seat(server_seat)
		var is_ai := bool(entry["is_ai"])
		seat_is_ai[display_seat] = is_ai
		var label: String
		if display_seat == 0:
			label = "You"
		elif is_ai:
			label = DISPLAY_SEAT_NAMES[display_seat]
		else:
			label = String(entry.get("username", DISPLAY_SEAT_NAMES[display_seat]))
		seat_usernames[display_seat] = label
		players[display_seat] = Player.new(display_seat, label, display_seat == 0)

	# Round-level state. Display-seat coordinates throughout.
	dealer_seat = _to_display_seat(int(data.get("dealer_seat", 0)))
	trump_selector_seat = _to_display_seat(int(data.get("trump_selector_seat", 0)))
	session_wins = _swap_team_array(data.get("session_wins", [0, 0]) as Array)
	books = _swap_team_array(data.get("books", [0, 0]) as Array)
	books_by_seat = _rotate_seat_int_array(data.get("books_by_seat", [0, 0, 0, 0]) as Array)
	trick_history.clear()

	# Trump suit (server sends -1 if the round hasn't reached trump selection yet).
	var trump_int := int(data.get("trump_suit", -1))
	if trump_int >= 0:
		trump_suit = trump_int as Card.Suit

	# The local player's hand: real Card instances. Other seats: hand.size() is
	# all the UI reads to render face-down stacks.
	var hand_counts := data.get("hand_counts", [0, 0, 0, 0]) as Array
	var your_hand_raw := data.get("your_hand", []) as Array
	for s in 4:
		var display_seat := _to_display_seat(s)
		var count := int(hand_counts[s]) if s < hand_counts.size() else 0
		if s == _server_local_seat:
			var real_cards: Array[Card] = []
			for d in your_hand_raw:
				var c := Protocol.dict_to_card(d as Dictionary)
				if c != null:
					real_cards.append(c)
			players[display_seat].hand.add_cards(real_cards)
		else:
			# Synthesize placeholder cards so hand.size() returns the right count.
			var fake: Array[Card] = []
			for i in count:
				fake.append(Card.new(Card.Suit.SPADES, Card.Rank.TWO))
			players[display_seat].hand.add_cards(fake)

	# In-progress trick (cards already played this trick, in play order).
	current_trick = null
	if trump_int >= 0:
		current_trick = Trick.new(trump_suit)
		var trick_data := data.get("current_trick", []) as Array
		for entry in trick_data:
			var server_seat := int(entry["seat"])
			var display_seat := _to_display_seat(server_seat)
			var card := Protocol.dict_to_card(entry["card"] as Dictionary)
			if card != null:
				current_trick.play_card(display_seat, card)

	# Active actor + timer.
	var server_state := int(data.get("state", int(RoundState.IDLE)))
	state = server_state
	var current_server_seat := int(data.get("current_player_seat", -1))
	if current_server_seat >= 0:
		current_player_seat = _to_display_seat(current_server_seat)
	_arm_local_deadline(float(data.get("seconds_remaining", 0)))

	full_state_applied.emit(data)

func _apply_seat_taken_over(data: Dictionary) -> void:
	var display_seat := _to_display_seat(int(data["seat_index"]))
	var reason := String(data.get("reason", "disconnect"))
	seat_is_ai[display_seat] = true
	# Keep the position label — the UI appends an "(AI)" suffix itself so it
	# stays consistent with the rest of the position-based naming scheme.
	var label: String = DISPLAY_SEAT_NAMES[display_seat]
	seat_usernames[display_seat] = label
	if players.size() > display_seat and players[display_seat] != null:
		players[display_seat].display_name = label
	seat_taken_over_by_ai.emit(display_seat, label, reason)

func _deserialize_trick_history(raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in raw:
		var cards_played: Array = []
		for cp in entry["cards_played"]:
			var server_position := String(cp["position"])
			var display_seat := _to_display_seat(_seat_for_history_position(server_position))
			cards_played.append({
				"position": _history_position_for_display_seat(display_seat),
				"player": DISPLAY_SEAT_NAMES[display_seat],
				"card": Protocol.dict_to_card(cp["card"]),
			})
		var server_team := 0 if String(entry["winning_team"]) == "player_team" else 1
		var display_team := _to_display_team(server_team)
		out.append({
			"trick_number": int(entry["trick_number"]),
			"winning_team": "player_team" if display_team == 0 else "opponent_team",
			"winning_card": Protocol.dict_to_card(entry["winning_card"]),
			"cards_played": cards_played,
		})
	return out

func _seat_for_history_position(position: String) -> int:
	match position:
		"bottom":
			return 0
		"left":
			return 1
		"top":
			return 2
		"right":
			return 3
		_:
			return 0

func _history_position_for_display_seat(seat: int) -> String:
	match seat:
		0:
			return "bottom"
		1:
			return "left"
		2:
			return "top"
		3:
			return "right"
		_:
			return "bottom"
