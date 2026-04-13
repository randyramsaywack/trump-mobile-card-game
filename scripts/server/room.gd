class_name Room
extends RefCounted

## A single waiting-room's state. Lives on the server only.

enum State { WAITING, STARTING, IN_GAME, BETWEEN_ROUNDS }

var code: String = ""
var host_id: int = 0
var state: int = State.WAITING
var game_session: GameSession = null
## Array of player dicts: {peer_id:int, username:String, seat:int, is_host:bool}
var players: Array = []

func is_full() -> bool:
	return players.size() >= Protocol.MAX_PLAYERS_PER_ROOM

func has_peer(peer_id: int) -> bool:
	for p in players:
		if int(p["peer_id"]) == peer_id:
			return true
	return false

## Returns the lowest seat index (0..3) not currently taken.
func next_free_seat() -> int:
	var taken := {}
	for p in players:
		taken[int(p["seat"])] = true
	for s in Protocol.MAX_PLAYERS_PER_ROOM:
		if not taken.has(s):
			return s
	return -1

func add_player(peer_id: int, username: String) -> Dictionary:
	var seat := next_free_seat()
	var is_host := players.is_empty()
	if is_host:
		host_id = peer_id
	var entry := {
		"peer_id": peer_id,
		"username": username,
		"seat": seat,
		"is_host": is_host,
	}
	players.append(entry)
	return entry

func remove_player(peer_id: int) -> void:
	for i in players.size():
		if int(players[i]["peer_id"]) == peer_id:
			players.remove_at(i)
			return

func to_state_dict() -> Dictionary:
	return {
		"code": code,
		"players": players.duplicate(true),
		"host_id": host_id,
	}
