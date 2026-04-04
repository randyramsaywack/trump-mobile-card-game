class_name Player

## Seat indices: 0=bottom(human), 1=top(partner), 2=left, 3=right
## Teams: 0+1 = team 0, 2+3 = team 1
var seat_index: int
var display_name: String
var hand: Hand
var is_human: bool

func _init(idx: int, name: String, human: bool) -> void:
	seat_index = idx
	display_name = name
	hand = Hand.new()
	is_human = human

func team() -> int:
	return 0 if seat_index in [0, 1] else 1

func clear_hand() -> void:
	hand = Hand.new()
