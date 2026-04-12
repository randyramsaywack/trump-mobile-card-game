class_name Protocol
extends RefCounted

## Wire-protocol constants shared by client and server.
## Every message is a Dictionary of the form { "type": String, "data": Dictionary }.
## Access constants via the class_name: `Protocol.MSG_HELLO`, etc.

# ── Client → Server ───────────────────────────────────────────────────────────
const MSG_HELLO := "hello"
const MSG_CREATE_ROOM := "create_room"
const MSG_JOIN_ROOM := "join_room"
const MSG_LEAVE_ROOM := "leave_room"
const MSG_START_GAME := "start_game"

# ── Server → Client ───────────────────────────────────────────────────────────
const MSG_WELCOME := "welcome"
const MSG_ROOM_JOINED := "room_joined"
const MSG_ROOM_STATE := "room_state"
const MSG_ERROR := "error"
const MSG_GAME_STARTING := "game_starting"

# ── Error codes ───────────────────────────────────────────────────────────────
const ERR_ROOM_NOT_FOUND := "ROOM_NOT_FOUND"
const ERR_ROOM_FULL := "ROOM_FULL"
const ERR_INVALID_ROOM_CODE := "INVALID_ROOM_CODE"
const ERR_NOT_HOST := "NOT_HOST"
const ERR_NOT_IN_ROOM := "NOT_IN_ROOM"
const ERR_HOST_LEFT := "HOST_LEFT"
const ERR_ALREADY_IN_ROOM := "ALREADY_IN_ROOM"

# ── Error messages (human-readable) ───────────────────────────────────────────
const ERROR_MESSAGES := {
	ERR_ROOM_NOT_FOUND: "Room code not found.",
	ERR_ROOM_FULL: "Room is full.",
	ERR_INVALID_ROOM_CODE: "Room code must be 6 characters.",
	ERR_NOT_HOST: "Only the host can start the game.",
	ERR_NOT_IN_ROOM: "You must join a room first.",
	ERR_HOST_LEFT: "Host left the room.",
	ERR_ALREADY_IN_ROOM: "You are already in a room.",
}

# ── Transport ─────────────────────────────────────────────────────────────────
const SERVER_HOST := "127.0.0.1"
const SERVER_PORT := 9999
const MAX_PEERS := 8
const MAX_PLAYERS_PER_ROOM := 4
const ROOM_CODE_LENGTH := 6
const ROOM_CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  # excludes 0/O/1/I
const USERNAME_MAX_LEN := 12

## Build a message dict. Returns the exact shape the wire expects.
static func msg(type: String, data: Dictionary = {}) -> Dictionary:
	return {"type": type, "data": data}
