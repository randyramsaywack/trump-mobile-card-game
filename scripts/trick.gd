class_name Trick

## Each entry: { "player_index": int, "card": Card }
var played: Array[Dictionary] = []
var led_suit: int = -1  # -1 until first card played; cast to Card.Suit after
var trump_suit: Card.Suit

func _init(trump: Card.Suit) -> void:
	trump_suit = trump

func play_card(player_index: int, card: Card) -> void:
	assert(played.size() < 4, "Trick is already complete")
	if played.is_empty():
		led_suit = card.suit
	played.append({"player_index": player_index, "card": card})

func is_complete() -> bool:
	return played.size() == 4

## Returns the player_index of the trick winner.
## Must only be called when is_complete() is true.
func get_winner_index() -> int:
	assert(is_complete(), "Cannot get winner of incomplete trick")
	var winning: Dictionary = played[0]
	for i in range(1, played.size()):
		var entry: Dictionary = played[i]
		var challenger: Card = entry["card"] as Card
		var current_winner: Card = winning["card"] as Card
		if challenger.beats(current_winner, led_suit as Card.Suit, trump_suit):
			winning = entry
	return winning["player_index"]

func cards_played() -> int:
	return played.size()

func get_card_for_player(player_index: int) -> Card:
	for entry in played:
		if entry["player_index"] == player_index:
			return entry["card"] as Card
	return null
