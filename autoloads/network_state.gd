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
