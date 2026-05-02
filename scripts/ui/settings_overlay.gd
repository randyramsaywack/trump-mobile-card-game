extends Control

signal closed()

const VisualStyle := preload("res://scripts/ui/visual_style.gd")

@onready var volume_slider: HSlider = $Panel/VBox/VolumeRow/VolumeSlider
@onready var volume_value: Label = $Panel/VBox/VolumeRow/VolumeValue
@onready var difficulty_label: Label = $Panel/VBox/DifficultyLabel
@onready var difficulty_row: HBoxContainer = $Panel/VBox/DifficultyRow
@onready var easy_btn: Button = $Panel/VBox/DifficultyRow/EasyBtn
@onready var medium_btn: Button = $Panel/VBox/DifficultyRow/MediumBtn
@onready var hard_btn: Button = $Panel/VBox/DifficultyRow/HardBtn
@onready var difficulty_desc: Label = $Panel/VBox/DifficultyDesc
@onready var vibration_toggle: Button = $Panel/VBox/VibrationRow/VibrationToggle
@onready var auto_sort_toggle: Button = $Panel/VBox/AutoSortRow/AutoSortToggle
@onready var room_status_label: Label = $Panel/VBox/RoomStatusLabel
@onready var close_button: Button = $Panel/VBox/CloseButton
@onready var main_menu_button: Button = $Panel/VBox/MainMenuButton
@onready var title_label: Label = $Panel/VBox/Title

const DIFFICULTY_DESC := {
	AIPlayer.Difficulty.EASY: "Random plays — good for learning",
	AIPlayer.Difficulty.MEDIUM: "Balanced opponents",
	AIPlayer.Difficulty.HARD: "Tracks cards, conserves trump",
}

func _ready() -> void:
	_apply_mockup_style()
	volume_slider.value = Settings.volume
	_update_value_label()
	_refresh_difficulty_buttons()
	_refresh_vibration_toggle()
	vibration_toggle.toggled.connect(_on_vibration_toggled)
	auto_sort_toggle.toggled.connect(_on_auto_sort_toggled)
	_refresh_auto_sort_toggle()
	volume_slider.value_changed.connect(_on_volume_changed)
	easy_btn.pressed.connect(func(): _set_difficulty(AIPlayer.Difficulty.EASY))
	medium_btn.pressed.connect(func(): _set_difficulty(AIPlayer.Difficulty.MEDIUM))
	hard_btn.pressed.connect(func(): _set_difficulty(AIPlayer.Difficulty.HARD))
	close_button.pressed.connect(_on_close_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	_refresh_room_action()

func _apply_mockup_style() -> void:
	var dim := $Dim as ColorRect
	dim.color = Color(0, 0, 0, 0.58)
	var panel := $Panel as PanelContainer
	panel.anchor_left = 0.035
	panel.anchor_top = 0.50
	panel.anchor_right = 0.965
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -10.0
	panel.add_theme_stylebox_override("panel", VisualStyle.panel_style(0.96, 12, 0.95))
	var box := $Panel/VBox as VBoxContainer
	box.add_theme_constant_override("separation", 10)
	VisualStyle.apply_title(title_label, 24)
	for label in [$Panel/VBox/VolumeRow/VolumeLabel, difficulty_label, $Panel/VBox/VibrationRow/VibrationLabel, $Panel/VBox/AutoSortRow/AutoSortLabel]:
		VisualStyle.apply_label(label, 14, VisualStyle.TEXT)
	VisualStyle.apply_label(volume_value, 13, VisualStyle.TEXT)
	VisualStyle.apply_label(difficulty_desc, 12, VisualStyle.TEXT_DIM)
	VisualStyle.apply_label(room_status_label, 13, VisualStyle.GOLD_SOFT)
	for btn in [easy_btn, medium_btn, hard_btn, vibration_toggle, auto_sort_toggle, close_button]:
		VisualStyle.apply_button(btn, "normal")
	for btn in [main_menu_button]:
		VisualStyle.apply_button(btn, "normal")
	close_button.text = "CLOSE"
	main_menu_button.text = "MAIN MENU"
	vibration_toggle.custom_minimum_size = Vector2(76, 36)
	auto_sort_toggle.custom_minimum_size = Vector2(76, 36)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_refresh_room_action()

func _on_volume_changed(value: float) -> void:
	Settings.set_volume(value)
	_update_value_label()

func _update_value_label() -> void:
	volume_value.text = "%d%%" % int(volume_slider.value)

func _set_difficulty(value: int) -> void:
	GameState.ai_difficulty = value
	_refresh_difficulty_buttons()

func _refresh_difficulty_buttons() -> void:
	easy_btn.button_pressed = GameState.ai_difficulty == AIPlayer.Difficulty.EASY
	medium_btn.button_pressed = GameState.ai_difficulty == AIPlayer.Difficulty.MEDIUM
	hard_btn.button_pressed = GameState.ai_difficulty == AIPlayer.Difficulty.HARD
	for btn in [easy_btn, medium_btn, hard_btn]:
		var pressed: bool = btn.button_pressed
		btn.add_theme_stylebox_override("normal", VisualStyle.button_style("segment", pressed))
		btn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02, 1) if pressed else VisualStyle.GOLD_SOFT)
	difficulty_desc.text = DIFFICULTY_DESC.get(GameState.ai_difficulty, "")

func _on_vibration_toggled(pressed: bool) -> void:
	Settings.set_vibration_enabled(pressed)
	_refresh_vibration_toggle()

func _refresh_vibration_toggle() -> void:
	vibration_toggle.button_pressed = Settings.vibration_enabled
	vibration_toggle.text = "On" if Settings.vibration_enabled else "Off"
	vibration_toggle.add_theme_stylebox_override("normal", VisualStyle.button_style("segment", Settings.vibration_enabled))

func _on_auto_sort_toggled(pressed: bool) -> void:
	Settings.set_auto_sort(pressed)
	_refresh_auto_sort_toggle()

func _refresh_auto_sort_toggle() -> void:
	auto_sort_toggle.button_pressed = Settings.auto_sort
	auto_sort_toggle.text = "On" if Settings.auto_sort else "Off"
	auto_sort_toggle.add_theme_stylebox_override("normal", VisualStyle.button_style("segment", Settings.auto_sort))

func _on_close_pressed() -> void:
	visible = false
	closed.emit()

func _on_main_menu_pressed() -> void:
	if GameState.multiplayer_mode:
		NetworkState.leave_room_for_main_menu()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _refresh_room_action() -> void:
	if room_status_label == null or main_menu_button == null:
		return
	if GameState.multiplayer_mode and NetworkState.room_code != "":
		GameState.ai_difficulty = AIPlayer.Difficulty.MEDIUM
		difficulty_label.visible = true
		difficulty_label.text = "AI Difficulty locked: Medium"
		difficulty_row.visible = false
		difficulty_desc.visible = true
		difficulty_desc.text = "Multiplayer rooms always use Medium AI."
		room_status_label.visible = true
		room_status_label.text = "Room Code    %s" % NetworkState.room_code
		main_menu_button.text = "LEAVE ROOM"
		VisualStyle.apply_button(main_menu_button, "danger")
	else:
		difficulty_label.visible = true
		difficulty_label.text = "AI Difficulty"
		difficulty_row.visible = true
		difficulty_desc.visible = true
		room_status_label.visible = false
		main_menu_button.text = "MAIN MENU"
		VisualStyle.apply_button(main_menu_button, "normal")
		_refresh_difficulty_buttons()
