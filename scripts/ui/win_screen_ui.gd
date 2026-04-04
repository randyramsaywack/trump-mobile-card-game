extends Control

@onready var result_label: Label = $ResultLabel
@onready var session_label: Label = $SessionLabel
@onready var next_round_btn: Button = $Buttons/NextRoundBtn
@onready var main_menu_btn: Button = $Buttons/MainMenuBtn

func _ready() -> void:
	next_round_btn.pressed.connect(_on_next_round)
	main_menu_btn.pressed.connect(_on_main_menu)

func show_result(winning_team: int, session_wins: Array) -> void:
	if winning_team == 0:
		result_label.text = "Your Team Wins!"
		result_label.add_theme_color_override("font_color", Color(0.1, 0.8, 0.1))
	else:
		result_label.text = "Opponents Win!"
		result_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
	session_label.text = "Session — You: %d | Opponents: %d" % [session_wins[0], session_wins[1]]

func _on_next_round() -> void:
	visible = false
	GameState.start_next_round()

func _on_main_menu() -> void:
	visible = false
	GameState.start_session()
