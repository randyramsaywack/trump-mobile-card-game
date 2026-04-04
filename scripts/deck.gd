class_name Deck

var cards: Array[Card] = []

func _init() -> void:
	_build()

func _build() -> void:
	cards.clear()
	for s in Card.Suit.values():
		for r in Card.Rank.values():
			cards.append(Card.new(s as Card.Suit, r as Card.Rank))
	# Sanity: 4 suits * 13 ranks = 52 cards
	assert(cards.size() == 52, "Deck must have 52 cards, got %d" % cards.size())

func shuffle() -> void:
	cards.shuffle()

## Deal `count` cards off the top (end of array = top).
## Returns array of dealt cards. Modifies deck in place.
func deal(count: int) -> Array[Card]:
	count = mini(count, cards.size())
	var dealt: Array[Card] = []
	for _i in range(count):
		dealt.append(cards.pop_back())
	return dealt

func remaining() -> int:
	return cards.size()
