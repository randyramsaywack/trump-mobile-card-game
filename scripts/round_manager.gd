class_name RoundManager
extends Node

signal hand_dealt(seat_index: int, cards: Array)
signal trump_selection_needed(seat_index: int, initial_cards: Array)
signal trump_declared(suit: Card.Suit)
signal turn_started(seat_index: int, valid_cards: Array)
signal card_played_signal(seat_index: int, card: Card)
signal trick_completed(winner_seat: int, books: Array, books_by_seat: Array)
signal round_ended(winning_team: int)

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

var state: RoundState = RoundState.IDLE
var deal_paused: bool = false
var menu_paused: bool = false
var players: Array[Player] = []
var deck: Deck
var trump_suit: Card.Suit
var dealer_seat: int
var trump_selector_seat: int
var current_player_seat: int
var current_trick: Trick
var books: Array[int] = [0, 0]  # [team0_books, team1_books]
var books_by_seat: Array[int] = [0, 0, 0, 0]  # per-player trick wins
## History of every trick completed this round. One entry per trick with
## trick number, winning team name, winning card, and all 4 played cards
## tagged with position (bottom/top/left/right) and player label.
## Cleared at round start; populated after each trick resolves.
var trick_history: Array[Dictionary] = []
var _ai_timer: float = 0.0
var _ai_pending: bool = false
var _trick_display_timer: float = 0.0
var _trick_winner_seat: int = 0

const AI_DELAY_MIN := 0.5
const AI_DELAY_MAX := 1.0
const BOOKS_TO_WIN := 7
const TRICK_DISPLAY_DURATION := 2.0

## Start a new round.
## `player_list`: Array[Player] with exactly 4 players at seats 0-3
## `dealer`: seat index of the dealer for this round
func start_round(player_list: Array[Player], dealer: int) -> void:
	players = player_list
	dealer_seat = dealer
	trump_selector_seat = (dealer_seat + 1) % 4
	books = [0, 0]
	books_by_seat = [0, 0, 0, 0]
	trick_history.clear()
	deck = Deck.new()
	deck.shuffle()
	for p in players:
		p.clear_hand()
		if p is AIPlayer:
			(p as AIPlayer).clear_played_cards()
	# Reset pause flags — menu_paused may be stuck true if the player opened
	# settings and returned to main menu before a new session started.
	deal_paused = false
	menu_paused = false
	_ai_pending = false
	_set_state(RoundState.DEALING_INITIAL)

func _set_state(new_state: RoundState) -> void:
	state = new_state
	_process_state()

func _process_state() -> void:
	match state:
		RoundState.DEALING_INITIAL:
			_do_deal_initial()
		RoundState.TRUMP_SELECTION:
			_do_trump_selection()
		RoundState.DEALING_REMAINING:
			_do_deal_remaining()
		RoundState.PLAYER_TURN:
			_do_player_turn()
		RoundState.TRICK_DISPLAY:
			pass  # timer runs in tick()

func _do_deal_initial() -> void:
	var initial := deck.deal(5)
	players[trump_selector_seat].hand.add_cards(initial)
	hand_dealt.emit(trump_selector_seat, initial)
	_set_state(RoundState.TRUMP_SELECTION)

func _do_trump_selection() -> void:
	var selector := players[trump_selector_seat]
	trump_selection_needed.emit(trump_selector_seat, selector.hand.cards.duplicate())
	if not selector.is_human:
		_schedule_ai_action()

func _do_deal_remaining() -> void:
	# Each player needs 13 cards total.
	# Trump selector already has 5 — the target for all players is 13.
	var needs: Array[int] = [13, 13, 13, 13]

	# Deal clockwise starting from trump selector until all hands are full
	var seat := trump_selector_seat
	var iterations := 0
	while deck.remaining() > 0 and iterations < 52:
		iterations += 1
		var player := players[seat]
		var target := needs[seat]
		if player.hand.size() < target:
			var amount := mini(target - player.hand.size(), deck.remaining())
			var new_cards := deck.deal(amount)
			player.hand.add_cards(new_cards)
			hand_dealt.emit(seat, new_cards)
		seat = (seat + 1) % 4

	for p in players:
		assert(p.hand.size() == 13, "Player %d has %d cards, expected 13" % [p.seat_index, p.hand.size()])

	# Trump selector leads the first trick
	current_player_seat = trump_selector_seat
	current_trick = Trick.new(trump_suit)
	_set_state(RoundState.PLAYER_TURN)

func _do_player_turn() -> void:
	var player := players[current_player_seat]
	var valid := player.hand.get_valid_cards(current_trick.led_suit, trump_suit)
	turn_started.emit(current_player_seat, valid)
	if not player.is_human:
		_schedule_ai_action()

func _schedule_ai_action() -> void:
	var delay_min := AI_DELAY_MIN
	var delay_max := AI_DELAY_MAX
	# Pick the seat of the AI currently acting.
	var active_seat := trump_selector_seat if state == RoundState.TRUMP_SELECTION else current_player_seat
	var active_player := players[active_seat] if active_seat >= 0 and active_seat < players.size() else null
	if active_player is AIPlayer:
		match (active_player as AIPlayer).difficulty:
			AIPlayer.Difficulty.EASY:
				delay_min = 1.0
				delay_max = 1.5
			AIPlayer.Difficulty.HARD:
				delay_min = 0.5
				delay_max = 0.75
			_:
				delay_min = 0.75
				delay_max = 1.0
	_ai_pending = true
	_ai_timer = randf_range(delay_min, delay_max)

## Called each frame from the owner Node via _process(delta).
## Drives AI timing and trick display countdown without blocking the main thread.
func tick(delta: float) -> void:
	if deal_paused or menu_paused:
		return
	if state == RoundState.TRICK_DISPLAY:
		_trick_display_timer -= delta
		if _trick_display_timer <= 0.0:
			_after_trick_display()
		return
	if not _ai_pending:
		return
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_pending = false
		_execute_ai_action()

func _after_trick_display() -> void:
	if books[0] >= BOOKS_TO_WIN or books[1] >= BOOKS_TO_WIN:
		var winning_team := 0 if books[0] >= BOOKS_TO_WIN else 1
		_set_state(RoundState.ROUND_OVER)
		round_ended.emit(winning_team)
	else:
		current_player_seat = _trick_winner_seat
		current_trick = Trick.new(trump_suit)
		_set_state(RoundState.PLAYER_TURN)

func _execute_ai_action() -> void:
	match state:
		RoundState.TRUMP_SELECTION:
			_ai_select_trump()
		RoundState.PLAYER_TURN:
			_ai_play_card()

func _ai_select_trump() -> void:
	var ai := players[trump_selector_seat] as AIPlayer
	declare_trump(ai.choose_trump())

## Called by the human player's UI when they select a trump suit.
func declare_trump(suit: Card.Suit) -> void:
	trump_suit = suit
	trump_declared.emit(suit)
	_set_state(RoundState.DEALING_REMAINING)

func _ai_play_card() -> void:
	var ai := players[current_player_seat] as AIPlayer
	var valid := ai.hand.get_valid_cards(current_trick.led_suit, trump_suit)
	if valid.is_empty():
		push_error("RoundManager: AI seat %d has no valid cards" % current_player_seat)
		return
	var partner_seat := (current_player_seat + 2) % 4
	var card := ai.choose_card(valid, current_trick, partner_seat)
	play_card(current_player_seat, card)

## Called by the human player's UI when they play a card.
func play_card(seat: int, card: Card) -> void:
	assert(seat == current_player_seat, "Not this player's turn (expected %d, got %d)" % [current_player_seat, seat])
	players[seat].hand.remove_card(card)
	current_trick.play_card(seat, card)
	# Let every AI update its card-tracking state (used by Hard strategy).
	for p in players:
		if p is AIPlayer:
			(p as AIPlayer).track_played_card(seat, card, current_trick.led_suit)
	card_played_signal.emit(seat, card)

	if current_trick.is_complete():
		_resolve_trick()
	else:
		current_player_seat = (current_player_seat + 1) % 4
		_set_state(RoundState.PLAYER_TURN)

func _resolve_trick() -> void:
	_set_state(RoundState.TRICK_RESOLUTION)
	_trick_winner_seat = current_trick.get_winner_index()
	var winner_team := 0 if _trick_winner_seat in [0, 2] else 1
	books[winner_team] += 1
	books_by_seat[_trick_winner_seat] += 1
	trick_history.append(_build_trick_history_entry(winner_team))
	trick_completed.emit(_trick_winner_seat, books.duplicate(), books_by_seat.duplicate())
	# Pause for TRICK_DISPLAY_DURATION seconds so the UI can highlight the winning card
	_trick_display_timer = TRICK_DISPLAY_DURATION * Settings.anim_multiplier()
	_set_state(RoundState.TRICK_DISPLAY)

## Build one trick_history entry for the trick just resolved.
## Seat mapping: 0=bottom(You), 1=left(Left), 2=top(Partner), 3=right(Right)
func _build_trick_history_entry(winner_team: int) -> Dictionary:
	var seat_info := {
		0: {"position": "bottom", "player": "You"},
		1: {"position": "left", "player": "Left"},
		2: {"position": "top", "player": "Partner"},
		3: {"position": "right", "player": "Right"},
	}
	var cards_played: Array = []
	# Iterate in seat order 0..3 so the overlay list is stable regardless of
	# play order within the trick.
	for seat in range(4):
		var card := current_trick.get_card_for_player(seat)
		if card == null:
			continue
		var info: Dictionary = seat_info[seat]
		cards_played.append({
			"position": info["position"],
			"player": info["player"],
			"card": card,
		})
	return {
		"trick_number": trick_history.size() + 1,
		"winning_team": "player_team" if winner_team == 0 else "opponent_team",
		"winning_card": current_trick.get_card_for_player(_trick_winner_seat),
		"cards_played": cards_played,
	}
