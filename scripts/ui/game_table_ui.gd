extends Control

@onready var bottom_hand: HBoxContainer = $BottomHand
@onready var top_hand: HBoxContainer = $TopHand
@onready var left_hand: VBoxContainer = $MidRow/LeftHand
@onready var right_hand: VBoxContainer = $MidRow/RightHand
@onready var trick_area: Control = $MidRow/TrickArea
@onready var trump_label: Label = $HUD/HUDRow1/TrumpLabel
@onready var books_label: Label = $HUD/HUDRow1/BooksLabel
@onready var session_label: Label = $HUD/HUDRow2/SessionLabel
@onready var turn_label: Label = $HUD/HUDRow2/TurnLabel
@onready var timer_label: Label = $HUD/HUDRow2/TimerLabel

const CardScene := preload("res://scenes/card.tscn")
const TrumpSelectorScene := preload("res://scenes/ui/trump_selector.tscn")
const WinScreenScene := preload("res://scenes/ui/win_screen.tscn")

var _selected_card: Card = null
var _current_valid_cards: Array[Card] = []
var _trump_selector_overlay: Control = null
var _win_screen_overlay: Control = null
var _current_round_id: int = 0

func _ready() -> void:
	timer_label.visible = false  # multiplayer only: show when turn timer is active
	_connect_signals()
	_trump_selector_overlay = TrumpSelectorScene.instantiate()
	_trump_selector_overlay.visible = false
	add_child(_trump_selector_overlay)
	_win_screen_overlay = WinScreenScene.instantiate()
	_win_screen_overlay.visible = false
	add_child(_win_screen_overlay)
	GameState.start_session()

func _connect_signals() -> void:
	var rm := GameState.get_round_manager()
	rm.hand_dealt.connect(_on_hand_dealt)
	rm.trump_selection_needed.connect(_on_trump_selection_needed)
	rm.trump_declared.connect(_on_trump_declared)
	rm.turn_started.connect(_on_turn_started)
	rm.card_played_signal.connect(_on_card_played)
	rm.trick_completed.connect(_on_trick_completed)
	rm.round_ended.connect(_on_round_ended)
	GameState.round_started.connect(_on_round_started)

func _get_hand_container(seat: int) -> BoxContainer:
	match seat:
		0: return bottom_hand
		1: return top_hand
		2: return left_hand
		3: return right_hand
	return null

func _get_trick_slot(seat: int) -> Control:
	match seat:
		0: return trick_area.get_node("SouthSlot")
		1: return trick_area.get_node("NorthSlot")
		2: return trick_area.get_node("WestSlot")
		3: return trick_area.get_node("EastSlot")
	return null

func _on_hand_dealt(seat: int, cards: Array) -> void:
	var container := _get_hand_container(seat)
	if container == null:
		return
	var face_up := (seat == 0)
	for card in cards:
		var card_node := CardScene.instantiate() as PanelContainer
		if seat != 0:
			card_node.custom_minimum_size = Vector2(26, 38)
		card_node.call("setup", card, face_up)
		if face_up:
			card_node.connect("card_tapped", _on_card_tapped)
		container.add_child(card_node)
		if face_up:
			card_node.z_index = container.get_child_count()

func _on_trump_selection_needed(seat: int, initial_cards: Array) -> void:
	if seat == 0 and _trump_selector_overlay != null:
		_trump_selector_overlay.call("show_for_human", initial_cards)
		_trump_selector_overlay.visible = true

func _on_trump_declared(suit: Card.Suit) -> void:
	if _trump_selector_overlay != null:
		_trump_selector_overlay.visible = false
	trump_label.text = "Trump: " + Card.SUIT_NAMES[suit] + " " + Card.SUIT_SYMBOLS[suit]

func _on_turn_started(seat: int, valid_cards: Array) -> void:
	_current_valid_cards.clear()
	for c in valid_cards:
		_current_valid_cards.append(c as Card)
	var player := GameState.get_player(seat)
	if player != null:
		turn_label.text = player.display_name + "'s turn"
	if seat == 0:
		_highlight_valid_cards()

func _highlight_valid_cards() -> void:
	for child in bottom_hand.get_children():
		var card_data: Card = child.get("card_data")
		if card_data != null:
			child.call("set_valid", card_data in _current_valid_cards)

func _on_card_tapped(card: Card) -> void:
	if card not in _current_valid_cards:
		return
	if _selected_card == card:
		_confirm_play()
	else:
		if _selected_card != null:
			_deselect_current()
		_selected_card = card
		_select_in_hand(card)

func _select_in_hand(card: Card) -> void:
	for child in bottom_hand.get_children():
		if child.get("card_data") == card:
			child.call("set_selected", true)

func _deselect_current() -> void:
	if _selected_card == null:
		return
	for child in bottom_hand.get_children():
		if child.get("card_data") == _selected_card:
			child.call("set_selected", false)
	_selected_card = null

func _confirm_play() -> void:
	var card := _selected_card
	_selected_card = null
	_reset_hand_state()
	GameState.get_round_manager().play_card(0, card)

func _reset_hand_state() -> void:
	for child in bottom_hand.get_children():
		child.call("set_valid", true)
		child.call("set_selected", false)

func _on_card_played(seat: int, card: Card) -> void:
	var container := _get_hand_container(seat)
	if container != null:
		for child in container.get_children():
			if child.get("card_data") == card:
				child.queue_free()
				break
	var slot := _get_trick_slot(seat)
	if slot != null:
		var trick_card := CardScene.instantiate() as PanelContainer
		trick_card.call("setup", card, true)
		slot.add_child(trick_card)

func _on_trick_completed(winner_seat: int, books: Array) -> void:
	books_label.text = "Books — You: %d | Opp: %d" % [books[0], books[1]]
	var round_id := _current_round_id
	get_tree().create_timer(0.3).timeout.connect(func():
		if _current_round_id != round_id:
			return  # round changed, skip stale clear
		if is_instance_valid(trick_area):
			for slot_name in ["NorthSlot", "WestSlot", "EastSlot", "SouthSlot"]:
				var slot := trick_area.get_node_or_null(slot_name)
				if slot != null:
					for child in slot.get_children():
						child.queue_free()
	)

func _on_round_ended(winning_team: int) -> void:
	var wins := GameState.session_wins
	session_label.text = "Session — You: %d | Opp: %d" % [wins[0], wins[1]]
	if _win_screen_overlay != null:
		_win_screen_overlay.call("show_result", winning_team, wins)
		_win_screen_overlay.visible = true

func _clear_table() -> void:
	for container in [bottom_hand, top_hand, left_hand, right_hand]:
		for child in container.get_children():
			child.queue_free()
	for slot_name in ["NorthSlot", "WestSlot", "EastSlot", "SouthSlot"]:
		var slot := trick_area.get_node_or_null(slot_name)
		if slot != null:
			for child in slot.get_children():
				child.queue_free()
	_selected_card = null
	_current_valid_cards.clear()
	trump_label.text = "Trump: —"
	books_label.text = "Books — You: 0 | Opp: 0"
	turn_label.text = "—'s turn"

func _on_round_started(_dealer_seat: int, _trump_selector_seat: int) -> void:
	_current_round_id += 1
	_clear_table()
