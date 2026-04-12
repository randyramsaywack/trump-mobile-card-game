extends Control

## Multiplayer entry menu. Collects a username and lets the player Create
## or Join a room. Delegates all networking to NetworkState.

@onready var username_edit: LineEdit = $Center/UsernameEdit
@onready var create_button: Button = $Center/CreateButton
@onready var join_button: Button = $Center/JoinButton
@onready var join_code_edit: LineEdit = $Center/JoinCodeEdit
@onready var join_confirm_button: Button = $Center/JoinConfirmButton
@onready var status_label: Label = $Center/StatusLabel
@onready var back_button: Button = $Center/BackButton

## True between pressing Create/Join and receiving `room_joined`, so we can
## route the arriving ROOM_JOINED signal into the correct next-scene.
var _pending_action: String = ""

const DEFAULT_MP_USERNAME := "Guest"

func _ready() -> void:
	# Use the persisted Settings name unless it's still the single-player
	# default "You" — in that case fall back to the multiplayer default "Guest".
	var initial := Settings.player_name
	if initial == Settings.PLAYER_NAME_DEFAULT:
		initial = DEFAULT_MP_USERNAME
	username_edit.text = initial
	username_edit.text_changed.connect(_on_username_changed)
	join_code_edit.text_changed.connect(_on_join_code_changed)
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	join_confirm_button.pressed.connect(_on_join_confirm_pressed)
	back_button.pressed.connect(_go_back)
	NetworkState.connection_state_changed.connect(_on_connection_state_changed)
	NetworkState.room_state_changed.connect(_on_room_state_changed)
	NetworkState.error_received.connect(_on_error_received)
	_refresh_buttons()
	_refresh_status()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()

func _on_username_changed(_text: String) -> void:
	_refresh_buttons()

func _on_join_code_changed(_text: String) -> void:
	_refresh_buttons()

func _current_username() -> String:
	return username_edit.text.strip_edges()

func _refresh_buttons() -> void:
	var valid := _current_username() != ""
	create_button.disabled = not valid
	join_button.disabled = not valid
	join_confirm_button.disabled = not valid or join_code_edit.text.strip_edges().length() != Protocol.ROOM_CODE_LENGTH

func _refresh_status() -> void:
	match NetworkState.connection_state:
		NetworkState.ConnectionState.DISCONNECTED:
			status_label.text = "Disconnected"
		NetworkState.ConnectionState.CONNECTING:
			status_label.text = "Connecting…"
		NetworkState.ConnectionState.CONNECTED:
			status_label.text = "Connected"
		NetworkState.ConnectionState.IN_ROOM:
			status_label.text = "In room"

func _persist_username() -> void:
	Settings.set_player_name(_current_username())
	NetworkState.local_username = Settings.player_name

func _on_create_pressed() -> void:
	_persist_username()
	_pending_action = "create"
	_start_connection_then(func(): NetworkState.create_room())

func _on_join_pressed() -> void:
	# Reveal the code input; actual send happens in _on_join_confirm_pressed.
	join_code_edit.visible = true
	join_confirm_button.visible = true
	join_code_edit.grab_focus()
	_refresh_buttons()

func _on_join_confirm_pressed() -> void:
	var code := join_code_edit.text.strip_edges().to_upper()
	if code.length() != Protocol.ROOM_CODE_LENGTH:
		return
	_persist_username()
	_pending_action = "join"
	_start_connection_then(func(): NetworkState.join_room(code))

## Connects if needed, then runs `action` once the handshake has completed.
## `action` is fired from the connection_state_changed handler below.
var _post_connect_action: Callable = Callable()

func _start_connection_then(action: Callable) -> void:
	if NetworkState.connection_state == NetworkState.ConnectionState.CONNECTED \
			or NetworkState.connection_state == NetworkState.ConnectionState.IN_ROOM:
		action.call()
		return
	_post_connect_action = action
	NetworkState.connect_to_server(_current_username())

func _on_connection_state_changed(state: int) -> void:
	_refresh_status()
	if state == NetworkState.ConnectionState.CONNECTED and _post_connect_action.is_valid():
		var cb := _post_connect_action
		_post_connect_action = Callable()
		cb.call()

func _on_room_state_changed() -> void:
	if NetworkState.connection_state == NetworkState.ConnectionState.IN_ROOM and _pending_action != "":
		_pending_action = ""
		var err := get_tree().change_scene_to_file("res://scenes/ui/room_waiting.tscn")
		if err != OK:
			push_error("MultiplayerMenu: failed to load room_waiting.tscn, err=%d" % err)

func _on_error_received(code: String, message: String) -> void:
	_pending_action = ""
	_post_connect_action = Callable()
	status_label.text = message
	# Surface a clear failure on the UI; the status label is sufficient for M1.
	push_warning("MultiplayerMenu: error %s — %s" % [code, message])

func _go_back() -> void:
	NetworkState.disconnect_from_server()
	var err := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		push_error("MultiplayerMenu: failed to load main_menu.tscn, err=%d" % err)
