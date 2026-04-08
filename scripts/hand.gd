class_name Hand

## Suit ordering used by sort_hand() — left to right on display.
const SUIT_SORT_ORDER: Array = [Card.Suit.HEARTS, Card.Suit.SPADES, Card.Suit.DIAMONDS, Card.Suit.CLUBS]

var cards: Array[Card] = []

## Sort cards in place by suit (HEARTS, SPADES, DIAMONDS, CLUBS) then by rank
## ascending (2..Ace). Purely cosmetic — game logic never depends on order.
func sort_hand() -> void:
	cards.sort_custom(func(a: Card, b: Card) -> bool:
		var sa := SUIT_SORT_ORDER.find(a.suit)
		var sb := SUIT_SORT_ORDER.find(b.suit)
		if sa != sb:
			return sa < sb
		return a.rank < b.rank
	)

func add_cards(new_cards: Array[Card]) -> void:
	cards.append_array(new_cards)

func remove_card(card: Card) -> bool:
	var idx := cards.find(card)
	if idx >= 0:
		cards.remove_at(idx)
		return true
	return false

## Returns the subset of cards the player is allowed to play.
## `led_suit`: the suit of the first card played in this trick.
##             Pass -1 if this player is leading (all cards valid).
## `trump_suit`: the current trump suit (passed for context, no restriction on trump).
func get_valid_cards(led_suit: int, _trump_suit: Card.Suit) -> Array[Card]:
	# Leading — all cards valid
	if led_suit == -1:
		return cards.duplicate()
	var led := led_suit as Card.Suit
	# Must follow led suit if possible
	var suit_cards: Array[Card] = cards.filter(func(c: Card) -> bool: return c.suit == led)
	if not suit_cards.is_empty():
		return suit_cards
	# Cannot follow suit — any card is valid
	return cards.duplicate()

func has_suit(suit: Card.Suit) -> bool:
	return cards.any(func(c: Card) -> bool: return c.suit == suit)

func size() -> int:
	return cards.size()

func is_empty() -> bool:
	return cards.is_empty()

## For AI: returns all cards of a given suit
func cards_of_suit(suit: Card.Suit) -> Array[Card]:
	return cards.filter(func(c: Card) -> bool: return c.suit == suit)

## For AI: returns lowest card by rank from a given array
func lowest_card(from: Array[Card]) -> Card:
	if from.is_empty():
		return null
	var lowest: Card = from[0]
	for c in from.slice(1):
		if c.rank < lowest.rank:
			lowest = c
	return lowest

## For AI: returns highest card by rank from a given array
func highest_card(from: Array[Card]) -> Card:
	if from.is_empty():
		return null
	var highest: Card = from[0]
	for c in from.slice(1):
		if c.rank > highest.rank:
			highest = c
	return highest

## For AI: returns the suit with the most cards in this hand
func dominant_suit() -> Card.Suit:
	var counts: Dictionary = {}
	for s in Card.Suit.values():
		counts[s] = cards_of_suit(s as Card.Suit).size()
	var best_suit: Card.Suit = Card.Suit.SPADES
	var best_count := 0
	for s in counts:
		if counts[s] > best_count:
			best_count = counts[s]
			best_suit = s as Card.Suit
	return best_suit
