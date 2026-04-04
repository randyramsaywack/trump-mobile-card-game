extends PanelContainer

@onready var face_content: Control = $FaceContent
@onready var top_rank: Label = $FaceContent/TopRank
@onready var top_suit: Label = $FaceContent/TopSuit
@onready var center_suit: Label = $FaceContent/CenterSuit
@onready var back_content: ColorRect = $BackContent

var card_data: Card = null
var _face_up: bool = true
var _is_valid: bool = true

signal card_tapped(card: Card)

const RED := Color(0.78, 0.08, 0.08)
const BLACK := Color(0.05, 0.05, 0.05)

func setup(c: Card, face_up: bool = true) -> void:
	card_data = c
	_face_up = face_up
	if is_inside_tree():
		_apply_display()

func _ready() -> void:
	if card_data != null:
		_apply_display()

func _apply_display() -> void:
	if _face_up:
		_show_face()
	else:
		_show_back()

func _show_face() -> void:
	face_content.visible = true
	back_content.visible = false
	var color := RED if card_data.suit in [Card.Suit.HEARTS, Card.Suit.DIAMONDS] else BLACK
	top_rank.text = Card.RANK_NAMES[card_data.rank]
	top_suit.text = Card.SUIT_SYMBOLS[card_data.suit]
	center_suit.text = Card.SUIT_SYMBOLS[card_data.suit]
	top_rank.add_theme_color_override("font_color", color)
	top_suit.add_theme_color_override("font_color", color)
	center_suit.add_theme_color_override("font_color", color)

func _show_back() -> void:
	face_content.visible = false
	back_content.visible = true

func set_valid(valid: bool) -> void:
	_is_valid = valid
	modulate.a = 1.0 if valid else 0.45

func set_selected(selected: bool) -> void:
	position.y = -15.0 if selected else 0.0

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
