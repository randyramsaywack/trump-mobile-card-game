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
