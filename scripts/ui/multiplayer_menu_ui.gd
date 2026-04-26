extends Control

## Multiplayer entry menu. Collects a username and lets the player Create
## or Join a room. Delegates all networking to NetworkState.

@onready var username_edit: LineEdit = $Center/UsernameEdit
@onready var rejoin_button: Button = $Center/RejoinButton
@onready var create_tab_button: Button = $Center/ModeRow/CreateTabButton
@onready var join_tab_button: Button = $Center/ModeRow/JoinTabButton
@onready var create_code_edit: LineEdit = $Center/CreateCodeEdit
@onready var create_button: Button = $Center/CreateButton
@onready var join_code_edit: LineEdit = $Center/JoinCodeEdit
@onready var join_confirm_button: Button = $Center/JoinConfirmButton
@onready var status_label: Label = $Center/StatusLabel
@onready var back_button: Button = $Center/BackButton

## True between pressing Create/Join and receiving `room_joined`, so we can
## route the arriving ROOM_JOINED signal into the correct next-scene.
var _pending_action: String = ""
var _mode := "create"

func _ready() -> void:
	# The multiplayer username is persisted separately from the single-player
	# "You" placeholder so editing here never bleeds into single-player UI.
	username_edit.text = Settings.mp_username
	username_edit.text_changed.connect(_on_username_changed)
	create_code_edit.text_changed.connect(_on_room_code_changed)
	join_code_edit.text_changed.connect(_on_join_code_changed)
	create_tab_button.pressed.connect(func(): _set_mode("create"))
	join_tab_button.pressed.connect(func(): _set_mode("join"))
	create_button.pressed.connect(_on_create_pressed)
	join_confirm_button.pressed.connect(_on_join_confirm_pressed)
	rejoin_button.pressed.connect(_on_rejoin_pressed)
	back_button.pressed.connect(_go_back)
	_refresh_rejoin_button()
	NetworkState.connection_state_changed.connect(_on_connection_state_changed)
	NetworkState.room_state_changed.connect(_on_room_state_changed)
	NetworkState.error_received.connect(_on_error_received)
	_set_mode("create")
	_refresh_buttons()
	_refresh_status()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()

func _on_username_changed(_text: String) -> void:
	_refresh_buttons()

func _on_join_code_changed(_text: String) -> void:
	_normalize_code_edit(join_code_edit)
	_refresh_buttons()

func _on_room_code_changed(_text: String) -> void:
	_normalize_code_edit(create_code_edit)
	_refresh_buttons()

func _current_username() -> String:
	return username_edit.text.strip_edges()

func _refresh_buttons() -> void:
	var valid := _current_username() != ""
	var active_room := _has_active_room()
	create_tab_button.button_pressed = _mode == "create"
	join_tab_button.button_pressed = _mode == "join"
	create_button.disabled = active_room or not valid or not _is_valid_room_code(create_code_edit.text)
	join_confirm_button.disabled = active_room or not valid or not _is_valid_room_code(join_code_edit.text)
	rejoin_button.disabled = not active_room and not valid

func _refresh_status() -> void:
	match NetworkState.connection_state:
		NetworkState.ConnectionState.DISCONNECTED:
			status_label.text = "Disconnected"
		NetworkState.ConnectionState.CONNECTING:
			status_label.text = "Connecting…"
		NetworkState.ConnectionState.CONNECTED:
			status_label.text = "Connected"
		NetworkState.ConnectionState.IN_ROOM:
			status_label.text = "Connected to room %s" % NetworkState.room_code

func _persist_username() -> void:
	Settings.set_mp_username(_current_username())
	NetworkState.local_username = Settings.mp_username

func _on_create_pressed() -> void:
	var code := _normalize_room_code(create_code_edit.text)
	if not _is_valid_room_code(code):
		status_label.text = "Enter a 6-letter room code. Do not use I or O."
		return
	_persist_username()
	_pending_action = "create"
	_start_connection_then(func(): NetworkState.create_room(code))

func _on_join_confirm_pressed() -> void:
	var code := _normalize_room_code(join_code_edit.text)
	if not _is_valid_room_code(code):
		return
	_persist_username()
	_pending_action = "join"
	_start_connection_then(func(): NetworkState.join_room(code))

func _set_mode(mode: String) -> void:
	_mode = mode
	var create_mode := _mode == "create"
	create_code_edit.visible = create_mode
	create_button.visible = create_mode
	join_code_edit.visible = not create_mode
	join_confirm_button.visible = not create_mode
	if NetworkState.connection_state != NetworkState.ConnectionState.IN_ROOM:
		status_label.text = "Choose a 6-letter room code to share." if create_mode else "Enter the shared room code."
	if create_mode:
		create_code_edit.grab_focus()
	else:
		join_code_edit.grab_focus()
	_refresh_buttons()

func _normalize_room_code(value: String) -> String:
	return value.strip_edges().to_upper()

func _is_valid_room_code(value: String) -> bool:
	var code := _normalize_room_code(value)
	if code.length() != Protocol.ROOM_CODE_LENGTH:
		return false
	for ch in code:
		if not Protocol.ROOM_CODE_ALPHABET.contains(ch):
			return false
	return true

func _normalize_code_edit(edit: LineEdit) -> void:
	var normalized := _normalize_room_code(edit.text)
	if normalized == edit.text:
		return
	var caret := edit.caret_column
	edit.text = normalized
	edit.caret_column = mini(caret, edit.text.length())

## Active rooms resume locally without reconnecting. Otherwise this pre-fills
## the join field with the saved code and submits through the normal join path.
func _on_rejoin_pressed() -> void:
	if _has_active_room():
		_resume_active_room()
		return
	var code := Settings.last_room_code
	if code.length() != Protocol.ROOM_CODE_LENGTH:
		return
	_set_mode("join")
	join_code_edit.text = code
	_persist_username()
	_pending_action = "join"
	_start_connection_then(func(): NetworkState.join_room(code))

func _refresh_rejoin_button() -> void:
	if _has_active_room():
		rejoin_button.text = "Resume Room (%s)" % NetworkState.room_code
		rejoin_button.visible = true
		return
	var code := Settings.last_room_code
	if code.length() == Protocol.ROOM_CODE_LENGTH:
		rejoin_button.text = "Rejoin Last Room (%s)" % code
		rejoin_button.visible = true
	else:
		rejoin_button.visible = false

func _has_active_room() -> bool:
	return NetworkState.connection_state == NetworkState.ConnectionState.IN_ROOM \
			and NetworkState.room_code.length() == Protocol.ROOM_CODE_LENGTH

func _resume_active_room() -> void:
	var scene := "res://scenes/ui/room_waiting.tscn"
	if GameState.multiplayer_mode and GameState.game_source is NetGameView:
		scene = "res://scenes/game_table.tscn"
	var err := get_tree().change_scene_to_file(scene)
	if err != OK:
		push_error("MultiplayerMenu: failed to resume active room scene %s, err=%d" % [scene, err])

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
	_refresh_rejoin_button()
	_refresh_buttons()
	_refresh_status()
	if state == NetworkState.ConnectionState.CONNECTED and _post_connect_action.is_valid():
		var cb := _post_connect_action
		_post_connect_action = Callable()
		cb.call()

func _on_room_state_changed() -> void:
	_refresh_rejoin_button()
	_refresh_buttons()
	_refresh_status()
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
	if NetworkState.connection_state != NetworkState.ConnectionState.IN_ROOM:
		NetworkState.disconnect_from_server()
	var err := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		push_error("MultiplayerMenu: failed to load main_menu.tscn, err=%d" % err)
