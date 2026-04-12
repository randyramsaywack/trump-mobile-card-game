extends Node

## First-run autoload. Decides whether this Godot instance becomes the
## dedicated server or a client by racing to bind ENet port 9999:
##   * bind succeeds → server mode, hand peer off to server_main.tscn
##   * bind fails    → client mode, fall through to main_menu.tscn
##
## Runs before the main scene is loaded (see the scene change at the bottom).
## Zero config, no command-line flags, no editor changes — first F5 is the
## server, every subsequent F5 is a client.

func _ready() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(Protocol.SERVER_PORT, Protocol.MAX_PEERS)
	if err == OK:
		print("[bootstrap] Port %d free — running as SERVER" % Protocol.SERVER_PORT)
		NetworkState.pending_server_peer = peer
		get_tree().change_scene_to_file.call_deferred("res://scenes/server_main.tscn")
	else:
		print("[bootstrap] Port %d taken (err=%d) — running as CLIENT" % [Protocol.SERVER_PORT, err])
		peer.close()
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
