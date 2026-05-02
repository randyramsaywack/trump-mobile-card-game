extends Control

signal history_requested()

const VisualStyle := preload("res://scripts/ui/visual_style.gd")

const COLOR_WIN := Color(0.788, 0.659, 0.298)      # gold #c9a84c
const COLOR_LOSS := Color(0.85, 0.85, 0.85, 0.75)  # muted white

@onready var background: ColorRect = $Background
@onready var result_label: Label = $ResultLabel
@onready var session_label: Label = $SessionLabel
@onready var final_books_label: Label = $FinalBooksLabel
@onready var history_btn: Button = $HistoryBtn
@onready var buttons_container: HBoxContainer = $Buttons
@onready var next_round_btn: Button = $Buttons/NextRoundBtn
@onready var main_menu_btn: Button = $Buttons/MainMenuBtn
@onready var result_sheet: PanelContainer = $ResultSheet

func _ready() -> void:
	_apply_mockup_style()
	history_btn.pressed.connect(_on_history_pressed)
	next_round_btn.pressed.connect(_on_next_round)
	main_menu_btn.pressed.connect(_on_main_menu)
	# Re-evaluate the Next Round button if the host changes while the win
	# screen is visible (e.g., the original host disconnected and the server
	# promoted someone else to host between rounds).
	NetworkState.room_state_changed.connect(_refresh_next_round_button)
	if "--shot-win-screen" in OS.get_cmdline_user_args():
		call_deferred("show_result", 0, [3, 2], [7, 5])

func _apply_mockup_style() -> void:
	VisualStyle.apply_felt_background(self)
	background.color = Color(0, 0, 0, 0.28)
	result_sheet.anchor_left = 0.055
	result_sheet.anchor_top = 0.08
	result_sheet.anchor_right = 0.945
	result_sheet.anchor_bottom = 0.92
	result_sheet.add_theme_stylebox_override("panel", VisualStyle.panel_style(0.42, 10, 0.78))
	result_label.anchor_top = 0.14
	result_label.anchor_bottom = 0.30
	session_label.anchor_top = 0.31
	session_label.anchor_bottom = 0.39
	final_books_label.anchor_top = 0.42
	final_books_label.anchor_bottom = 0.49
	history_btn.anchor_top = 0.73
	history_btn.anchor_bottom = 0.80
	buttons_container.anchor_top = 0.56
	buttons_container.anchor_bottom = 0.69
	VisualStyle.apply_button(history_btn, "normal")
	VisualStyle.apply_button(next_round_btn, "primary")
	VisualStyle.apply_button(main_menu_btn, "normal")
	history_btn.text = "▤  VIEW HISTORY"
	next_round_btn.text = "NEXT ROUND"
	main_menu_btn.text = "MAIN MENU"

func _on_history_pressed() -> void:
	history_requested.emit()

func show_result(winning_team: int, session_wins: Array, final_books: Array = []) -> void:
	VisualStyle.apply_title(result_label, 28)
	if winning_team == 0:
		result_label.text = "YOUR TEAM WINS!"
		result_label.add_theme_color_override("font_color", COLOR_WIN)
	else:
		result_label.text = "OPPONENTS WIN!"
		result_label.add_theme_color_override("font_color", COLOR_LOSS)
	session_label.text = "Session Wins\n%d / %d" % [session_wins[0], session_wins[0] + session_wins[1]]
	VisualStyle.apply_label(session_label, 20, VisualStyle.GOLD_SOFT)
	if final_books.size() >= 2:
		final_books_label.text = "Final Tricks\n%d / %d" % [final_books[0], final_books[1]]
		final_books_label.visible = true
	else:
		final_books_label.visible = false
	VisualStyle.apply_label(final_books_label, 17, VisualStyle.TEXT)
	_refresh_next_round_button()
	_animate_entrance()

func _refresh_next_round_button() -> void:
	if GameState.multiplayer_mode and not NetworkState.is_host:
		next_round_btn.disabled = true
		next_round_btn.text = "Waiting for host…"
	else:
		next_round_btn.disabled = false
		next_round_btn.text = "NEXT ROUND"

func _on_next_round() -> void:
	visible = false
	if GameState.multiplayer_mode:
		if NetworkState.is_host:
			NetworkState.next_round()
		# Non-hosts ignore — button should already be hidden/disabled for them.
	else:
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
	final_books_label.modulate.a = 0.0
	# Buttons + history delayed
	history_btn.modulate.a = 0.0
	buttons_container.modulate.a = 0.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(background, "modulate:a", 1.0, 0.25 * m)
	tw.tween_property(result_label, "modulate:a", 1.0, 0.25 * m)
	tw.tween_property(result_label, "scale", Vector2.ONE, 0.25 * m).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(session_label, "modulate:a", 1.0, 0.2 * m).set_delay(0.1 * m)
	tw.tween_property(final_books_label, "modulate:a", 1.0, 0.2 * m).set_delay(0.12 * m)
	tw.tween_property(history_btn, "modulate:a", 1.0, 0.15 * m).set_delay(0.15 * m)
	tw.tween_property(buttons_container, "modulate:a", 1.0, 0.15 * m).set_delay(0.15 * m)

func _on_main_menu() -> void:
	if GameState.multiplayer_mode:
		NetworkState.leave_room_for_main_menu()
	var err := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		push_error("WinScreen: failed to load main_menu.tscn, error: %d" % err)
