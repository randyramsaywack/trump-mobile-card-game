extends Control

signal closed()

@onready var name_edit: LineEdit = $Panel/VBox/NameRow/NameEdit
@onready var volume_slider: HSlider = $Panel/VBox/VolumeRow/VolumeSlider
@onready var volume_value: Label = $Panel/VBox/VolumeRow/VolumeValue
@onready var slow_btn: Button = $Panel/VBox/SpeedRow/SlowBtn
@onready var normal_btn: Button = $Panel/VBox/SpeedRow/NormalBtn
@onready var fast_btn: Button = $Panel/VBox/SpeedRow/FastBtn
@onready var easy_btn: Button = $Panel/VBox/DifficultyRow/EasyBtn
@onready var medium_btn: Button = $Panel/VBox/DifficultyRow/MediumBtn
@onready var hard_btn: Button = $Panel/VBox/DifficultyRow/HardBtn
@onready var difficulty_desc: Label = $Panel/VBox/DifficultyDesc
@onready var vibration_toggle: Button = $Panel/VBox/VibrationRow/VibrationToggle
@onready var auto_sort_toggle: Button = $Panel/VBox/AutoSortRow/AutoSortToggle
@onready var close_button: Button = $Panel/VBox/CloseButton
@onready var main_menu_button: Button = $Panel/VBox/MainMenuButton

const DIFFICULTY_DESC := {
	AIPlayer.Difficulty.EASY: "Random plays — good for learning",
	AIPlayer.Difficulty.MEDIUM: "Balanced opponents",
	AIPlayer.Difficulty.HARD: "Tracks cards, conserves trump",
}

func _ready() -> void:
	volume_slider.value = Settings.volume
	_update_value_label()
	_refresh_speed_buttons()
	_refresh_difficulty_buttons()
	_refresh_vibration_toggle()
	_refresh_name_edit()
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_on_name_focus_exited)
	vibration_toggle.toggled.connect(_on_vibration_toggled)
	auto_sort_toggle.toggled.connect(_on_auto_sort_toggled)
	_refresh_auto_sort_toggle()
	volume_slider.value_changed.connect(_on_volume_changed)
	slow_btn.pressed.connect(func(): _set_speed(Settings.AnimSpeed.SLOW))
	normal_btn.pressed.connect(func(): _set_speed(Settings.AnimSpeed.NORMAL))
	fast_btn.pressed.connect(func(): _set_speed(Settings.AnimSpeed.FAST))
	easy_btn.pressed.connect(func(): _set_difficulty(AIPlayer.Difficulty.EASY))
	medium_btn.pressed.connect(func(): _set_difficulty(AIPlayer.Difficulty.MEDIUM))
	hard_btn.pressed.connect(func(): _set_difficulty(AIPlayer.Difficulty.HARD))
	close_button.pressed.connect(_on_close_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

func _on_volume_changed(value: float) -> void:
	Settings.set_volume(value)
	_update_value_label()

func _update_value_label() -> void:
	volume_value.text = "%d%%" % int(volume_slider.value)

func _set_speed(speed: int) -> void:
	Settings.set_anim_speed(speed)
	_refresh_speed_buttons()

func _refresh_speed_buttons() -> void:
	slow_btn.button_pressed = Settings.anim_speed == Settings.AnimSpeed.SLOW
	normal_btn.button_pressed = Settings.anim_speed == Settings.AnimSpeed.NORMAL
	fast_btn.button_pressed = Settings.anim_speed == Settings.AnimSpeed.FAST

func _set_difficulty(value: int) -> void:
	GameState.ai_difficulty = value
	_refresh_difficulty_buttons()

func _refresh_difficulty_buttons() -> void:
	easy_btn.button_pressed = GameState.ai_difficulty == AIPlayer.Difficulty.EASY
	medium_btn.button_pressed = GameState.ai_difficulty == AIPlayer.Difficulty.MEDIUM
	hard_btn.button_pressed = GameState.ai_difficulty == AIPlayer.Difficulty.HARD
	difficulty_desc.text = DIFFICULTY_DESC.get(GameState.ai_difficulty, "")

func _refresh_name_edit() -> void:
	name_edit.text = Settings.player_name

func _on_name_submitted(new_text: String) -> void:
	Settings.set_player_name(new_text)
	_refresh_name_edit()
	name_edit.release_focus()

func _on_name_focus_exited() -> void:
	Settings.set_player_name(name_edit.text)
	_refresh_name_edit()

func _on_vibration_toggled(pressed: bool) -> void:
	Settings.set_vibration_enabled(pressed)
	_refresh_vibration_toggle()

func _refresh_vibration_toggle() -> void:
	vibration_toggle.button_pressed = Settings.vibration_enabled
	vibration_toggle.text = "On" if Settings.vibration_enabled else "Off"

func _on_auto_sort_toggled(pressed: bool) -> void:
	Settings.set_auto_sort(pressed)
	_refresh_auto_sort_toggle()

func _refresh_auto_sort_toggle() -> void:
	auto_sort_toggle.button_pressed = Settings.auto_sort
	auto_sort_toggle.text = "On" if Settings.auto_sort else "Off"

func _on_close_pressed() -> void:
	visible = false
	closed.emit()

func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
