extends Node

## Client-side networking singleton. Holds connection + room projection.
## Server instances also load this autoload because it is global, but server
## code never touches these fields (server state lives in RoomManager).

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, IN_ROOM }

signal connection_state_changed(state: int)
signal room_state_changed()
signal error_received(code: String, message: String)
signal game_starting()

## Set by bootstrap.gd when this instance wins the ENet bind race and becomes
## the server. main_server.gd picks it up in _ready and never touches it again.
var pending_server_peer: ENetMultiplayerPeer = null

## Client-side fields. Read by UI, written by the send/receive helpers in Task 8+.
var connection_state: int = ConnectionState.DISCONNECTED
var local_peer_id: int = 0
var local_username: String = ""
var room_code: String = ""
var local_seat: int = -1
var is_host: bool = false
var players: Array = []			# Array[Dictionary] — server snapshot
var last_error_code: String = "" # for UI that wants to inspect without a signal

func _set_connection_state(value: int) -> void:
	if value == connection_state:
		return
	connection_state = value
	connection_state_changed.emit(value)

## Reset all room projection fields. Called on leave/disconnect/host_left.
func _clear_room() -> void:
	room_code = ""
	local_seat = -1
	is_host = false
	players = []
	room_state_changed.emit()

# ── Client transport ──────────────────────────────────────────────────────────

var _client_peer: ENetMultiplayerPeer = null

## Start connecting to the dedicated server. Safe to call repeatedly — a
## second call while already CONNECTED or CONNECTING is a no-op.
func connect_to_server(username: String) -> void:
	if connection_state == ConnectionState.CONNECTED \
			or connection_state == ConnectionState.CONNECTING \
			or connection_state == ConnectionState.IN_ROOM:
		return
	local_username = username
	_client_peer = ENetMultiplayerPeer.new()
	var err := _client_peer.create_client(Protocol.SERVER_HOST, Protocol.SERVER_PORT)
	if err != OK:
		push_warning("NetworkState: create_client failed err=%d" % err)
		_client_peer = null
		_set_connection_state(ConnectionState.DISCONNECTED)
		error_received.emit("CONNECT_FAILED", "Server unavailable")
		return
	_set_connection_state(ConnectionState.CONNECTING)

func disconnect_from_server() -> void:
	if _client_peer != null:
		_client_peer.close()
		_client_peer = null
	_clear_room()
	_set_connection_state(ConnectionState.DISCONNECTED)

func send(msg: Dictionary) -> void:
	if _client_peer == null:
		return
	_client_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	_client_peer.put_packet(var_to_bytes(msg))

func _process(_delta: float) -> void:
	if _client_peer == null:
		return
	_client_peer.poll()
	var status := _client_peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if connection_state != ConnectionState.DISCONNECTED:
			_client_peer = null
			_clear_room()
			_set_connection_state(ConnectionState.DISCONNECTED)
			error_received.emit("DISCONNECTED", "Disconnected from server")
		return
	if status == MultiplayerPeer.CONNECTION_CONNECTED and connection_state == ConnectionState.CONNECTING:
		# Queue HELLO BEFORE emitting CONNECTED. The signal handler runs
		# synchronously and may enqueue follow-up messages (create_room,
		# join_room). Those would otherwise land on the server before HELLO
		# and be dropped by the "registered peer" gate — forcing the user to
		# click Create/Join twice for the first action to stick.
		send(Protocol.msg(Protocol.MSG_HELLO, {"username": local_username}))
		_set_connection_state(ConnectionState.CONNECTED)
	while _client_peer != null and _client_peer.get_available_packet_count() > 0:
		var bytes := _client_peer.get_packet()
		var msg = bytes_to_var(bytes)
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		_handle_server_message(msg)

# ── Room actions (UI facade) ──────────────────────────────────────────────────

func create_room() -> void:
	send(Protocol.msg(Protocol.MSG_CREATE_ROOM))

func join_room(code: String) -> void:
	send(Protocol.msg(Protocol.MSG_JOIN_ROOM, {"code": code.to_upper()}))

func leave_room() -> void:
	if connection_state != ConnectionState.IN_ROOM:
		return
	send(Protocol.msg(Protocol.MSG_LEAVE_ROOM))
	_clear_room()
	_set_connection_state(ConnectionState.CONNECTED)

func start_game() -> void:
	if not is_host:
		return
	send(Protocol.msg(Protocol.MSG_START_GAME))

# ── Incoming server messages ──────────────────────────────────────────────────

func _handle_server_message(msg: Dictionary) -> void:
	var type := String(msg.get("type", ""))
	var data := msg.get("data", {}) as Dictionary
	match type:
		Protocol.MSG_WELCOME:
			local_peer_id = int(data.get("peer_id", 0))
		Protocol.MSG_ROOM_JOINED:
			room_code = String(data.get("code", ""))
			players = (data.get("players", []) as Array).duplicate(true)
			local_seat = int(data.get("your_seat", -1))
			var host_id := int(data.get("host_id", 0))
			is_host = host_id == local_peer_id
			_set_connection_state(ConnectionState.IN_ROOM)
			room_state_changed.emit()
		Protocol.MSG_ROOM_STATE:
			room_code = String(data.get("code", room_code))
			players = (data.get("players", []) as Array).duplicate(true)
			var host_id2 := int(data.get("host_id", 0))
			is_host = host_id2 == local_peer_id
			# Recompute local_seat from players list in case it changed.
			for p in players:
				if int(p["peer_id"]) == local_peer_id:
					local_seat = int(p["seat"])
					break
			room_state_changed.emit()
		Protocol.MSG_ERROR:
			var code := String(data.get("code", ""))
			var message := String(data.get("message", ""))
			last_error_code = code
			if code == Protocol.ERR_HOST_LEFT:
				_clear_room()
				_set_connection_state(ConnectionState.CONNECTED)
			error_received.emit(code, message)
		Protocol.MSG_GAME_STARTING:
			game_starting.emit()
		_:
			push_warning("NetworkState: unknown server msg type=%s" % type)
