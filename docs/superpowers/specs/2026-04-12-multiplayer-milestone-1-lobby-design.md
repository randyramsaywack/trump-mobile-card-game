# Multiplayer Milestone 1 — Lobby — Design Spec

## Problem

The project has a fully functional single-player game but no multiplayer code at all. CLAUDE.md outlines a dedicated-server architecture on a Proxmox VM, but nothing has been built yet. Multiplayer as a whole (server + rooms + state sync + reconnect + host migration + turn timer) is too large for a single spec and must be decomposed.

This spec covers the **first** multiplayer sub-project: a working lobby. After this milestone, two or more local Godot instances can create a room, join by code, see each other in a waiting room, and the host can press Start. No game logic crosses the wire yet — this is the transport, protocol, and lobby UI foundation.

## Goals

1. Stand up a dedicated server that runs as a separate Godot instance.
2. Lock in the wire protocol (message shape, serialization, channel usage) that every later multiplayer phase will build on.
3. Ship real UI for username entry, room creation, room joining, and the waiting room.
4. Wire the main menu's disabled "Multiplayer" button into the new flow.
5. Support fast local-dev iteration with zero configuration (no command-line flags, no editor setup).

## Non-Goals

- Any game logic running over the network (no dealing, trump selection, tricks, or scoring)
- Turn timer
- AI takeover on timeout or disconnect
- Reconnect/rejoin after disconnect (disconnects are permanent for this milestone)
- Host migration (room closes if host leaves)
- Remote/LAN play — localhost only
- NAT traversal, DNS, domain config
- Encryption, auth, anti-cheat
- Persistence — rooms live in memory only, vanish on server restart

## Scope

One working local dev loop: you press F5 in Godot twice, the first instance becomes the server, the second becomes a client, the client creates a room, a third instance joins by code, both clients see each other in a waiting room, and the host can press Start to fire a `game_starting` broadcast (which the clients acknowledge with a toast).

---

## Architecture

### Roles

- **Server**: a separate Godot instance running `scenes/server_main.tscn`. Listens on ENet port `9999`. Tracks rooms, validates messages, broadcasts room state. No rendering, no game logic.
- **Client**: the existing main menu and game flow, extended with a new multiplayer branch. Connects to `127.0.0.1:9999` (hardcoded for this milestone; made configurable in a later phase).

### Instance role detection

A new autoload `scripts/bootstrap.gd` runs before the main scene is loaded. It tries to bind ENet to port `9999`:

- **Port free** → this instance becomes the server. Bootstrap stashes the peer on `NetworkState` and transitions to `scenes/server_main.tscn`.
- **Port taken** → this instance is a client. Bootstrap transitions to `scenes/main_menu.tscn` (the normal client entry point).

Zero config, no command-line flags, no editor changes. First F5 is the server, every subsequent F5 is a client.

### Transport

- `ENetMultiplayerPeer` on both sides. Godot 4 supports ENet on desktop, Android, and iOS, so there is no need for a WebSocket fallback at this phase.
- Maximum 8 peers server-side (enough headroom for a few rooms of 4 + host).
- All messages are sent on channel 0, reliable mode.

### Serialization

Messages are `Dictionary` values with two top-level keys:

```gdscript
{ "type": String, "data": Dictionary }
```

Send via `peer.put_packet(var_to_bytes(msg))`. Receive via `bytes_to_var(peer.get_packet())`. Godot-native, no JSON marshaling.

### State split

- **`autoloads/network_state.gd`** — client-side singleton. Holds connection status, current room code, player list, local seat, local username. Emits signals on state changes so UI can react reactively.
- **Existing `autoloads/game_state.gd`** — unchanged in this milestone. Game logic still runs entirely local. A later phase will route it through the network layer.

Keeping `NetworkState` separate from `GameState` preserves the option to later have `GameState` consume authoritative state dispatched by `NetworkState`, rather than tangling the two responsibilities in one file.

---

## File Structure

### New files

```
autoloads/
  network_state.gd              # client-side singleton (autoload)

scenes/
  server_main.tscn              # headless server root
  ui/
    multiplayer_menu.tscn       # username entry + Create / Join buttons
    room_waiting.tscn           # room code, player list, Start/Leave buttons

scripts/
  bootstrap.gd                  # autoload: auto-detects server vs client at startup
  server/
    main_server.gd              # server root: ENet listen loop, dispatch
    room_manager.gd              # generates codes, tracks rooms, broadcasts room state
    room.gd                     # Resource subclass: code, host_id, players, state
  net/
    protocol.gd                  # message type constants + build/parse helpers
  ui/
    multiplayer_menu_ui.gd
    room_waiting_ui.gd
```

### Modified files

- `scenes/main_menu.tscn` + `scripts/ui/main_menu_ui.gd` — wire the existing disabled Multiplayer button to load `scenes/ui/multiplayer_menu.tscn`. Remove the `disabled = true` flag and the "(coming soon)" text.
- `project.godot` — register `bootstrap.gd` and `network_state.gd` as autoloads. `bootstrap.gd` must be ordered before `network_state.gd` because bootstrap writes to NetworkState during `_ready`.

### Bootstrap behavior

```gdscript
# scripts/bootstrap.gd — autoload, runs before main scene
extends Node

const SERVER_PORT := 9999
const MAX_PEERS := 8

func _ready() -> void:
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(SERVER_PORT, MAX_PEERS)
    if err == OK:
        # Port was free — this instance is the server.
        NetworkState.pending_server_peer = peer
        get_tree().change_scene_to_file("res://scenes/server_main.tscn")
    else:
        # Port taken — client mode, use the normal main menu.
        peer.close()
        get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
```

---

## Wire Protocol

All messages travel on channel 0 in reliable mode. Every message is a dict with `type` and `data` keys.

### Client → Server

| type            | data                      | meaning                                                                                       |
| --------------- | ------------------------- | --------------------------------------------------------------------------------------------- |
| `hello`         | `{username: String}`      | First message after connect. Server registers the peer with its chosen username.              |
| `create_room`   | `{}`                      | Caller becomes the host of a new room. Server replies with `room_joined` and broadcasts state. |
| `join_room`     | `{code: String}`          | Join an existing room. Server validates the code and replies with `room_joined` or `error`.   |
| `leave_room`    | `{}`                      | Leave the current room. No reply; server broadcasts `room_state` to remaining players.        |
| `start_game`    | `{}`                      | Host only. Server broadcasts `game_starting` to everyone in the room.                          |

### Server → Client

| type            | data                                                  | meaning                                                                  |
| --------------- | ----------------------------------------------------- | ------------------------------------------------------------------------ |
| `welcome`       | `{peer_id: int}`                                      | Ack of `hello`. Client knows its server-assigned peer id.                |
| `room_joined`   | `{code, players, host_id, your_seat}`                 | Sent only to the joining client. Full room snapshot plus their seat.     |
| `room_state`    | `{code, players, host_id}`                            | Broadcast to every client in the room on any membership change.          |
| `error`         | `{code: String, message: String}`                     | Error reply. Error codes listed below.                                   |
| `game_starting` | `{}`                                                  | Host pressed Start. Clients react with a toast for this milestone.       |

### Error codes

| code                 | message                                      |
| -------------------- | -------------------------------------------- |
| `ROOM_NOT_FOUND`     | "Room code not found."                       |
| `ROOM_FULL`          | "Room is full."                              |
| `INVALID_ROOM_CODE`  | "Room code must be 6 characters."            |
| `NOT_HOST`           | "Only the host can start the game."          |
| `NOT_IN_ROOM`        | "You must join a room first."                |

### Room code generation

- 6 characters, uppercase alphanumeric
- Alphabet excludes ambiguous characters: `0`, `O`, `1`, `I` → 32-char alphabet
- Collision-check against active rooms; regenerate on collision
- `32^6 ≈ 1.07B` combinations — collisions are effectively impossible in a local-dev context

### Player object shape

A player in the `players` list is:

```gdscript
{
    "peer_id": int,       # ENet peer id (server-assigned, unique)
    "username": String,   # trimmed, max 12 chars
    "seat": int,          # 0..3, assigned on join (first free seat)
    "is_host": bool,
}
```

---

## Client Scene Flow

```
main_menu.tscn
  ↓ Multiplayer button
multiplayer_menu.tscn
  - Username text field (max 12 chars, default "Guest")
  - [Create Room]
  - [Join Room] → prompts for 6-char code in a small input
  - Connection status label ("Connecting…", "Connected", "Server unavailable")
  ↓ create_room or join_room succeeds
room_waiting.tscn
  - Room code displayed large and bold
  - 4 seat rows:
      Seat 1: <username> (Host)   ← or "Empty — AI will fill"
      Seat 2: <username>           ← or "Empty — AI will fill"
      Seat 3: ...
      Seat 4: ...
  - [Start Game]   (host only, enabled with 1+ humans)
  - [Leave Room]
  ↓ host taps Start
Toast: "Milestone 1: game logic not implemented"
(scene does not change)
```

### Username handling

- Text field on `multiplayer_menu.tscn`, max 12 characters.
- Trimmed of leading/trailing whitespace on submit.
- Empty or whitespace-only → Create and Join buttons disabled.
- Default value: `Guest`.
- Persisted via `Settings` so it survives restarts, but still editable.
- Stored on `NetworkState.local_username` for the session.

### Multiplayer menu back button

- Android hardware back → return to main menu.
- UI back arrow → same.

### Room waiting back button

- Android hardware back or Leave Room button → send `leave_room`, return to main menu.

---

## Server Responsibilities

`scripts/server/main_server.gd` is the root node of `server_main.tscn` and owns the ENet peer. Responsibilities:

- Accept connections; on `peer_connected`, mark the peer as "unregistered" until `hello`.
- On `hello`, register the peer with its username.
- Dispatch every subsequent message to `RoomManager`.
- On `peer_disconnected`, tell `RoomManager` to remove the peer from any room it was in.
- Log every connection, disconnection, and message type to the server console for debugging.

`scripts/server/room_manager.gd` owns all room state. Responsibilities:

- Maintain `Dictionary[String, Room]` of active rooms keyed by code.
- Generate unique room codes.
- Handle `create_room`, `join_room`, `leave_room`, `start_game`.
- Broadcast `room_state` to every peer in a room on any change.
- Delete a room when it becomes empty.
- Close a room if the host leaves while other players are still in it: send `error` (`HOST_LEFT`) to the others and remove the room.

`scripts/server/room.gd` is a small `Resource` class holding a single room's state: `code`, `host_id`, `players`, and a state enum (`WAITING`, `STARTING`, …).

---

## Edge Cases

| situation                                             | behavior                                                                                                                                      |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Server dies while client is in a room                 | Client's ENet peer emits disconnect. Client shows toast "Disconnected from server" and returns to main menu.                                  |
| Non-host client disconnects from a waiting room       | Server drops them, broadcasts updated `room_state` to remaining clients.                                                                      |
| Host disconnects while other players are present      | Server broadcasts `error` with code `HOST_LEFT` to the others, removes the room. Clients show a toast and return to main menu.                 |
| Host disconnects while alone in the room              | Server silently deletes the room.                                                                                                             |
| Client sends `start_game` but isn't the host          | Server replies with `error` `NOT_HOST`. Shouldn't happen via UI (button is hidden for non-hosts), but validated on server as a safety net.    |
| Client sends `create_room` while already in a room    | Server replies with `error`. Client-side the Create button should be unreachable from the waiting room, but validate server-side anyway.     |
| Invalid room code (not 6 chars, bad characters)       | Client-side validation on the input field before submit; server also returns `INVALID_ROOM_CODE` on bad input as defensive measure.            |
| Room full (4 humans joined)                           | Server returns `error` `ROOM_FULL`. Joining client stays on multiplayer menu, sees a toast.                                                   |
| Client tries to send a message before `hello`         | Server ignores and logs a warning. No crash.                                                                                                  |
| Server restart during dev                             | All clients see a disconnect. No persistence concerns — rooms live only in memory.                                                            |
| Player disconnects mid-`create_room`                  | Server creates the room then drops the peer, same as a normal disconnect — room deletes itself.                                                |

---

## Local Dev Workflow

1. Open the project in Godot.
2. Enable **Debug → Run Multiple Instances → 3 Instances** (or however many you want).
3. Press F5.
4. Instance #1 grabs port `9999` → loads `server_main.tscn` → you see a server log window.
5. Instances #2 and #3 fail to bind → load `main_menu.tscn` → you see normal main menus.
6. Tap Multiplayer on instance #2 → enter username → Create Room → room code appears.
7. Tap Multiplayer on instance #3 → enter username → Join Room → enter code → waiting room shows both players.
8. Host taps Start → both clients show the "not implemented" toast.
9. Close an instance → the other(s) see the disconnect ripple through the waiting room.

---

## Verification

- Two clients in the same room see a consistent `players` list at all times after any membership change.
- Room code is displayed identically on all clients.
- Start Game button is visible only to the host.
- Leaving the room returns to main menu and the other clients' player list updates within one message round-trip.
- Killing the server produces a clean "disconnected" toast on all clients, no crashes, no stuck scenes.
- Killing a non-host client does not break the host's waiting room.
- Killing the host evicts the other players with a `HOST_LEFT` toast.
- The same username field persists across app restarts (via `Settings`).
