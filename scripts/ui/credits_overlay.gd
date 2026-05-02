extends Control

signal closed()

const VisualStyle := preload("res://scripts/ui/visual_style.gd")

@onready var close_button: Button = $Panel/VBox/CloseButton
@onready var title_label: Label = $Panel/VBox/Title
@onready var body_label: Label = $Panel/VBox/Body
@onready var version_label: Label = $Panel/VBox/Version

func _ready() -> void:
	_apply_mockup_style()
	close_button.pressed.connect(_on_close_pressed)

func _apply_mockup_style() -> void:
	VisualStyle.apply_felt_background(self)
	($Dim as ColorRect).color = Color(0, 0, 0, 0.42)
	($Panel as PanelContainer).add_theme_stylebox_override("panel", VisualStyle.panel_style(0.92, 10, 0.82))
	VisualStyle.apply_title(title_label, 24)
	VisualStyle.apply_label(body_label, 14, VisualStyle.TEXT)
	VisualStyle.apply_label(version_label, 12, VisualStyle.TEXT_DIM)
	VisualStyle.apply_button(close_button, "normal")
	close_button.text = "CLOSE"

func _on_close_pressed() -> void:
	visible = false
	closed.emit()
