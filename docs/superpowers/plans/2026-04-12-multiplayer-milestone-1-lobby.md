# Multiplayer Milestone 1 — Lobby Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a dedicated Godot server, a dict-based ENet wire protocol, and working lobby UI so two local Godot instances can create a room, join by code, see each other in a waiting room, and the host can press Start to fire a `game_starting` broadcast.

**Architecture:** The first Godot instance that successfully binds ENet port `9999` becomes the server and loads `server_main.tscn`; every other instance fails to bind, becomes a client, and loads the normal `main_menu.tscn`. A new autoload `bootstrap.gd` performs this detection before the main scene loads. Server and clients exchange `Dictionary` messages over channel 0 reliable, serialized with `var_to_bytes`/`bytes_to_var`. All room state lives on the server in `RoomManager`; clients keep a thin projection in `NetworkState`.

**Tech Stack:** Godot 4.6.2, GDScript, `ENetMultiplayerPeer` (raw `put_packet`/`get_packet` without `SceneTree.multiplayer`), autoloads, Control-based UI.

**Verification style:** No unit-test framework is in use in this project. Every task ends with a manual Godot-editor run and explicit checks against the debug output / screen. For the final task, the plan walks through the full two-client scenario described in the spec's Verification section.

---

## File Map

### New files

| Path | Responsibility |
| --- | --- |
| `scripts/net/protocol.gd` | Typed constants for message `type` strings and error `code` strings. No logic. |
| `scripts/bootstrap.gd` | Autoload. On `_ready`, tries to bind ENet to `9999`; on success transitions to `server_main.tscn`, on failure transitions to `main_menu.tscn`. |
| `scripts/server/room.gd` | `Resource` subclass: `code`, `host_id`, `players` (Array[Dictionary]), `state` enum. Owns no logic beyond small helpers. |
| `scripts/server/room_manager.gd` | Owns `Dictionary[String, Room]`. Handles `create_room`, `join_room`, `leave_room`, `start_game`. Broadcasts `room_state` on change. Evicts on host leave. |
| `scripts/server/main_server.gd` | Server root script. Owns the `ENetMultiplayerPeer`, polls each frame, dispatches messages to `RoomManager`, logs everything. |
| `scenes/server_main.tscn` | Root `Node` scene for the server with a `Label` debug log and the `main_server.gd` script. |
| `scripts/ui/multiplayer_menu_ui.gd` | Username field, Create Room, Join Room (with code prompt), connection status, back. Talks to `NetworkState`. |
| `scenes/ui/multiplayer_menu.tscn` | Multiplayer menu layout. |
| `scripts/ui/room_waiting_ui.gd` | Room code header, 4 seat rows, Start (host only), Leave. Reacts to `NetworkState` signals. |
| `scenes/ui/room_waiting.tscn` | Waiting-room layout. |

### Modified files

| Path | Change |
| --- | --- |
| `autoloads/network_state.gd` | Replace stub. Adds connection state, signals, room projection, `connect_to_server`, `send`, per-frame `_process` polling, and handlers for every server→client message in the protocol. |
| `project.godot` | Register `bootstrap.gd` as an autoload (before `NetworkState`). Existing `NetworkState` stays in place. |
| `scenes/main_menu.tscn` | Rename `MultiplayerBtn.text` to `"Multiplayer"` and remove `disabled = true`. |
| `scripts/ui/main_menu_ui.gd` | Remove `multiplayer_btn.disabled = true`, connect its `pressed` signal to load `multiplayer_menu.tscn`. |

### Out-of-scope reminders (do NOT do these in this plan)

- Do not route any `GameState` calls through `NetworkState`.
- Do not add a turn timer or AI takeover.
- Do not implement reconnect, rejoin, or host migration.
- Do not make the server address configurable — hardcode `127.0.0.1:9999`.

---

## Task 1: Protocol constants

**Files:**
- Create: `scripts/net/protocol.gd`

- [ ] **Step 1: Create the protocol constants file**

Create `scripts/net/protocol.gd` with the exact contents below. No logic, just string constants so every other file imports the same names.

```gdscript
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/net/protocol.gd
git commit -m "feat(mp): add wire-protocol constants for lobby"
```

---

## Task 2: NetworkState skeleton — vars, signals, enums

**Files:**
- Modify: `autoloads/network_state.gd` (replace stub)

This task replaces the one-line stub with fields + signals only. No connection logic yet — that comes in Task 8. The split keeps the diff readable and lets `bootstrap.gd` (Task 3) compile without a half-written network stack.

- [ ] **Step 1: Replace the stub with the field skeleton**

Replace the entire contents of `autoloads/network_state.gd` with:

```gdscript
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
var players: Array = []          # Array[Dictionary] — server snapshot
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
```

- [ ] **Step 2: Open Godot and verify the project still parses**

Run the project (F5). The main menu should load normally. If Godot reports a parse error, fix it before committing.

- [ ] **Step 3: Commit**

```bash
git add autoloads/network_state.gd
git commit -m "feat(mp): flesh out NetworkState skeleton"
```

---

## Task 3: Bootstrap autoload — port-based role detection

**Files:**
- Create: `scripts/bootstrap.gd`
- Modify: `project.godot` (register autoload)

- [ ] **Step 1: Create the bootstrap script**

Create `scripts/bootstrap.gd` with:

```gdscript
extends Node

## First-run autoload. Decides whether this Godot instance becomes the
## dedicated server or a client by racing to bind ENet port 9999:
##   * bind succeeds → server mode, hand peer off to server_main.tscn
##   * bind fails    → client mode, fall through to main_menu.tscn
##
## Runs before the main scene is loaded (see the scene change at the bottom).
## Zero config, no command-line flags, no editor changes — first F5 is the
## server, every subsequent F5 is a client.

func _ready() -> void:
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
```

Note: `call_deferred` is used so the scene change happens after all autoloads' `_ready` run. The `main_scene` in `project.godot` is still `main_menu.tscn`, which will briefly load and be immediately replaced — that's fine for a milestone-1 dev loop.

- [ ] **Step 2: Register bootstrap as the first autoload**

Modify `project.godot`: inside the `[autoload]` section, **prepend** the Bootstrap entry so it comes before every other autoload. Final section should look like:

```ini
[autoload]

Bootstrap="*res://scripts/bootstrap.gd"
GameState="*res://autoloads/game_state.gd"
NetworkState="*res://autoloads/network_state.gd"
AudioManager="*res://autoloads/audio_manager.gd"
Settings="*res://autoloads/settings.gd"
SuitFont="*res://autoloads/suit_font.gd"
StatsManager="*res://autoloads/stats_manager.gd"
```

Bootstrap must come first so its `_ready` fires before any gameplay autoload assumes a particular mode.

- [ ] **Step 3: Run once to confirm client-mode boot still works**

Press F5. Expected:
- Godot's output panel prints `[bootstrap] Port 9999 free — running as SERVER`
- The running instance tries to change to `server_main.tscn` — that scene doesn't exist yet, so expect a red error like `Cannot change to scene file at path "res://scenes/server_main.tscn"`.

This error is expected. We just want to prove the port-binding half of bootstrap fires. Stop the run.

- [ ] **Step 4: Commit**

```bash
git add scripts/bootstrap.gd project.godot
git commit -m "feat(mp): add bootstrap autoload for server/client role detection"
```

---

## Task 4: Server — Room resource

**Files:**
- Create: `scripts/server/room.gd`

- [ ] **Step 1: Create the Room class**

Create `scripts/server/room.gd`:

```gdscript
class_name Room
extends RefCounted

## A single waiting-room's state. Lives on the server only.

enum State { WAITING, STARTING }

var code: String = ""
var host_id: int = 0
var state: int = State.WAITING
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/server/room.gd
git commit -m "feat(mp): add Room resource for server-side state"
```

---

## Task 5: Server — RoomManager

**Files:**
- Create: `scripts/server/room_manager.gd`

- [ ] **Step 1: Create RoomManager**

Create `scripts/server/room_manager.gd`:

```gdscript
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
    var out: Array = []
    out.append([peer_id, _room_joined_msg(room, entry)])
    # Broadcast room_state too so the new host has a consistent view.
    out.append_array(_broadcast_room_state(room))
    return out

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
    if room.is_full():
        return [_err_to(peer_id, Protocol.ERR_ROOM_FULL)]
    var entry := room.add_player(peer_id, get_username(peer_id))
    _peer_to_room[peer_id] = room.code
    var out: Array = []
    out.append([peer_id, _room_joined_msg(room, entry)])
    out.append_array(_broadcast_room_state(room))
    return out

# ── leave_room ────────────────────────────────────────────────────────────────

func handle_leave_room(peer_id: int) -> Array:
    var room := room_for_peer(peer_id)
    if room == null:
        return []
    return _remove_peer_from_room(peer_id, room)

# ── start_game ────────────────────────────────────────────────────────────────

func handle_start_game(peer_id: int) -> Array:
    var room := room_for_peer(peer_id)
    if room == null:
        return [_err_to(peer_id, Protocol.ERR_NOT_IN_ROOM)]
    if room.host_id != peer_id:
        return [_err_to(peer_id, Protocol.ERR_NOT_HOST)]
    room.state = Room.State.STARTING
    var out: Array = []
    for p in room.players:
        out.append([int(p["peer_id"]), Protocol.msg(Protocol.MSG_GAME_STARTING)])
    return out

# ── disconnect path ───────────────────────────────────────────────────────────

## Called from main_server.gd on any `peer_disconnected`. Cleans up the
## username table and removes the peer from any room it was in.
func handle_disconnect(peer_id: int) -> Array:
    _usernames.erase(peer_id)
    var room := room_for_peer(peer_id)
    if room == null:
        return []
    return _remove_peer_from_room(peer_id, room)

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

func _broadcast_room_state(room: Room) -> Array:
    var msg := Protocol.msg(Protocol.MSG_ROOM_STATE, room.to_state_dict())
    var out: Array = []
    for p in room.players:
        out.append([int(p["peer_id"]), msg])
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/server/room_manager.gd
git commit -m "feat(mp): add RoomManager with create/join/leave/start handlers"
```

---

## Task 6: Server — main_server.gd

**Files:**
- Create: `scripts/server/main_server.gd`

- [ ] **Step 1: Create the server root script**

Create `scripts/server/main_server.gd`:

```gdscript
extends Node

## Server root. Owns the ENetMultiplayerPeer, polls it every frame, parses
## incoming packets as Dictionaries, and dispatches them to RoomManager.
## Never uses SceneTree.multiplayer — we drive the peer manually so raw
## put_packet/get_packet works unambiguously.

@onready var log_label: Label = $LogLabel

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

func _process(_delta: float) -> void:
    if _peer == null:
        return
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/server/main_server.gd
git commit -m "feat(mp): add main_server.gd with ENet polling and dispatch"
```

---

## Task 7: Server — server_main.tscn scene

**Files:**
- Create: `scenes/server_main.tscn`

- [ ] **Step 1: Create the server scene**

Create `scenes/server_main.tscn` with a root `Node` (not `Control` — we want zero rendering overhead) that owns the script, plus a `Label` for the debug log. Write the raw `.tscn` directly:

```
[gd_scene load_steps=2 format=3 uid="uid://servermain"]

[ext_resource type="Script" path="res://scripts/server/main_server.gd" id="1_main_server"]

[node name="ServerMain" type="Node"]
script = ExtResource("1_main_server")

[node name="LogLabel" type="Label" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 16.0
offset_top = 16.0
offset_right = -16.0
offset_bottom = -16.0
text = "Trump server starting…"
theme_override_font_sizes/font_size = 14
theme_override_colors/font_color = Color(0.85, 0.95, 0.85, 1)
autowrap_mode = 3
vertical_alignment = 0
```

The `@onready var log_label: Label = $LogLabel` lookup in `main_server.gd` requires the node to be named exactly `LogLabel` — keep the name as-is.

- [ ] **Step 2: Run the project to verify server boots cleanly**

Press F5. Expected (editor Output panel):

```
[bootstrap] Port 9999 free — running as SERVER
[server] Server listening on port 9999
```

The running window should show a dark-green background with `Server listening on port 9999` as a label. No red errors.

- [ ] **Step 3: Commit**

```bash
git add scenes/server_main.tscn
git commit -m "feat(mp): add server_main.tscn with debug log label"
```

---

## Task 8: NetworkState — client connection + send/receive loop

**Files:**
- Modify: `autoloads/network_state.gd`

- [ ] **Step 1: Add the connection helpers and polling loop**

Append the following functions to the bottom of `autoloads/network_state.gd` (after the existing `_clear_room()` helper):

```gdscript
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
        _set_connection_state(ConnectionState.CONNECTED)
        # Kick off the handshake as soon as we're connected.
        send(Protocol.msg(Protocol.MSG_HELLO, {"username": local_username}))
    while _client_peer != null and _client_peer.get_available_packet_count() > 0:
        var bytes := _client_peer.get_packet()
        var msg = bytes_to_var(bytes)
        if typeof(msg) != TYPE_DICTIONARY:
            continue
        _handle_server_message(msg)
```

- [ ] **Step 2: Commit**

```bash
git add autoloads/network_state.gd
git commit -m "feat(mp): add NetworkState client connect + polling"
```

---

## Task 9: NetworkState — server message handlers + room actions

**Files:**
- Modify: `autoloads/network_state.gd`

- [ ] **Step 1: Add `_handle_server_message` plus `create_room`/`join_room`/`leave_room`/`start_game` wrappers**

Append to `autoloads/network_state.gd` (after `_process` from Task 8):

```gdscript
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
```

- [ ] **Step 2: Commit**

```bash
git add autoloads/network_state.gd
git commit -m "feat(mp): add NetworkState room actions + server msg handling"
```

---

## Task 10: Multiplayer menu scene

**Files:**
- Create: `scenes/ui/multiplayer_menu.tscn`

- [ ] **Step 1: Create the scene**

Create `scenes/ui/multiplayer_menu.tscn` with the exact contents below. The node structure the script in Task 11 depends on is:

```
MultiplayerMenu (Control)
├── Background (ColorRect)
└── Center (VBoxContainer)
    ├── TitleLabel (Label)       "Multiplayer"
    ├── UsernameLabel (Label)    "Username"
    ├── UsernameEdit (LineEdit)
    ├── CreateButton (Button)    "Create Room"
    ├── JoinButton (Button)      "Join Room"
    ├── JoinCodeEdit (LineEdit)  (hidden by default)
    ├── JoinConfirmButton (Button) "Join" (hidden by default)
    ├── StatusLabel (Label)      connection status
    └── BackButton (Button)      "Back"
```

```
[gd_scene load_steps=2 format=3 uid="uid://multiplayermenu"]

[ext_resource type="Script" path="res://scripts/ui/multiplayer_menu_ui.gd" id="1_mp_menu"]

[node name="MultiplayerMenu" type="Control"]
script = ExtResource("1_mp_menu")
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Background" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.102, 0.29, 0.18, 1)

[node name="Center" type="VBoxContainer" parent="."]
anchor_left = 0.1
anchor_top = 0.12
anchor_right = 0.9
anchor_bottom = 0.92
theme_override_constants/separation = 16

[node name="TitleLabel" type="Label" parent="Center"]
layout_mode = 2
text = "Multiplayer"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 32
theme_override_colors/font_color = Color(0.95, 0.82, 0.45, 1)

[node name="UsernameLabel" type="Label" parent="Center"]
layout_mode = 2
text = "Username"
theme_override_font_sizes/font_size = 14
theme_override_colors/font_color = Color(0.788, 0.659, 0.298, 0.85)

[node name="UsernameEdit" type="LineEdit" parent="Center"]
layout_mode = 2
custom_minimum_size = Vector2(0, 44)
max_length = 12
placeholder_text = "Guest"

[node name="CreateButton" type="Button" parent="Center"]
layout_mode = 2
custom_minimum_size = Vector2(0, 54)
text = "Create Room"
theme_override_font_sizes/font_size = 16

[node name="JoinButton" type="Button" parent="Center"]
layout_mode = 2
custom_minimum_size = Vector2(0, 54)
text = "Join Room"
theme_override_font_sizes/font_size = 16

[node name="JoinCodeEdit" type="LineEdit" parent="Center"]
visible = false
layout_mode = 2
custom_minimum_size = Vector2(0, 44)
max_length = 6
placeholder_text = "Room code (6 chars)"

[node name="JoinConfirmButton" type="Button" parent="Center"]
visible = false
layout_mode = 2
custom_minimum_size = Vector2(0, 44)
text = "Join"
theme_override_font_sizes/font_size = 16

[node name="StatusLabel" type="Label" parent="Center"]
layout_mode = 2
text = "Disconnected"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 13
theme_override_colors/font_color = Color(0.788, 0.659, 0.298, 0.75)

[node name="BackButton" type="Button" parent="Center"]
layout_mode = 2
custom_minimum_size = Vector2(0, 44)
text = "Back"
theme_override_font_sizes/font_size = 14
```

- [ ] **Step 2: Commit**

```bash
git add scenes/ui/multiplayer_menu.tscn
git commit -m "feat(mp): add multiplayer menu scene"
```

---

## Task 11: Multiplayer menu script

**Files:**
- Create: `scripts/ui/multiplayer_menu_ui.gd`

- [ ] **Step 1: Create the script**

Create `scripts/ui/multiplayer_menu_ui.gd`:

```gdscript
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ui/multiplayer_menu_ui.gd
git commit -m "feat(mp): add multiplayer menu controller"
```

---

## Task 12: Room waiting scene

**Files:**
- Create: `scenes/ui/room_waiting.tscn`

- [ ] **Step 1: Create the scene**

Write `scenes/ui/room_waiting.tscn`. Node structure the script needs:

```
RoomWaiting (Control)
├── Background (ColorRect)
└── Center (VBoxContainer)
    ├── TitleLabel (Label)     "Room Code"
    ├── CodeLabel (Label)      large, bold, the 6-char code
    ├── Seat0 (Label)
    ├── Seat1 (Label)
    ├── Seat2 (Label)
    ├── Seat3 (Label)
    ├── StartButton (Button)   "Start Game" (host only)
    └── LeaveButton (Button)   "Leave Room"
```

```
[gd_scene load_steps=2 format=3 uid="uid://roomwaiting"]

[ext_resource type="Script" path="res://scripts/ui/room_waiting_ui.gd" id="1_room_wait"]

[node name="RoomWaiting" type="Control"]
script = ExtResource("1_room_wait")
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Background" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.102, 0.29, 0.18, 1)

[node name="Center" type="VBoxContainer" parent="."]
anchor_left = 0.08
anchor_top = 0.1
anchor_right = 0.92
anchor_bottom = 0.92
theme_override_constants/separation = 14

[node name="TitleLabel" type="Label" parent="Center"]
layout_mode = 2
text = "Room Code"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 16
theme_override_colors/font_color = Color(0.788, 0.659, 0.298, 0.85)

[node name="CodeLabel" type="Label" parent="Center"]
layout_mode = 2
text = "------"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 56
theme_override_colors/font_color = Color(0.95, 0.82, 0.45, 1)

[node name="Seat0" type="Label" parent="Center"]
layout_mode = 2
text = "Seat 1: Empty — AI will fill"
theme_override_font_sizes/font_size = 18

[node name="Seat1" type="Label" parent="Center"]
layout_mode = 2
text = "Seat 2: Empty — AI will fill"
theme_override_font_sizes/font_size = 18

[node name="Seat2" type="Label" parent="Center"]
layout_mode = 2
text = "Seat 3: Empty — AI will fill"
theme_override_font_sizes/font_size = 18

[node name="Seat3" type="Label" parent="Center"]
layout_mode = 2
text = "Seat 4: Empty — AI will fill"
theme_override_font_sizes/font_size = 18

[node name="StartButton" type="Button" parent="Center"]
layout_mode = 2
custom_minimum_size = Vector2(0, 54)
text = "Start Game"
theme_override_font_sizes/font_size = 16

[node name="LeaveButton" type="Button" parent="Center"]
layout_mode = 2
custom_minimum_size = Vector2(0, 44)
text = "Leave Room"
theme_override_font_sizes/font_size = 14
```

- [ ] **Step 2: Commit**

```bash
git add scenes/ui/room_waiting.tscn
git commit -m "feat(mp): add room waiting scene"
```

---

## Task 13: Room waiting script

**Files:**
- Create: `scripts/ui/room_waiting_ui.gd`

- [ ] **Step 1: Create the script**

Create `scripts/ui/room_waiting_ui.gd`:

```gdscript
extends Control

## Waiting room. Reacts to NetworkState.room_state_changed to re-render seats.
## Host sees an enabled Start button; everyone else sees it hidden.

@onready var code_label: Label = $Center/CodeLabel
@onready var seat_labels: Array[Label] = [
    $Center/Seat0,
    $Center/Seat1,
    $Center/Seat2,
    $Center/Seat3,
]
@onready var start_button: Button = $Center/StartButton
@onready var leave_button: Button = $Center/LeaveButton

const _TOAST_NOT_IMPLEMENTED := "Milestone 1: game logic not implemented"

func _ready() -> void:
    start_button.pressed.connect(_on_start_pressed)
    leave_button.pressed.connect(_leave)
    NetworkState.room_state_changed.connect(_render)
    NetworkState.connection_state_changed.connect(_on_connection_state_changed)
    NetworkState.error_received.connect(_on_error_received)
    NetworkState.game_starting.connect(_on_game_starting)
    _render()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        _leave()

func _render() -> void:
    code_label.text = NetworkState.room_code if NetworkState.room_code != "" else "------"
    var by_seat := {}
    for p in NetworkState.players:
        by_seat[int(p["seat"])] = p
    for i in 4:
        var label := seat_labels[i]
        if by_seat.has(i):
            var p: Dictionary = by_seat[i]
            var suffix := " (Host)" if bool(p["is_host"]) else ""
            label.text = "Seat %d: %s%s" % [i + 1, String(p["username"]), suffix]
        else:
            label.text = "Seat %d: Empty — AI will fill" % [i + 1]
    start_button.visible = NetworkState.is_host
    # Enable Start whenever there is at least one human (the host), per spec.
    start_button.disabled = NetworkState.players.size() < 1

func _on_start_pressed() -> void:
    NetworkState.start_game()

func _on_game_starting() -> void:
    _show_toast(_TOAST_NOT_IMPLEMENTED)

func _on_connection_state_changed(state: int) -> void:
    if state == NetworkState.ConnectionState.DISCONNECTED:
        _show_toast("Disconnected from server")
        _return_to_main_menu()

func _on_error_received(code: String, message: String) -> void:
    if code == Protocol.ERR_HOST_LEFT:
        _show_toast(message)
        _return_to_main_menu()

func _leave() -> void:
    NetworkState.leave_room()
    _return_to_main_menu()

func _return_to_main_menu() -> void:
    # Defer so we don't change scenes mid-signal.
    get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

## Simple auto-dismissing toast without a dedicated node — creates a Label
## overlay, fades it out, frees itself. Sufficient for milestone 1.
func _show_toast(text: String) -> void:
    var toast := Label.new()
    toast.text = text
    toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    toast.add_theme_font_size_override("font_size", 16)
    toast.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 1))
    toast.anchor_left = 0.1
    toast.anchor_right = 0.9
    toast.anchor_top = 0.05
    toast.anchor_bottom = 0.12
    add_child(toast)
    var tw := create_tween()
    tw.tween_interval(1.8)
    tw.tween_property(toast, "modulate:a", 0.0, 0.3)
    tw.tween_callback(toast.queue_free)
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ui/room_waiting_ui.gd
git commit -m "feat(mp): add room waiting controller"
```

---

## Task 14: Wire the main-menu Multiplayer button

**Files:**
- Modify: `scenes/main_menu.tscn` (button text + disabled flag)
- Modify: `scripts/ui/main_menu_ui.gd`

- [ ] **Step 1: Update the scene file**

In `scenes/main_menu.tscn` find the `[node name="MultiplayerBtn"` block and make two edits:

1. Change `text = "Multiplayer (coming soon)"` → `text = "Multiplayer"`
2. Delete the line `disabled = true` entirely.

The resulting node block should look like:

```
[node name="MultiplayerBtn" type="Button" parent="CenterLayout"]
layout_mode = 2
size_flags_horizontal = 4
custom_minimum_size = Vector2(200, 60)
text = "Multiplayer"
theme_override_font_sizes/font_size = 16
theme_override_colors/font_color = Color(0.788, 0.659, 0.298, 1)
theme_override_colors/font_hover_color = Color(1, 0.95, 0.7, 1)
theme_override_styles/normal = SubResource("SB_btn_normal")
theme_override_styles/disabled = SubResource("SB_btn_normal")
theme_override_styles/hover = SubResource("SB_btn_hover")
theme_override_styles/pressed = SubResource("SB_btn_hover")
theme_override_styles/focus = SubResource("SB_btn_hover")
```

(Leave the font-color at `(..., 1)` — no longer dimmed — and drop the `font_disabled_color` override to avoid lingering dim styling. Keep `theme_override_styles/disabled` in place; it simply won't be used.)

- [ ] **Step 2: Wire the button in the script**

In `scripts/ui/main_menu_ui.gd`:

1. Delete the line `multiplayer_btn.disabled = true` in `_ready`.
2. Add `multiplayer_btn.pressed.connect(_on_multiplayer)` immediately after `single_player_btn.pressed.connect(_on_single_player)`.
3. Add a new method at the bottom of the file (before `_apply_raw_font`):

```gdscript
func _on_multiplayer() -> void:
    var err := get_tree().change_scene_to_file("res://scenes/ui/multiplayer_menu.tscn")
    if err != OK:
        push_error("MainMenu: failed to load multiplayer_menu.tscn, error: %d" % err)
```

- [ ] **Step 3: Run once as a client to confirm the button navigates**

The only way to launch as a client right now is to first have a server holding port 9999. Skip visual verification for this step — we'll cover the full end-to-end run in Task 15. Just check that the project parses and loads (F5 → confirm the server scene boots, then stop).

- [ ] **Step 4: Commit**

```bash
git add scenes/main_menu.tscn scripts/ui/main_menu_ui.gd
git commit -m "feat(mp): wire main menu Multiplayer button to lobby"
```

---

## Task 15: End-to-end manual verification

**Files:** none (no code changes — this task proves the milestone works).

This task runs the full spec workflow with three local Godot instances and walks every item in the spec's "Verification" section. Any failure found here must be fixed in a follow-up commit (either a fix task below or a returning edit to the offending task).

- [ ] **Step 1: Enable Run Multiple Instances**

In the Godot editor top bar, open `Debug → Run Multiple Instances` and select `3 Instances`. (This is a per-project editor preference and persists.)

- [ ] **Step 2: Start three instances**

Press F5 once. Godot launches three windows. Expected:

- Instance #1 window title: `Trump — SERVER :9999`. Debug log shows `Server listening on port 9999`.
- Instance #2 and #3: normal main menu ("TRUMP" title, "Multiplayer" button enabled, no "(coming soon)" suffix).

If instance #2 or #3 also try to become server: check that `change_scene_to_file.call_deferred` in `bootstrap.gd` runs; check the `err` from `create_server`. The second instance's `create_server(9999, ...)` must return non-OK — if it returns OK, the port is not actually bound (uncommon but possible with some firewalls).

- [ ] **Step 3: Instance #2 creates a room**

On instance #2:
1. Tap **Multiplayer**. Multiplayer menu appears.
2. Type a username like `Alice`. Leave the placeholder `Guest` alone if faster.
3. Tap **Create Room**.
4. Expected: status briefly shows `Connecting…`, then `Connected`, then scene changes to room waiting showing a 6-char code (uppercase, no 0/O/1/I), `Seat 1: Alice (Host)`, three "Empty — AI will fill" rows, `Start Game` button visible.
5. Server log window shows:
   ```
   CONNECT peer=<id> (awaiting hello)
   RECV peer=<id> type=hello
   HELLO peer=<id> username=Alice
   SEND peer=<id> type=welcome
   RECV peer=<id> type=create_room
   SEND peer=<id> type=room_joined
   SEND peer=<id> type=room_state
   ```

- [ ] **Step 4: Instance #3 joins the room**

On instance #3:
1. Tap **Multiplayer**, enter username `Bob`.
2. Tap **Join Room**, type the 6-char code from instance #2, tap **Join**.
3. Expected: instance #3 jumps to room waiting showing the same code, `Seat 1: Alice (Host)`, `Seat 2: Bob`, two empty rows, NO Start button.
4. Instance #2 updates within one round-trip to also show `Seat 2: Bob`.

**Spec verification item:** "Two clients in the same room see a consistent players list at all times." ✓

**Spec verification item:** "Room code is displayed identically on all clients." ✓

**Spec verification item:** "Start Game button is visible only to the host." ✓

- [ ] **Step 5: Non-host disconnect test**

Close instance #3's window. Expected:
- Instance #2's seat 2 row reverts to `Empty — AI will fill` within a second.
- Server log shows `DISCONNECT peer=<id>` and no errors.
- Instance #2 stays on the waiting screen, Start button still visible.

**Spec verification item:** "Killing a non-host client does not break the host's waiting room." ✓

- [ ] **Step 6: Invalid room code test**

Relaunch instance #3 (close it and rerun multi-instance by pressing F5 again — or just use any remaining window). Tap Multiplayer → Join Room → enter `XXXXXX` (valid chars but not a real room) → Join.

Expected: status label changes to `Room code not found.`, scene does NOT change, instance #3 can retry with a valid code.

**Spec verification item:** Error codes work. ✓

- [ ] **Step 7: Host start-game test**

Have instance #3 (or a fresh client) rejoin instance #2's room. On instance #2 tap **Start Game**.

Expected on BOTH clients: a toast appears reading `Milestone 1: game logic not implemented` at the top of the screen, fades out after ~2 seconds, scene does NOT change. Server log shows `SEND peer=<id> type=game_starting` for both clients.

**Spec verification item:** "Host taps Start → both clients show the 'not implemented' toast." ✓

- [ ] **Step 8: Leave Room test**

On instance #3 tap **Leave Room**.

Expected: instance #3 returns to main menu. Instance #2's seat 2 row reverts to empty. Server log shows `RECV type=leave_room` followed by a broadcast of `room_state`.

**Spec verification item:** "Leaving the room returns to main menu and the other clients' player list updates within one message round-trip." ✓

- [ ] **Step 9: Host disconnect test**

With instance #2 still host of a room and (a fresh) instance #3 joined, close instance #2. Expected on instance #3: toast reads `Host left the room.`, scene returns to main menu within a second.

**Spec verification item:** "Killing the host evicts the other players with a HOST_LEFT toast." ✓

- [ ] **Step 10: Server death test**

Relaunch (F5) so instance #1 is server and #2/#3 are clients. Have one client create a room. Close instance #1 (the server).

Expected on each client: toast `Disconnected from server`, scene returns to main menu.

**Spec verification item:** "Killing the server produces a clean 'disconnected' toast on all clients, no crashes, no stuck scenes." ✓

- [ ] **Step 11: Username persistence test**

Relaunch. Tap Multiplayer on a client — the username field is pre-filled with whatever was last typed (via `Settings.player_name`).

**Spec verification item:** "The same username field persists across app restarts (via Settings)." ✓

- [ ] **Step 12: Commit a tag for the milestone**

No code changes — but a clean run is the deliverable. Commit an empty marker commit or annotate the most recent commit. Simplest form:

```bash
git commit --allow-empty -m "chore(mp): milestone 1 lobby verified end-to-end"
```

---

## Post-plan checklist

- [ ] All 15 tasks' steps checked off.
- [ ] No remaining `disabled = true` on the Multiplayer button.
- [ ] `git log --oneline` shows a clean sequence of feature commits — no squashes, one concern per commit.
- [ ] Single-player mode still works (regression check): from main menu, tap Single Player, play a trick, confirm no lobby code broke existing flow.
