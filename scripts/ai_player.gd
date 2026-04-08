class_name AIPlayer
extends Player

enum Difficulty { EASY, MEDIUM, HARD }

var difficulty: int = Difficulty.MEDIUM
## All cards played this round (any seat) — used by Hard strategy.
var played_cards: Array[Card] = []
## Per-seat known exhausted suits: { seat_index: { suit_int: true } }
var _seat_exhausted: Dictionary = {}

func _init(idx: int, name: String) -> void:
	super._init(idx, name, false)

## Called by round_manager at the start of each round.
func clear_played_cards() -> void:
	played_cards.clear()
	_seat_exhausted.clear()

## Called by round_manager after every card play (including our own).
## `led_suit` is the suit of the first card of the current trick.
func track_played_card(seat: int, card: Card, led_suit: int) -> void:
	played_cards.append(card)
	# If this was not the lead card and the player did not follow suit,
	# they are now known to be out of the led suit.
	if led_suit != -1 and int(card.suit) != led_suit:
		if not _seat_exhausted.has(seat):
			_seat_exhausted[seat] = {}
		_seat_exhausted[seat][led_suit] = true

## Choose trump suit — routes to the strategy for the current difficulty.
func choose_trump() -> Card.Suit:
	match difficulty:
		Difficulty.EASY:
			return _choose_trump_easy()
		Difficulty.HARD:
			return _choose_trump_hard()
		_:
			return _choose_trump_medium()

## Choose which card to play — routes to the strategy for the current difficulty.
func choose_card(valid_cards: Array[Card], current_trick: Trick, partner_seat: int) -> Card:
	if valid_cards.size() == 1:
		return valid_cards[0]
	match difficulty:
		Difficulty.EASY:
			# Opponents (team 1) play worst cards; partner uses medium strategy.
			if seat_index in [1, 3]:
				return _choose_card_easy(valid_cards, current_trick, partner_seat)
			return _choose_card_medium(valid_cards, current_trick, partner_seat)
		Difficulty.HARD:
			return _choose_card_hard(valid_cards, current_trick, partner_seat)
		_:
			return _choose_card_medium(valid_cards, current_trick, partner_seat)

# -----------------------------------------------------------------------------
# EASY — purely random
# -----------------------------------------------------------------------------

func _choose_trump_easy() -> Card.Suit:
	var suits := Card.Suit.values()
	return suits[randi() % suits.size()] as Card.Suit

func _choose_card_easy(valid_cards: Array[Card], current_trick: Trick, partner_seat: int) -> Card:
	var trump: Card.Suit = current_trick.trump_suit

	# Leading — waste highest non-trump card to give opponents an easy win.
	if current_trick.cards_played() == 0:
		var non_trump: Array[Card] = valid_cards.filter(
			func(c: Card) -> bool: return c.suit != trump
		)
		if not non_trump.is_empty():
			return hand.highest_card(non_trump)
		return hand.lowest_card(valid_cards)

	var current_winner_idx := _trick_current_winner_index(current_trick)
	var partner_is_winning := (current_winner_idx == partner_seat)

	# Partner is winning — waste highest card to burn good cards for nothing.
	if partner_is_winning:
		return hand.highest_card(valid_cards)

	# Opponent is winning — dump lowest card, don't try to win.
	var discard: Array[Card] = valid_cards.filter(
		func(c: Card) -> bool: return c.suit != trump
	)
	if not discard.is_empty():
		return hand.lowest_card(discard)
	return hand.lowest_card(valid_cards)

# -----------------------------------------------------------------------------
# MEDIUM — pick dominant suit for trump, basic follow/win/discard heuristics
# -----------------------------------------------------------------------------

func _choose_trump_medium() -> Card.Suit:
	return hand.dominant_suit()

func _choose_card_medium(valid_cards: Array[Card], current_trick: Trick, partner_seat: int) -> Card:
	var trump: Card.Suit = current_trick.trump_suit

	# Leading — play lowest card (conservative)
	if current_trick.cards_played() == 0:
		return hand.lowest_card(valid_cards)

	var current_winner_idx := _trick_current_winner_index(current_trick)
	var partner_is_winning := (current_winner_idx == partner_seat)

	# Partner winning — discard lowest non-trump
	if partner_is_winning:
		var non_trump_p: Array[Card] = valid_cards.filter(
			func(c: Card) -> bool: return c.suit != trump
		)
		if not non_trump_p.is_empty():
			return hand.lowest_card(non_trump_p)
		return hand.lowest_card(valid_cards)

	# Try to win with lowest winning card
	var winning_card := _find_lowest_winner(valid_cards, current_trick)
	if winning_card != null:
		return winning_card

	# Can't win — play trump if trick wasn't trump-led
	if current_trick.led_suit != trump:
		var trump_cards: Array[Card] = valid_cards.filter(
			func(c: Card) -> bool: return c.suit == trump
		)
		if not trump_cards.is_empty():
			return hand.lowest_card(trump_cards)

	# Can't win, can't trump — discard lowest
	return hand.lowest_card(valid_cards)

# -----------------------------------------------------------------------------
# HARD — card tracking, suit exhaustion awareness, trump conservation
# -----------------------------------------------------------------------------

func _choose_trump_hard() -> Card.Suit:
	# Score = cards_in_suit * 2 + number of high cards (J/Q/K/A) in that suit.
	var best_suit: Card.Suit = Card.Suit.SPADES
	var best_score := -1
	for s in Card.Suit.values():
		var suit := s as Card.Suit
		var suit_cards := hand.cards_of_suit(suit)
		var score := suit_cards.size() * 2
		for c in suit_cards:
			if c.rank >= Card.Rank.JACK:
				score += 1
		if score > best_score:
			best_score = score
			best_suit = suit
	return best_suit

func _choose_card_hard(valid_cards: Array[Card], current_trick: Trick, partner_seat: int) -> Card:
	var trump: Card.Suit = current_trick.trump_suit

	# Leading the trick
	if current_trick.cards_played() == 0:
		return _hard_lead(valid_cards, trump)

	var current_winner_idx := _trick_current_winner_index(current_trick)
	var current_winner_card := _trick_current_winning_card(current_trick)
	var partner_is_winning := (current_winner_idx == partner_seat)

	# Partner winning — discard lowest non-trump (save trump)
	if partner_is_winning:
		var non_trump_p: Array[Card] = valid_cards.filter(
			func(c: Card) -> bool: return c.suit != trump
		)
		if not non_trump_p.is_empty():
			return hand.lowest_card(non_trump_p)
		return hand.lowest_card(valid_cards)

	var winners: Array[Card] = valid_cards.filter(
		func(c: Card) -> bool: return c.beats(
			current_winner_card,
			current_trick.led_suit as Card.Suit,
			trump
		)
	)
	var cards_remaining := 4 - current_trick.cards_played()
	var is_last_to_play := (cards_remaining == 1)

	if not winners.is_empty():
		var lowest_winner := hand.lowest_card(winners)
		# Trump conservation: if winning would require burning a trump and
		# we're not last to play and the trick has no high card yet, save trump.
		if lowest_winner.suit == trump and current_trick.led_suit != trump:
			var trick_has_high := _trick_contains_high_card(current_trick)
			if not is_last_to_play and not trick_has_high:
				var non_trump_d: Array[Card] = valid_cards.filter(
					func(c: Card) -> bool: return c.suit != trump
				)
				if not non_trump_d.is_empty():
					return hand.lowest_card(non_trump_d)
			return lowest_winner
		return lowest_winner

	# Can't win — discard lowest non-trump if possible (never waste trump on a loss)
	var non_trump: Array[Card] = valid_cards.filter(
		func(c: Card) -> bool: return c.suit != trump
	)
	if not non_trump.is_empty():
		return hand.lowest_card(non_trump)
	return hand.lowest_card(valid_cards)

## Hard-mode leading strategy.
func _hard_lead(valid_cards: Array[Card], trump: Card.Suit) -> Card:
	var non_trump: Array[Card] = valid_cards.filter(
		func(c: Card) -> bool: return c.suit != trump
	)
	if non_trump.is_empty():
		# Only trump — lead lowest trump
		return hand.lowest_card(valid_cards)

	# Prefer to lead an Ace or King in a suit opponents may still have.
	# Rank non-trump high cards, skipping suits where both opponents are exhausted.
	var opponents: Array[int] = _opponent_seats()
	var safe_highs: Array[Card] = []
	for c in non_trump:
		if c.rank >= Card.Rank.KING and not _both_opponents_out_of(c.suit, opponents):
			safe_highs.append(c)
	if not safe_highs.is_empty():
		return hand.highest_card(safe_highs)

	# No guaranteed-winner high cards — lead the lowest non-trump to probe.
	return hand.lowest_card(non_trump)

# -----------------------------------------------------------------------------
# Shared helpers
# -----------------------------------------------------------------------------

func _trick_current_winner_index(trick: Trick) -> int:
	if trick.cards_played() == 0:
		return -1
	var winning_entry: Dictionary = trick.played[0]
	for i in range(1, trick.played.size()):
		var entry: Dictionary = trick.played[i]
		var challenger: Card = entry["card"] as Card
		var cur_winner_card: Card = winning_entry["card"] as Card
		if challenger.beats(cur_winner_card, trick.led_suit as Card.Suit, trick.trump_suit):
			winning_entry = entry
	return winning_entry["player_index"]

func _trick_current_winning_card(trick: Trick) -> Card:
	if trick.cards_played() == 0:
		return null
	var winning_entry: Dictionary = trick.played[0]
	for i in range(1, trick.played.size()):
		var entry: Dictionary = trick.played[i]
		var challenger: Card = entry["card"] as Card
		var cur_winner_card: Card = winning_entry["card"] as Card
		if challenger.beats(cur_winner_card, trick.led_suit as Card.Suit, trick.trump_suit):
			winning_entry = entry
	return winning_entry["card"] as Card

func _trick_contains_high_card(trick: Trick) -> bool:
	for entry in trick.played:
		var c: Card = entry["card"] as Card
		if c.rank >= Card.Rank.JACK:
			return true
	return false

func _find_lowest_winner(valid_cards: Array[Card], trick: Trick) -> Card:
	var current_winner_card := _trick_current_winning_card(trick)
	if current_winner_card == null:
		return null
	var winners: Array[Card] = valid_cards.filter(
		func(c: Card) -> bool: return c.beats(current_winner_card, trick.led_suit as Card.Suit, trick.trump_suit)
	)
	if winners.is_empty():
		return null
	return hand.lowest_card(winners)

func _opponent_seats() -> Array[int]:
	var out: Array[int] = []
	out.append((seat_index + 1) % 4)
	out.append((seat_index + 3) % 4)
	return out

func _both_opponents_out_of(suit: Card.Suit, opponents: Array[int]) -> bool:
	for opp in opponents:
		if not _seat_exhausted.has(opp):
			return false
		if not _seat_exhausted[opp].has(int(suit)):
			return false
	return true
