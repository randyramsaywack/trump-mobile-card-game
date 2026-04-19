extends Node

## Server root. Owns the ENetMultiplayerPeer, polls it every frame, parses
## incoming packets as Dictionaries, and dispatches them to RoomManager.
## Never uses SceneTree.multiplayer — we drive the peer manually so raw
## put_packet/get_packet works unambiguously.

@onready var log_label: Label = get_node_or_null("LogLabel")

var _peer: ENetMultiplayerPeer = null
var _rooms: RoomManager = null
var _log_lines: PackedStringArray = PackedStringArray()
const LOG_MAX_LINES := 30

func _ready() -> void:
	_rooms = RoomManager.new()
	_peer = NetworkState.pending_server_peer
	NetworkState.pending_server_peer = null
	if _peer == null:
		_log("ERROR: no pending server peer — did bootstrap.gd run?")
		return
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	_log("Server listening on port %d" % Protocol.SERVER_PORT)
	get_window().title = "Trump — SERVER :%d" % Protocol.SERVER_PORT

func _process(delta: float) -> void:
	if _peer == null:
		return
	# Drain any outgoing messages accumulated since last frame by active
	# game sessions (AI plays, trick display timer transitions, etc.).
	_dispatch_outgoing(_rooms.tick(delta))
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var sender := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		var msg = bytes_to_var(bytes)
		if typeof(msg) != TYPE_DICTIONARY:
			_log("DROP peer=%d (non-dict packet)" % sender)
			continue
		_handle(sender, msg)

# ── ENet callbacks ────────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	_log("CONNECT peer=%d (awaiting hello)" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_log("DISCONNECT peer=%d" % peer_id)
	_dispatch_outgoing(_rooms.handle_disconnect(peer_id))

# ── Message dispatch ──────────────────────────────────────────────────────────

func _handle(sender: int, msg: Dictionary) -> void:
	var type := String(msg.get("type", ""))
	var data := msg.get("data", {}) as Dictionary
	_log("RECV peer=%d type=%s" % [sender, type])
	match type:
		Protocol.MSG_HELLO:
			_handle_hello(sender, data)
		Protocol.MSG_CREATE_ROOM:
			_require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_create_room(sender)))
		Protocol.MSG_JOIN_ROOM:
			_require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_join_room(sender, data)))
		Protocol.MSG_LEAVE_ROOM:
			_require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_leave_room(sender)))
		Protocol.MSG_START_GAME:
			_require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_start_game(sender)))
		Protocol.MSG_PLAY_CARD:
			_require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_play_card(sender, data)))
		Protocol.MSG_DECLARE_TRUMP:
			_require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_declare_trump(sender, data)))
		Protocol.MSG_NEXT_ROUND:
			_require_registered(sender, func(): _dispatch_outgoing(_rooms.handle_next_round(sender)))
		_:
			_log("DROP peer=%d unknown type=%s" % [sender, type])

func _handle_hello(sender: int, data: Dictionary) -> void:
	var username := String(data.get("username", "")).strip_edges()
	if username == "":
		username = "Guest"
	if username.length() > Protocol.USERNAME_MAX_LEN:
		username = username.substr(0, Protocol.USERNAME_MAX_LEN)
	_rooms.register_peer(sender, username)
	_send(sender, Protocol.msg(Protocol.MSG_WELCOME, {"peer_id": sender}))
	_log("HELLO peer=%d username=%s" % [sender, username])

func _require_registered(sender: int, action: Callable) -> void:
	if not _rooms.is_registered(sender):
		_log("WARN peer=%d sent message before hello — ignoring" % sender)
		return
	action.call()

# ── Outgoing ──────────────────────────────────────────────────────────────────

func _dispatch_outgoing(outgoing: Array) -> void:
	for pair in outgoing:
		_send(int(pair[0]), pair[1] as Dictionary)

func _send(target_peer: int, msg: Dictionary) -> void:
	_peer.set_target_peer(target_peer)
	_peer.put_packet(var_to_bytes(msg))
	_log("SEND peer=%d type=%s" % [target_peer, String(msg.get("type", ""))])

# ── Logging ───────────────────────────────────────────────────────────────────

func _log(line: String) -> void:
	print("[server] " + line)
	_log_lines.append(line)
	while _log_lines.size() > LOG_MAX_LINES:
		_log_lines.remove_at(0)
	if log_label != null:
		log_label.text = "\n".join(_log_lines)
