extends Control

@onready var single_player_btn: Button = $CenterLayout/SinglePlayerBtn
@onready var multiplayer_btn: Button = $CenterLayout/MultiplayerBtn

func _ready() -> void:
	single_player_btn.pressed.connect(_on_single_player)
	multiplayer_btn.disabled = true

func _on_single_player() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/game_table.tscn")
	if err != OK:
		push_error("MainMenu: failed to load game_table.tscn, error: %d" % err)
