extends Node

const DEFAULT_TIMEOUT_SEC := 150.0

var _role := "join"
var _username := "Auto"
var _human_count := 2
var _code_file := ""
var _done_file := ""
var _shot_file := ""
var _timeout_sec := DEFAULT_TIMEOUT_SEC
var _started_msec := 0
var _join_sent := false
var _start_sent := false
var _action_pending := false
var _last_action_key := ""
var _connected_view: NetGameView = null
var _finished := false

func _ready() -> void:
	_parse_args()
	_started_msec = Time.get_ticks_msec()
	NetworkState.connection_state_changed.connect(_on_connection_state_changed)
	NetworkState.room_state_changed.connect(_on_room_state_changed)
	NetworkState.error_received.connect(_on_error_received)
	print("[rap31-auto:%s] starting role=%s humans=%d" % [_username, _role, _human_count])
	if _role == "host":
		NetworkState.connect_to_server(_username)

func _process(_delta: float) -> void:
	if _finished:
		return
	if _elapsed_sec() > _timeout_sec:
		_finish(false, "timeout after %.1fs" % _timeout_sec)
		return
	if _role != "host" and not _join_sent:
		_try_join_from_code_file()
	_connect_game_view()
	_drive_local_turn()

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rap31-role="):
			_role = arg.substr("--rap31-role=".length())
		elif arg.begins_with("--rap31-username="):
			_username = arg.substr("--rap31-username=".length())
		elif arg.begins_with("--rap31-human-count="):
			_human_count = int(arg.substr("--rap31-human-count=".length()))
		elif arg.begins_with("--rap31-code-file="):
			_code_file = arg.substr("--rap31-code-file=".length())
		elif arg.begins_with("--rap31-done-file="):
			_done_file = arg.substr("--rap31-done-file=".length())
		elif arg.begins_with("--rap31-shot-file="):
			_shot_file = arg.substr("--rap31-shot-file=".length())
		elif arg.begins_with("--rap31-timeout="):
			_timeout_sec = float(arg.substr("--rap31-timeout=".length()))

func _try_join_from_code_file() -> void:
	if _code_file == "" or not FileAccess.file_exists(_code_file):
		return
	var code := FileAccess.get_file_as_string(_code_file).strip_edges().to_upper()
	if code.length() != Protocol.ROOM_CODE_LENGTH:
		return
	_join_sent = true
	NetworkState.connect_to_server(_username)

func _on_connection_state_changed(state: int) -> void:
	if state != NetworkState.ConnectionState.CONNECTED:
		return
	if _role == "host":
		NetworkState.create_room()
	else:
		var code := FileAccess.get_file_as_string(_code_file).strip_edges().to_upper()
		print("[rap31-auto:%s] joining %s" % [_username, code])
		NetworkState.join_room(code)

func _on_room_state_changed() -> void:
	if NetworkState.connection_state != NetworkState.ConnectionState.IN_ROOM:
		return
	if _role == "host":
		_write_code_file()
		if not _start_sent and NetworkState.players.size() >= _human_count:
			_start_sent = true
			print("[rap31-auto:%s] starting game with %d humans" % [_username, NetworkState.players.size()])
			NetworkState.start_game()

func _write_code_file() -> void:
	if _code_file == "" or NetworkState.room_code == "":
		return
	if FileAccess.file_exists(_code_file):
		return
	var f := FileAccess.open(_code_file, FileAccess.WRITE)
	if f == null:
		_finish(false, "failed to write room code file")
		return
	f.store_string(NetworkState.room_code)
	f.close()
	print("[rap31-auto:%s] room code %s" % [_username, NetworkState.room_code])

func _connect_game_view() -> void:
	var view := GameState.game_source as NetGameView
	if view == null or view == _connected_view:
		return
	_connected_view = view
	view.trump_declared.connect(func(_suit): _action_pending = false)
	view.card_played_signal.connect(func(seat, _card):
		if int(seat) == 0:
			_action_pending = false
	)
	view.round_ended.connect(_on_round_ended)
	print("[rap31-auto:%s] game view connected" % _username)

func _drive_local_turn() -> void:
	if _action_pending:
		return
	var view := GameState.game_source as NetGameView
	if view == null:
		return
	if view.state == NetGameView.RoundState.TRUMP_SELECTION and view.trump_selector_seat == 0:
		var trump_key := "trump:%d:%d" % [view.players[0].hand.size(), view.trump_selector_seat]
		if trump_key == _last_action_key:
			return
		var hand := view.players[0].hand
		var suit := hand.dominant_suit()
		_action_pending = true
		_last_action_key = trump_key
		print("[rap31-auto:%s] declare trump %d" % [_username, int(suit)])
		NetworkState.declare_trump(suit)
	elif view.state == NetGameView.RoundState.PLAYER_TURN and view.current_player_seat == 0:
		var trick := view.current_trick
		var led := trick.led_suit if trick != null else -1
		var valid := view.players[0].hand.get_valid_cards(led, view.trump_suit)
		if valid.is_empty():
			_finish(false, "local turn has no valid cards")
			return
		var card := valid[0] as Card
		var cards_played := trick.cards_played() if trick != null else 0
		var play_key := "play:%d:%d:%d:%d:%d" % [
			view.players[0].hand.size(),
			cards_played,
			int(card.suit),
			int(card.rank),
			view.current_player_seat,
		]
		if play_key == _last_action_key:
			return
		_action_pending = true
		_last_action_key = play_key
		print("[rap31-auto:%s] play %s" % [_username, card.display_name()])
		NetworkState.play_card(card)

func _on_round_ended(winning_team: int) -> void:
	var view := GameState.game_source as NetGameView
	var books := view.books if view != null else []
	var wins := view.session_wins if view != null else []
	_capture_shot()
	_finish(true, "round ended winning_team=%d books=%s session_wins=%s" % [winning_team, str(books), str(wins)])

func _capture_shot() -> void:
	if _shot_file == "":
		return
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	var err := img.save_png(_shot_file)
	if err != OK:
		push_warning("[rap31-auto:%s] failed screenshot err=%d" % [_username, err])

func _on_error_received(code: String, message: String) -> void:
	_finish(false, "network error %s: %s" % [code, message])

func _finish(ok: bool, message: String) -> void:
	if _finished:
		return
	_finished = true
	var status := "PASS" if ok else "FAIL"
	var line := "[rap31-auto:%s] %s %s" % [_username, status, message]
	if ok:
		print(line)
	else:
		push_error(line)
	if _done_file != "":
		var f := FileAccess.open(_done_file, FileAccess.WRITE)
		if f != null:
			f.store_string("%s\n%s\n" % [status, message])
			f.close()
	if ok:
		get_tree().create_timer(5.0).timeout.connect(_shutdown_success)
		return
	NetworkState.disconnect_from_server()
	get_tree().quit(1)

func _shutdown_success() -> void:
	NetworkState.disconnect_from_server()
	get_tree().quit(0)

func _elapsed_sec() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0
