class_name AIPlayer
extends Player

func _init(idx: int, name: String) -> void:
	super._init(idx, name, false)

## Choose trump suit: pick the suit with most cards in hand.
func choose_trump() -> Card.Suit:
	return hand.dominant_suit()

## Choose which card to play.
## `valid_cards`: cards already filtered by follow-suit rules
## `current_trick`: the Trick in progress (may have 0-3 cards played)
## `partner_seat`: seat index of this AI's partner
func choose_card(valid_cards: Array[Card], current_trick: Trick, partner_seat: int) -> Card:
	if valid_cards.size() == 1:
		return valid_cards[0]

	var trump := current_trick.trump_suit

	# Case 1: Leading the trick — play lowest card (conservative)
	if current_trick.cards_played() == 0:
		return hand.lowest_card(valid_cards)

	# Determine if partner is currently winning
	var current_winner_idx := current_trick.get_winner_index() if current_trick.cards_played() > 0 else -1
	var partner_is_winning := (current_winner_idx == partner_seat)

	# Case 2: Partner is currently winning — discard lowest non-trump card
	if partner_is_winning:
		var non_trump: Array[Card] = valid_cards.filter(func(c: Card) -> bool: return c.suit != trump)
		if not non_trump.is_empty():
			return hand.lowest_card(non_trump)
		return hand.lowest_card(valid_cards)

	# Case 3: Try to win with lowest winning card
	var winning_card := _find_lowest_winner(valid_cards, current_trick)
	if winning_card != null:
		return winning_card

	# Case 4: Can't win — play trump if possible (and trick wasn't trump-led)
	if current_trick.led_suit != trump:
		var trump_cards: Array[Card] = valid_cards.filter(func(c: Card) -> bool: return c.suit == trump)
		if not trump_cards.is_empty():
			return hand.lowest_card(trump_cards)

	# Case 5: Can't win, can't trump — discard lowest
	return hand.lowest_card(valid_cards)

## Finds the lowest-ranked card in `valid_cards` that beats the current trick winner.
## Returns null if no card in valid_cards can win.
func _find_lowest_winner(valid_cards: Array[Card], trick: Trick) -> Card:
	if trick.cards_played() == 0:
		return null
	# Find current winning card by iterating played entries
	var winning_entry: Dictionary = trick.played[0]
	for i in range(1, trick.played.size()):
		var entry: Dictionary = trick.played[i]
		var challenger: Card = entry["card"] as Card
		var current_winner_card: Card = winning_entry["card"] as Card
		if challenger.beats(current_winner_card, trick.led_suit as Card.Suit, trick.trump_suit):
			winning_entry = entry
	var winning_card: Card = winning_entry["card"] as Card

	var winners: Array[Card] = valid_cards.filter(
		func(c: Card) -> bool: return c.beats(winning_card, trick.led_suit as Card.Suit, trick.trump_suit)
	)
	if winners.is_empty():
		return null
	return hand.lowest_card(winners)
