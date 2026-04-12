extends VBoxContainer

const COLOR_GOLD := Color(0.788, 0.659, 0.298, 1.0)
const COLOR_WHITE := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_DARK_BG := Color(0.165, 0.165, 0.165, 1.0)
const COLOR_SILHOUETTE := Color(0.533, 0.533, 0.533, 0.7)
const COLOR_GOLD_DIM := Color(0.788, 0.659, 0.298, 0.85)

const CIRCLE_SIZE := 48.0
const BORDER_WIDTH := 2.0
const INNER_SIZE := CIRCLE_SIZE - BORDER_WIDTH * 2.0

var _border_style: StyleBoxFlat
var _pulse_tween: Tween = null

@onready var _name_label: Label = $NameLabel
@onready var _tricks_count: Label = $CircleBorder/CircleBG/TricksCount
@onready var _silhouette: Control = $CircleBorder/CircleBG/Silhouette
@onready var _circle_border: PanelContainer = $CircleBorder

func _ready() -> void:
	# Build the border StyleBoxFlat (gold circle).
	_border_style = _circle_border.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_circle_border.add_theme_stylebox_override("panel", _border_style)

func set_player_name(n: String) -> void:
	_name_label.text = n

func set_tricks(count: int) -> void:
	_tricks_count.text = str(count)
	_silhouette.visible = false
	_tricks_count.visible = true

func clear_tricks() -> void:
	_tricks_count.text = ""
	_tricks_count.visible = false
	_silhouette.visible = true

func set_active(active: bool) -> void:
	if active:
		_start_pulse()
	else:
		_stop_pulse()

func _start_pulse() -> void:
	_stop_pulse()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_border_style, "bg_color", COLOR_WHITE, 0.5)
	_pulse_tween.tween_property(_border_style, "bg_color", COLOR_GOLD, 0.5)

func _stop_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	if _border_style != null:
		_border_style.bg_color = COLOR_GOLD
