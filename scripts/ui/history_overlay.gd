extends Control

## Scrollable list of completed tricks for the current round.
## Informational only — never pauses or mutates game state.

signal closed()

const VisualStyle := preload("res://scripts/ui/visual_style.gd")

@onready var close_button: Button = $Panel/VBox/Header/CloseButton
@onready var list_container: VBoxContainer = $Panel/VBox/Scroll/List
@onready var empty_label: Label = $Panel/VBox/EmptyLabel
@onready var scroll: ScrollContainer = $Panel/VBox/Scroll
@onready var title_label: Label = $Panel/VBox/Header/Title
@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Panel

const COLOR_SUIT_RED := Color(0.95, 0.42, 0.38)
const COLOR_SUIT_BLACK := Color(0.85, 0.85, 0.85)
const COLOR_GOLD := Color(0.95, 0.82, 0.38)
const COLOR_WIN_BG := Color(0.95, 0.82, 0.18, 0.28)
const COLOR_WIN_BORDER := Color(1.0, 0.9, 0.22)
const COLOR_ROW_BG := Color(0.04, 0.11, 0.075, 0.42)
const COLOR_ROW_BORDER := Color(1.0, 1.0, 1.0, 0.08)
const COLOR_TEXT_DIM := Color(0.75, 0.75, 0.75)
const COLOR_TEXT := Color(0.92, 0.92, 0.92)

# Ordered seat/position keys so every row always lays out You, Partner, Left, Right.
const POSITION_ORDER: Array[String] = ["bottom", "top", "left", "right"]

func _ready() -> void:
	_apply_mockup_style()
	close_button.pressed.connect(_on_close_pressed)
	SuitFont.apply(close_button)
	if "--shot-history-overlay" in OS.get_cmdline_user_args():
		call_deferred("_show_screenshot_sample")

func _apply_mockup_style() -> void:
	VisualStyle.apply_felt_background(self)
	dim.color = Color(0, 0, 0, 0.14)
	panel.anchor_left = 0.035
	panel.anchor_top = 0.06
	panel.anchor_right = 0.965
	panel.anchor_bottom = 0.94
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	panel.add_theme_stylebox_override("panel", VisualStyle.panel_style(0.44, 10, 0.72))
	title_label.text = "TRICK HISTORY"
	VisualStyle.apply_title(title_label, 22)
	close_button.text = "×"
	VisualStyle.apply_button(close_button, "normal")
	VisualStyle.apply_label(empty_label, 14, VisualStyle.TEXT_DIM)

## Refresh the list from the provided trick_history array and show the overlay.
## `history` is the array owned by RoundManager — callers pass it directly.
func show_history(history: Array) -> void:
	_clear_list()
	if history.is_empty():
		empty_label.visible = true
		scroll.visible = false
	else:
		empty_label.visible = false
		scroll.visible = true
		for entry in history:
			list_container.add_child(_build_trick_row(entry as Dictionary))
		# Jump to the most recent trick at the bottom of the list.
		await get_tree().process_frame
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	visible = true

func _clear_list() -> void:
	for child in list_container.get_children():
		child.queue_free()

func _show_screenshot_sample() -> void:
	var trick_1_win := Card.new(Card.Suit.HEARTS, Card.Rank.ACE)
	var trick_2_win := Card.new(Card.Suit.SPADES, Card.Rank.KING)
	show_history([
		{
			"trick_number": 1,
			"winning_team": "player_team",
			"winning_card": trick_1_win,
			"cards_played": [
				{"position": "bottom", "player": "Randy", "card": trick_1_win},
				{"position": "top", "player": "Jamie", "card": Card.new(Card.Suit.HEARTS, Card.Rank.QUEEN)},
				{"position": "left", "player": "Alex", "card": Card.new(Card.Suit.HEARTS, Card.Rank.TEN)},
				{"position": "right", "player": "Morgan", "card": Card.new(Card.Suit.CLUBS, Card.Rank.TWO)},
			],
		},
		{
			"trick_number": 2,
			"winning_team": "opponents",
			"winning_card": trick_2_win,
			"cards_played": [
				{"position": "bottom", "player": "Randy", "card": Card.new(Card.Suit.SPADES, Card.Rank.FOUR)},
				{"position": "top", "player": "Jamie", "card": Card.new(Card.Suit.SPADES, Card.Rank.NINE)},
				{"position": "left", "player": "Alex", "card": trick_2_win},
				{"position": "right", "player": "Morgan", "card": Card.new(Card.Suit.SPADES, Card.Rank.JACK)},
			],
		},
	])

func _build_trick_row(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_ROW_BG
	panel_style.border_color = COLOR_ROW_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", panel_style)

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(row)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var num_label := Label.new()
	num_label.text = "%d" % int(entry["trick_number"])
	num_label.add_theme_color_override("font_color", COLOR_GOLD)
	num_label.add_theme_font_size_override("font_size", 20)
	header.add_child(num_label)

	var winner_label := Label.new()
	var winning_team := String(entry["winning_team"])
	winner_label.text = "Your Team won" if winning_team == "player_team" else "Opponents won"
	winner_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	winner_label.add_theme_font_size_override("font_size", 11)
	winner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(winner_label)

	row.add_child(header)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 10)
	var winning_card: Card = entry["winning_card"] as Card
	var by_pos: Dictionary = {}
	for c in entry["cards_played"]:
		by_pos[String((c as Dictionary)["position"])] = c
	for pos in POSITION_ORDER:
		if not by_pos.has(pos):
			continue
		var cd: Dictionary = by_pos[pos]
		cards_row.add_child(_build_card_chip(cd, winning_card))
	row.add_child(cards_row)

	return panel

func _build_card_chip(card_entry: Dictionary, winning_card: Card) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 1)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(container)

	var player_label := Label.new()
	player_label.text = String(card_entry["player"])
	player_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	player_label.add_theme_font_size_override("font_size", 10)
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(player_label)

	var card: Card = card_entry["card"] as Card
	var is_winner := _same_card(card, winning_card)
	if is_winner:
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_WIN_BG
		style.border_color = COLOR_WIN_BORDER
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		panel.add_theme_stylebox_override("panel", style)
		player_label.add_theme_color_override("font_color", COLOR_WIN_BORDER)
	var card_label := Label.new()
	card_label.text = Card.RANK_NAMES[card.rank] + Card.SUIT_SYMBOLS[card.suit]
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.add_theme_font_size_override("font_size", 16)
	SuitFont.apply(card_label)
	var is_red := card.suit == Card.Suit.HEARTS or card.suit == Card.Suit.DIAMONDS
	if is_winner:
		card_label.add_theme_color_override("font_color", COLOR_WIN_BORDER)
	else:
		card_label.add_theme_color_override("font_color", COLOR_SUIT_RED if is_red else COLOR_TEXT)
	container.add_child(card_label)
	return panel

func _same_card(a: Card, b: Card) -> bool:
	return a != null and b != null and a.suit == b.suit and a.rank == b.rank

func _on_close_pressed() -> void:
	visible = false
	closed.emit()
