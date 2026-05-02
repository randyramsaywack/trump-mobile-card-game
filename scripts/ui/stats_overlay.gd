extends Control

signal closed()

const VisualStyle := preload("res://scripts/ui/visual_style.gd")

@onready var rounds_played: Label = $Panel/VBox/RoundsPlayed
@onready var rounds_won: Label = $Panel/VBox/RoundsWon
@onready var rounds_lost: Label = $Panel/VBox/RoundsLost
@onready var win_rate: Label = $Panel/VBox/WinRate
@onready var books_won: Label = $Panel/VBox/BooksWon
@onready var books_lost: Label = $Panel/VBox/BooksLost
@onready var avg_books: Label = $Panel/VBox/AvgBooks
@onready var reset_button: Button = $Panel/VBox/ResetButton
@onready var close_button: Button = $Panel/VBox/CloseButton
@onready var confirm_panel: PanelContainer = $ConfirmPanel
@onready var cancel_button: Button = $ConfirmPanel/ConfirmVBox/ButtonRow/CancelButton
@onready var confirm_button: Button = $ConfirmPanel/ConfirmVBox/ButtonRow/ConfirmButton
@onready var title_label: Label = $Panel/VBox/Title
@onready var subtitle_label: Label = $Panel/VBox/Subtitle

func _ready() -> void:
	_apply_mockup_style()
	_refresh()
	StatsManager.changed.connect(_refresh)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_on_close_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

func _apply_mockup_style() -> void:
	VisualStyle.apply_felt_background(self)
	($Dim as ColorRect).color = Color(0, 0, 0, 0.42)
	($Panel as PanelContainer).add_theme_stylebox_override("panel", VisualStyle.panel_style(0.92, 10, 0.82))
	confirm_panel.add_theme_stylebox_override("panel", VisualStyle.panel_style(0.96, 10, 0.9))
	VisualStyle.apply_title(title_label, 24)
	VisualStyle.apply_label(subtitle_label, 12, VisualStyle.TEXT_DIM)
	for label in [rounds_played, rounds_won, rounds_lost, books_won, books_lost]:
		VisualStyle.apply_label(label, 15, VisualStyle.TEXT)
	for label in [win_rate, avg_books]:
		VisualStyle.apply_label(label, 15, VisualStyle.GOLD_SOFT)
	VisualStyle.apply_button(reset_button, "danger")
	VisualStyle.apply_button(close_button, "normal")
	VisualStyle.apply_button(cancel_button, "normal")
	VisualStyle.apply_button(confirm_button, "danger")
	close_button.text = "CLOSE"
	reset_button.text = "RESET STATS"

func _refresh() -> void:
	var s := StatsManager.stats
	rounds_played.text = "Rounds Played: %d" % int(s["rounds_played"])
	rounds_won.text = "Rounds Won: %d" % int(s["rounds_won"])
	rounds_lost.text = "Rounds Lost: %d" % int(s["rounds_lost"])
	win_rate.text = "Win Rate: %d%%" % int(round(StatsManager.win_rate_percent()))
	books_won.text = "Total Books Won: %d" % int(s["total_books_won"])
	books_lost.text = "Total Books Lost: %d" % int(s["total_books_lost"])
	avg_books.text = "Average Books Per Round: %.1f" % StatsManager.average_books_per_round()

func _on_reset_pressed() -> void:
	confirm_panel.visible = true

func _on_cancel_pressed() -> void:
	confirm_panel.visible = false

func _on_confirm_pressed() -> void:
	StatsManager.reset()
	confirm_panel.visible = false

func _on_close_pressed() -> void:
	visible = false
	closed.emit()
