extends Control

signal closed()

@onready var close_button: Button = $Panel/VBox/CloseButton

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed() -> void:
	visible = false
	closed.emit()
