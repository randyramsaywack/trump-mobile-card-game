extends Control

signal closed()

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

func _ready() -> void:
	_refresh()
	StatsManager.changed.connect(_refresh)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_on_close_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

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
