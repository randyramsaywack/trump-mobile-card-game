extends Control

signal closed()

@onready var volume_slider: HSlider = $Panel/VBox/VolumeRow/VolumeSlider
@onready var volume_value: Label = $Panel/VBox/VolumeRow/VolumeValue
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
	difficulty_desc.text = DIFFICULTY_DESC.get(GameState.ai_difficulty, "")

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
