extends PanelContainer

@onready var rank_label: Label = $VBox/RankLabel
@onready var suit_label: Label = $VBox/SuitLabel

var card_data: Card = null
var _is_valid: bool = true
var _is_selected: bool = false

signal card_tapped(card: Card)

const SUIT_COLORS: Dictionary = {
	Card.Suit.SPADES: Color.BLACK,
	Card.Suit.CLUBS: Color.BLACK,
	Card.Suit.HEARTS: Color(0.8, 0.1, 0.1),
	Card.Suit.DIAMONDS: Color(0.8, 0.1, 0.1)
}

func setup(c: Card, face_up: bool = true) -> void:
	card_data = c
	if face_up:
		_show_face()
	else:
		_show_back()

func _show_face() -> void:
	rank_label.text = Card.RANK_NAMES[card_data.rank]
	suit_label.text = Card.SUIT_SYMBOLS[card_data.suit]
	var color: Color = SUIT_COLORS[card_data.suit]
	rank_label.add_theme_color_override("font_color", color)
	suit_label.add_theme_color_override("font_color", color)

func _show_back() -> void:
	rank_label.text = ""
	suit_label.text = "?"
	rank_label.add_theme_color_override("font_color", Color.WHITE)
	suit_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.5))

func set_valid(valid: bool) -> void:
	_is_valid = valid
	modulate.a = 1.0 if valid else 0.4

func set_selected(selected: bool) -> void:
	_is_selected = selected
	position.y = -20.0 if selected else 0.0

func _gui_input(event: InputEvent) -> void:
	if card_data == null or not _is_valid:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			card_tapped.emit(card_data)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			card_tapped.emit(card_data)
			get_viewport().set_input_as_handled()
