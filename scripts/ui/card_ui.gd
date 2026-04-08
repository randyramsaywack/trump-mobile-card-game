extends PanelContainer

@onready var face_content: Control = $FaceContent
@onready var top_rank: Label = $FaceContent/TopRank
@onready var top_suit: Label = $FaceContent/TopSuit
@onready var center_suit: Label = $FaceContent/CenterSuit
@onready var bottom_rank: Label = $FaceContent/BottomRank
@onready var bottom_suit: Label = $FaceContent/BottomSuit
@onready var back_content: PanelContainer = $BackContent

var card_data: Card = null
var _face_up: bool = true
var _is_valid: bool = true
var _selected: bool = false
var _highlight_valid: bool = false

signal card_tapped(card: Card)
signal card_play_requested(card: Card)

# --- Visual constants ---
const COLOR_SUIT_RED := Color(0.753, 0.224, 0.169)       # #c0392b
const COLOR_SUIT_BLACK := Color(0.102, 0.102, 0.102)     # #1a1a1a
const COLOR_CARD_BG := Color(1, 1, 1, 1)                 # #ffffff
const COLOR_CARD_BORDER := Color(0.8, 0.8, 0.8, 1)       # #cccccc
const COLOR_GOLD := Color(0.788, 0.659, 0.298)           # #c9a84c
const COLOR_SHADOW := Color(0, 0, 0, 0.4)
const CORNER_RADIUS := 8
const BORDER_VALID := 3
const BORDER_SELECTED := 4
const INVALID_ALPHA := 0.5
const SELECT_RAISE_PX := 15.0

const DOUBLE_TAP_MS := 350
const DRAG_UP_THRESHOLD := 50.0
const REORDER_THRESHOLD := 20.0

var _last_tap_time: int = 0
var _drag_start_x_global: float = 0.0
var _drag_start_y_global: float = 0.0
var _drag_active: bool = false
var _reorder_active: bool = false

var _style_default: StyleBoxFlat
var _style_valid: StyleBoxFlat
var _style_selected: StyleBoxFlat

func setup(c: Card, face_up: bool = true) -> void:
	card_data = c
	_face_up = face_up
	if is_inside_tree():
		_apply_display()

## Public toggle used by flip animations (swap face mid-tween).
func set_face_up(face_up: bool) -> void:
	_face_up = face_up
	if is_inside_tree():
		_apply_display()

func _ready() -> void:
	# Safety net: ensure suit glyphs render on all platforms.
	SuitFont.apply(top_suit)
	SuitFont.apply(center_suit)
	SuitFont.apply(bottom_suit)
	_build_face_styles()
	# Show back even when card_data is null (e.g. shuffle animation placeholders)
	if card_data != null or not _face_up:
		_apply_display()
	_apply_state_style()

func _build_face_styles() -> void:
	_style_default = _make_face_style(COLOR_CARD_BORDER, 1)
	_style_valid = _make_face_style(COLOR_GOLD, BORDER_VALID)
	_style_selected = _make_face_style(COLOR_GOLD, BORDER_SELECTED)

func _make_face_style(border_color: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_CARD_BG
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.shadow_color = COLOR_SHADOW
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb

func _apply_display() -> void:
	if _face_up:
		_show_face()
	else:
		_show_back()

func _show_face() -> void:
	face_content.visible = true
	back_content.visible = false
	var color := COLOR_SUIT_RED if card_data.suit in [Card.Suit.HEARTS, Card.Suit.DIAMONDS] else COLOR_SUIT_BLACK
	var rank_text: String = Card.RANK_NAMES[card_data.rank]
	var suit_text: String = Card.SUIT_SYMBOLS[card_data.suit]
	top_rank.text = rank_text
	top_suit.text = suit_text
	center_suit.text = suit_text
	bottom_rank.text = rank_text
	bottom_suit.text = suit_text
	for lbl in [top_rank, top_suit, center_suit, bottom_rank, bottom_suit]:
		lbl.add_theme_color_override("font_color", color)

func _show_back() -> void:
	face_content.visible = false
	back_content.visible = true

func set_valid(valid: bool) -> void:
	_is_valid = valid
	_apply_state_style()

func set_selected(selected: bool) -> void:
	_selected = selected
	_apply_state_style()
	_apply_raise()

func _apply_raise() -> void:
	position.y = -SELECT_RAISE_PX if _selected else 0.0

func _notification(what: int) -> void:
	# Parent HBoxContainer resets position.y to 0 when it re-sorts children.
	# Re-apply the raise after each sort so the selected state is preserved.
	if what == NOTIFICATION_RESIZED and _selected:
		position.y = -SELECT_RAISE_PX

func set_highlight(highlight: bool) -> void:
	_highlight_valid = highlight
	_apply_state_style()

func _apply_state_style() -> void:
	if _style_default == null:
		return
	var style: StyleBoxFlat
	if _selected:
		style = _style_selected
	elif _highlight_valid and _is_valid and _face_up:
		style = _style_valid
	else:
		style = _style_default
	add_theme_stylebox_override("panel", style)
	var alpha := 1.0 if _is_valid else INVALID_ALPHA
	modulate = Color(1.0, 1.0, 1.0, alpha)

func _gui_input(event: InputEvent) -> void:
	if card_data == null:
		return

	# Only process mouse events. With emulate_mouse_from_touch=true (Godot
	# default), every finger tap on Android synthesizes an InputEventMouseButton
	# that carries the touch position. Listening to InputEventScreenTouch as
	# well would double-fire _begin_press and spuriously trigger the double-tap
	# shortcut on the first tap.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_begin_press(get_global_mouse_position())
		else:
			_drag_active = false
			_reorder_active = false

func _begin_press(pos_global: Vector2) -> void:
	_drag_start_x_global = pos_global.x
	_drag_start_y_global = pos_global.y
	_drag_active = true
	_reorder_active = false
	# Invalid cards can only be reordered, not selected/played.
	if not _is_valid:
		get_viewport().set_input_as_handled()
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_time <= DOUBLE_TAP_MS and _last_tap_time > 0:
		_last_tap_time = 0
		_drag_active = false
		get_viewport().set_input_as_handled()
		card_play_requested.emit(card_data)
	else:
		_last_tap_time = now
		get_viewport().set_input_as_handled()
		card_tapped.emit(card_data)

# Motion events must be handled in _input because the cursor leaves the card's
# rect during a drag, so _gui_input stops receiving them.
func _input(event: InputEvent) -> void:
	if not _drag_active:
		return
	# Only process mouse motion — touch drags are emulated as mouse motion
	# when emulate_mouse_from_touch is enabled (Godot default).
	if not event is InputEventMouseMotion:
		return
	var pos: Vector2 = get_global_mouse_position()

	if _reorder_active:
		_update_reorder(pos.x)
		return

	var dx_abs: float = absf(pos.x - _drag_start_x_global)
	var dy_up: float = _drag_start_y_global - pos.y

	# Upward drag to play — only for valid cards, and only if mostly vertical.
	if _is_valid and dy_up >= DRAG_UP_THRESHOLD and dy_up > dx_abs:
		_drag_active = false
		get_viewport().set_input_as_handled()
		card_play_requested.emit(card_data)
		return

	# Horizontal drag switches into reorder mode.
	if dx_abs >= REORDER_THRESHOLD:
		_reorder_active = true
		_update_reorder(pos.x)

func _update_reorder(x_global: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var my_idx := get_index()
	var new_idx := 0
	for sib in parent.get_children():
		if sib == self:
			continue
		var ctrl := sib as Control
		if ctrl == null:
			continue
		var center_x: float = ctrl.global_position.x + ctrl.size.x / 2.0
		if center_x < x_global:
			new_idx += 1
	if new_idx != my_idx:
		parent.move_child(self, new_idx)
