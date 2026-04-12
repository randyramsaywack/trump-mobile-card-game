extends Control

signal history_requested()

const COLOR_WIN := Color(0.788, 0.659, 0.298)      # gold #c9a84c
const COLOR_LOSS := Color(0.85, 0.85, 0.85, 0.75)  # muted white

@onready var background: ColorRect = $Background
@onready var result_label: Label = $ResultLabel
@onready var session_label: Label = $SessionLabel
@onready var history_btn: Button = $HistoryBtn
@onready var buttons_container: HBoxContainer = $Buttons
@onready var next_round_btn: Button = $Buttons/NextRoundBtn
@onready var main_menu_btn: Button = $Buttons/MainMenuBtn

func _ready() -> void:
	history_btn.pressed.connect(_on_history_pressed)
	next_round_btn.pressed.connect(_on_next_round)
	main_menu_btn.pressed.connect(_on_main_menu)

func _on_history_pressed() -> void:
	history_requested.emit()

func show_result(winning_team: int, session_wins: Array) -> void:
	if winning_team == 0:
		result_label.text = "Your Team Wins!"
		result_label.add_theme_color_override("font_color", COLOR_WIN)
	else:
		result_label.text = "Opponents Win!"
		result_label.add_theme_color_override("font_color", COLOR_LOSS)
	session_label.text = "Session — You: %d | Opponents: %d" % [session_wins[0], session_wins[1]]
	_animate_entrance()

func _on_next_round() -> void:
	visible = false
	GameState.start_next_round()

func _animate_entrance() -> void:
	visible = true
	var m := Settings.anim_multiplier()
	# Background fade
	background.modulate.a = 0.0
	# Result label scale-bounce
	result_label.pivot_offset = result_label.size / 2.0
	result_label.scale = Vector2(0.8, 0.8)
	result_label.modulate.a = 0.0
	# Session label
	session_label.modulate.a = 0.0
	# Buttons + history delayed
	history_btn.modulate.a = 0.0
	buttons_container.modulate.a = 0.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(background, "modulate:a", 1.0, 0.25 * m)
	tw.tween_property(result_label, "modulate:a", 1.0, 0.25 * m)
	tw.tween_property(result_label, "scale", Vector2.ONE, 0.25 * m).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(session_label, "modulate:a", 1.0, 0.2 * m).set_delay(0.1 * m)
	tw.tween_property(history_btn, "modulate:a", 1.0, 0.15 * m).set_delay(0.15 * m)
	tw.tween_property(buttons_container, "modulate:a", 1.0, 0.15 * m).set_delay(0.15 * m)

func _on_main_menu() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		push_error("WinScreen: failed to load main_menu.tscn, error: %d" % err)
