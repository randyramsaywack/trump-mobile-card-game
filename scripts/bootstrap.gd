extends Node

## First-run autoload. Decides whether this Godot instance becomes the
## dedicated server or a client.
##
## Priority order:
##   1. --server flag or OS.has_feature("dedicated_server") → always server
##   2. iOS / Android platform → always client
##   3. Desktop fallback → race for the ENet port (first F5 = server)

func _ready() -> void:
	# Dev-only: jump straight into a SP game_table session for screenshot
	# captures. Skips the server-port race so the local instance can't
	# accidentally take over the cloud server's role during a layout check.
	if "--shot-game-table" in OS.get_cmdline_user_args():
		print("[bootstrap] --shot-game-table — direct to game_table")
		get_tree().change_scene_to_file.call_deferred("res://scenes/game_table.tscn")
		return

	# Explicit dedicated server mode (headless export or --server flag)
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_args():
		_start_server()
		return

	# Mobile builds are always clients
	var platform := OS.get_name()
	if platform == "iOS" or platform == "Android":
		print("[bootstrap] Platform %s — running as CLIENT" % platform)
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
		return

	# Desktop: race for the port (dev convenience)
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

func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(Protocol.SERVER_PORT, Protocol.MAX_PEERS)
	if err != OK:
		push_error("[bootstrap] FATAL: cannot bind port %d (err=%d)" % [Protocol.SERVER_PORT, err])
		get_tree().quit(1)
		return
	print("[bootstrap] Dedicated server on port %d" % Protocol.SERVER_PORT)
	NetworkState.pending_server_peer = peer
	get_tree().change_scene_to_file.call_deferred("res://scenes/server_main.tscn")
