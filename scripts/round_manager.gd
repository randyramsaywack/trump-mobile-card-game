class_name RoundManager
extends Node

signal hand_dealt(seat_index: int, cards: Array)
signal trump_selection_needed(seat_index: int, initial_cards: Array)
signal trump_declared(suit: Card.Suit)
signal turn_started(seat_index: int, valid_cards: Array)
signal card_played_signal(seat_index: int, card: Card)
signal trick_completed(winner_seat: int, books: Array)
signal round_ended(winning_team: int)

enum RoundState {
	IDLE,
	DEALING_INITIAL,
	TRUMP_SELECTION,
	DEALING_REMAINING,
	PLAYER_TURN,
	TRICK_RESOLUTION,
	ROUND_OVER
}

var state: RoundState = RoundState.IDLE
var players: Array[Player] = []
var deck: Deck
var trump_suit: Card.Suit
var dealer_seat: int
var trump_selector_seat: int
var current_player_seat: int
var current_trick: Trick
var books: Array[int] = [0, 0]  # [team0_books, team1_books]
var _ai_timer: float = 0.0
var _ai_pending: bool = false

const AI_DELAY_MIN := 0.5
const AI_DELAY_MAX := 1.0
const BOOKS_TO_WIN := 7

## Start a new round.
## `player_list`: Array[Player] with exactly 4 players at seats 0-3
## `dealer`: seat index of the dealer for this round
func start_round(player_list: Array[Player], dealer: int) -> void:
	players = player_list
	dealer_seat = dealer
	trump_selector_seat = (dealer_seat + 1) % 4
	books = [0, 0]
	deck = Deck.new()
	deck.shuffle()
	for p in players:
		p.clear_hand()
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
	_ai_pending = true
	_ai_timer = randf_range(AI_DELAY_MIN, AI_DELAY_MAX)

## Called each frame from the owner Node via _process(delta).
## Drives AI timing without blocking the main thread.
func tick(delta: float) -> void:
	if not _ai_pending:
		return
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_pending = false
		_execute_ai_action()

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
	var partner_seat := (current_player_seat + 2) % 4
	var card := ai.choose_card(valid, current_trick, partner_seat)
	play_card(current_player_seat, card)

## Called by the human player's UI when they play a card.
func play_card(seat: int, card: Card) -> void:
	assert(seat == current_player_seat, "Not this player's turn (expected %d, got %d)" % [current_player_seat, seat])
	players[seat].hand.remove_card(card)
	current_trick.play_card(seat, card)
	card_played_signal.emit(seat, card)

	if current_trick.is_complete():
		_resolve_trick()
	else:
		current_player_seat = (current_player_seat + 1) % 4
		_set_state(RoundState.PLAYER_TURN)

func _resolve_trick() -> void:
	_set_state(RoundState.TRICK_RESOLUTION)
	var winner_seat := current_trick.get_winner_index()
	var winner_team := 0 if winner_seat in [0, 1] else 1
	books[winner_team] += 1
	trick_completed.emit(winner_seat, books.duplicate())

	if books[0] >= BOOKS_TO_WIN or books[1] >= BOOKS_TO_WIN:
		var winning_team := 0 if books[0] >= BOOKS_TO_WIN else 1
		_set_state(RoundState.ROUND_OVER)
		round_ended.emit(winning_team)
	else:
		# Trick winner leads next trick
		current_player_seat = winner_seat
		current_trick = Trick.new(trump_suit)
		_set_state(RoundState.PLAYER_TURN)
