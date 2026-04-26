class_name RoomManager
extends RefCounted

## Server-only. Owns all rooms and every room-mutation handler.
## Every mutation method returns a list of (peer_id, message_dict) pairs
## for the caller (main_server.gd) to actually send. That keeps this class
## free of ENet coupling and easier to reason about.

## Maps peer_id → username for peers that completed the `hello` handshake
## but aren't in a room yet.
var _usernames: Dictionary = {}

## code → Room
var _rooms: Dictionary = {}

## peer_id → code (fast lookup for the room a peer is currently in)
var _peer_to_room: Dictionary = {}

# ── Registration ──────────────────────────────────────────────────────────────

func register_peer(peer_id: int, username: String) -> void:
	_usernames[peer_id] = username

func get_username(peer_id: int) -> String:
	return String(_usernames.get(peer_id, ""))

func is_registered(peer_id: int) -> bool:
	return _usernames.has(peer_id)

# ── Room lookup ───────────────────────────────────────────────────────────────

func room_for_peer(peer_id: int) -> Room:
	var code := String(_peer_to_room.get(peer_id, ""))
	if code == "":
		return null
	return _rooms.get(code, null) as Room

# ── create_room ───────────────────────────────────────────────────────────────

func handle_create_room(peer_id: int) -> Array:
	if not is_registered(peer_id):
		return [_err_to(peer_id, Protocol.ERR_NOT_IN_ROOM)]
	if _peer_to_room.has(peer_id):
		return [_err_to(peer_id, Protocol.ERR_ALREADY_IN_ROOM)]
	var room := Room.new()
	room.code = _generate_unique_code()
	_rooms[room.code] = room
	var entry := room.add_player(peer_id, get_username(peer_id))
	_peer_to_room[peer_id] = room.code
	# Only the creator is in the room — ROOM_JOINED carries the full snapshot,
	# so there is no one to broadcast ROOM_STATE to.
	return [[peer_id, _room_joined_msg(room, entry)]]

# ── join_room ─────────────────────────────────────────────────────────────────

func handle_join_room(peer_id: int, data: Dictionary) -> Array:
	if not is_registered(peer_id):
		return [_err_to(peer_id, Protocol.ERR_NOT_IN_ROOM)]
	if _peer_to_room.has(peer_id):
		return [_err_to(peer_id, Protocol.ERR_ALREADY_IN_ROOM)]
	var code := String(data.get("code", "")).to_upper()
	if code.length() != Protocol.ROOM_CODE_LENGTH:
		return [_err_to(peer_id, Protocol.ERR_INVALID_ROOM_CODE)]
	for ch in code:
		if not Protocol.ROOM_CODE_ALPHABET.contains(ch):
			return [_err_to(peer_id, Protocol.ERR_INVALID_ROOM_CODE)]
	var room: Room = _rooms.get(code, null)
	if room == null:
		return [_err_to(peer_id, Protocol.ERR_ROOM_NOT_FOUND)]
	# Mid-game rejoin: if there's a vacant seat (peer_id == 0) whose username
	# matches this peer, reclaim it. Must come before the WAITING and is_full
	# checks — an in-progress full room would otherwise be rejected.
	var rejoin_pair := _try_rejoin(peer_id, room)
	if not rejoin_pair.is_empty():
		return rejoin_pair
	if room.state != Room.State.WAITING:
		return [_err_to(peer_id, Protocol.ERR_ROOM_STARTED)]
	if room.is_full():
		return [_err_to(peer_id, Protocol.ERR_ROOM_FULL)]
	var entry := room.add_player(peer_id, get_username(peer_id))
	_peer_to_room[peer_id] = room.code
	var out: Array = []
	# The joiner gets a full snapshot via ROOM_JOINED; existing members need
	# a ROOM_STATE broadcast so their seat list updates. Excluding the joiner
	# from the broadcast avoids a redundant back-to-back render on their end.
	out.append([peer_id, _room_joined_msg(room, entry)])
	out.append_array(_broadcast_room_state(room, peer_id))
	return out

# ── leave_room ────────────────────────────────────────────────────────────────

func handle_leave_room(peer_id: int) -> Array:
	var room := room_for_peer(peer_id)
	if room == null:
		return []
	# Mid-game: same shape as a disconnect — AI takes the seat, and if the
	# host left we promote another human so the room keeps functioning.
	if room.game_session != null:
		var was_host := room.host_id == peer_id
		var out := _on_non_host_exit(room, peer_id, "left")
		if was_host:
			out.append_array(_promote_new_host(room))
		return out
	# Lobby: host leaving collapses the room.
	return _remove_peer_from_room(peer_id, room)

# ── start_game ────────────────────────────────────────────────────────────────

func handle_start_game(peer_id: int) -> Array:
	var room := room_for_peer(peer_id)
	if room == null:
		return [_err_to(peer_id, Protocol.ERR_NOT_IN_ROOM)]
	if room.host_id != peer_id:
		return [_err_to(peer_id, Protocol.ERR_NOT_HOST)]
	if room.players.size() < 2:
		return [_err_to(peer_id, Protocol.ERR_NOT_ENOUGH_PLAYERS)]
	if room.state != Room.State.WAITING:
		return [_err_to(peer_id, Protocol.ERR_ROOM_STARTED)]
	# Construct the session first so a failure there leaves the room in
	# WAITING and the host can retry without hitting ERR_ROOM_STARTED.
	room.game_session = GameSession.new(room.code)
	room.game_session.setup_players(room.players)
	room.state = Room.State.IN_GAME
	# Keep the M1 game_starting broadcast for parity — clients currently
	# ignore it but it still confirms the transition at the protocol level.
	var out: Array = []
	for p in room.players:
		out.append([int(p["peer_id"]), Protocol.msg(Protocol.MSG_GAME_STARTING)])
	out.append_array(room.game_session.start_first_round())
	return out

# ── disconnect path ───────────────────────────────────────────────────────────

## Called from main_server.gd on any `peer_disconnected`. Cleans up the
## username table and removes the peer from any room it was in.
func handle_disconnect(peer_id: int) -> Array:
	_usernames.erase(peer_id)
	var room := room_for_peer(peer_id)
	if room == null:
		return []
	# Mid-game: AI takes over the seat regardless of host status, and if the
	# host disconnected we auto-promote another connected human so future
	# host-only actions (Next Round) still resolve. Without this, host
	# disconnects froze every other client on the game screen.
	if room.game_session != null:
		var was_host := room.host_id == peer_id
		var out := _on_non_host_exit(room, peer_id, "disconnect")
		if was_host:
			out.append_array(_promote_new_host(room))
		return out
	# Lobby (no active game): keep prior behavior — host disconnect collapses
	# the room since there's nothing to keep alive.
	return _remove_peer_from_room(peer_id, room)

# ── Game-loop delegators ──────────────────────────────────────────────────────

func handle_play_card(peer_id: int, data: Dictionary) -> Array:
	var room := room_for_peer(peer_id)
	if room == null or room.game_session == null:
		return [_err_to(peer_id, Protocol.ERR_NOT_IN_GAME)]
	return room.game_session.handle_play_card(peer_id, data)

func handle_declare_trump(peer_id: int, data: Dictionary) -> Array:
	var room := room_for_peer(peer_id)
	if room == null or room.game_session == null:
		return [_err_to(peer_id, Protocol.ERR_NOT_IN_GAME)]
	return room.game_session.handle_declare_trump(peer_id, data)

func handle_next_round(peer_id: int) -> Array:
	var room := room_for_peer(peer_id)
	if room == null or room.game_session == null:
		return [_err_to(peer_id, Protocol.ERR_NOT_IN_GAME)]
	return room.game_session.handle_next_round(peer_id, room.host_id == peer_id)

# ── Per-frame ─────────────────────────────────────────────────────────────────

## Called every frame by main_server._process. Drives every active game
## session so AI delays, trick display countdowns, and other async events
## produce outgoing messages.
func tick(delta: float) -> Array:
	var out: Array = []
	for code in _rooms.keys():
		var room: Room = _rooms[code]
		if room.game_session != null:
			out.append_array(room.game_session.tick(delta))
	return out

# ── internal helpers ──────────────────────────────────────────────────────────

func _remove_peer_from_room(peer_id: int, room: Room) -> Array:
	var was_host := room.host_id == peer_id
	room.remove_player(peer_id)
	_peer_to_room.erase(peer_id)
	var out: Array = []
	if room.players.is_empty():
		_rooms.erase(room.code)
		return out
	if was_host:
		# Evict remaining players with HOST_LEFT and delete the room.
		for p in room.players:
			var pid := int(p["peer_id"])
			out.append([pid, _err_msg(Protocol.ERR_HOST_LEFT)])
			_peer_to_room.erase(pid)
		_rooms.erase(room.code)
		return out
	out.append_array(_broadcast_room_state(room))
	return out

## Shared path for non-host disconnect or voluntary leave during an active
## game. Swaps the seat to AI. If zero humans remain, destroys the room.
func _on_non_host_exit(room: Room, peer_id: int, reason: String) -> Array:
	var out: Array
	if reason == "disconnect":
		out = room.game_session.handle_player_disconnect(peer_id)
	else:
		out = room.game_session.handle_player_leave(peer_id)
	_peer_to_room.erase(peer_id)
	# Keep room.players in sync — the seat entry becomes "AI" with the old
	# username but zero peer_id so future lookups can't match.
	for i in room.players.size():
		if int(room.players[i]["peer_id"]) == peer_id:
			room.players[i]["peer_id"] = 0
			break
	if not room.game_session.has_humans():
		_rooms.erase(room.code)
	return out

## Mid-game rejoin probe. Returns an outgoing-pair list (same shape as the
## other handlers) if the peer matches a vacant seat in `room`; empty array
## means "no match — fall through to normal join flow". Identity is username
## equality, which is spoofable but matches the no-account guest model.
func _try_rejoin(peer_id: int, room: Room) -> Array:
	if room.game_session == null:
		return []
	var username := get_username(peer_id)
	if username == "":
		return []
	var matched_seat := -1
	var matched_index := -1
	for i in room.players.size():
		var entry: Dictionary = room.players[i]
		if int(entry["peer_id"]) == 0 and String(entry["username"]) == username:
			matched_seat = int(entry["seat"])
			matched_index = i
			break
	if matched_seat < 0:
		return []
	# Reassign the seat to this peer.
	room.players[matched_index]["peer_id"] = peer_id
	_peer_to_room[peer_id] = room.code
	room.game_session.handle_player_rejoin(peer_id, matched_seat)
	# Drain any events handle_player_rejoin queued (e.g. re-armed turn timer)
	# so they ship in the same flight as the snapshot.
	var queued := room.game_session.drain_events()
	var out: Array = []
	out.append([peer_id, _room_joined_msg(room, room.players[matched_index])])
	out.append([peer_id, Protocol.msg(Protocol.MSG_FULL_STATE,
			room.game_session.build_full_state_for(matched_seat))])
	out.append_array(queued)
	out.append_array(_broadcast_room_state(room, peer_id))
	return out

## Picks the next still-connected human in `room` and transfers the host role.
## Called only after _on_non_host_exit has zeroed out the disconnected host's
## peer_id entry, so any non-zero peer in room.players is a candidate.
## Broadcasts the updated room state directly to each connected human (skipping
## the zeroed entry — _send treats peer 0 as a broadcast and would dupe).
func _promote_new_host(room: Room) -> Array:
	var new_host_id := 0
	for entry in room.players:
		var pid := int(entry["peer_id"])
		if pid != 0:
			new_host_id = pid
			break
	if new_host_id == 0:
		_rooms.erase(room.code)
		return []
	room.host_id = new_host_id
	for e in room.players:
		e["is_host"] = (int(e["peer_id"]) == new_host_id)
	var msg := Protocol.msg(Protocol.MSG_ROOM_STATE, room.to_state_dict())
	var out: Array = []
	for entry in room.players:
		var pid := int(entry["peer_id"])
		if pid != 0:
			out.append([pid, msg])
	return out

func _broadcast_room_state(room: Room, exclude_peer_id: int = -1) -> Array:
	var msg := Protocol.msg(Protocol.MSG_ROOM_STATE, room.to_state_dict())
	var out: Array = []
	for p in room.players:
		var pid := int(p["peer_id"])
		if pid == exclude_peer_id:
			continue
		out.append([pid, msg])
	return out

func _room_joined_msg(room: Room, entry: Dictionary) -> Dictionary:
	return Protocol.msg(Protocol.MSG_ROOM_JOINED, {
		"code": room.code,
		"players": room.players.duplicate(true),
		"host_id": room.host_id,
		"your_seat": int(entry["seat"]),
	})

func _err_to(peer_id: int, code: String) -> Array:
	return [peer_id, _err_msg(code)]

func _err_msg(code: String) -> Dictionary:
	return Protocol.msg(Protocol.MSG_ERROR, {
		"code": code,
		"message": String(Protocol.ERROR_MESSAGES.get(code, code)),
	})

func _generate_unique_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _attempt in 64:
		var s := ""
		for _i in Protocol.ROOM_CODE_LENGTH:
			var idx := rng.randi_range(0, Protocol.ROOM_CODE_ALPHABET.length() - 1)
			s += Protocol.ROOM_CODE_ALPHABET[idx]
		if not _rooms.has(s):
			return s
	# 32^6 ≈ 1.07B; 64 attempts with a handful of live rooms should never reach here.
	push_error("RoomManager: failed to generate unique room code after 64 attempts")
	return ""
