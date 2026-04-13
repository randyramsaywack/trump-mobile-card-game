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
const MSG_PLAY_CARD := "play_card"
const MSG_DECLARE_TRUMP := "declare_trump"
const MSG_NEXT_ROUND := "next_round"

# ── Server → Client ───────────────────────────────────────────────────────────
const MSG_WELCOME := "welcome"
const MSG_ROOM_JOINED := "room_joined"
const MSG_ROOM_STATE := "room_state"
const MSG_ERROR := "error"
const MSG_GAME_STARTING := "game_starting"
const MSG_SESSION_START := "session_start"
const MSG_ROUND_STARTING := "round_starting"
const MSG_HAND_DEALT := "hand_dealt"
const MSG_TRUMP_SELECTION_NEEDED := "trump_selection_needed"
const MSG_TRUMP_DECLARED := "trump_declared"
const MSG_TURN_STARTED := "turn_started"
const MSG_CARD_PLAYED := "card_played"
const MSG_TRICK_COMPLETED := "trick_completed"
const MSG_ROUND_ENDED := "round_ended"
const MSG_SEAT_TAKEN_OVER_BY_AI := "seat_taken_over_by_ai"

# ── Error codes ───────────────────────────────────────────────────────────────
const ERR_ROOM_NOT_FOUND := "ROOM_NOT_FOUND"
const ERR_ROOM_FULL := "ROOM_FULL"
const ERR_INVALID_ROOM_CODE := "INVALID_ROOM_CODE"
const ERR_NOT_HOST := "NOT_HOST"
const ERR_NOT_IN_ROOM := "NOT_IN_ROOM"
const ERR_HOST_LEFT := "HOST_LEFT"
const ERR_ALREADY_IN_ROOM := "ALREADY_IN_ROOM"
const ERR_ROOM_STARTED := "ROOM_STARTED"
const ERR_NOT_YOUR_TURN := "NOT_YOUR_TURN"
const ERR_INVALID_CARD := "INVALID_CARD"
const ERR_WRONG_PHASE := "WRONG_PHASE"
const ERR_NOT_IN_GAME := "NOT_IN_GAME"
const ERR_NOT_ENOUGH_PLAYERS := "NOT_ENOUGH_PLAYERS"

# ── Error messages (human-readable) ───────────────────────────────────────────
const ERROR_MESSAGES := {
	ERR_ROOM_NOT_FOUND: "Room code not found.",
	ERR_ROOM_FULL: "Room is full.",
	ERR_INVALID_ROOM_CODE: "Room code must be 6 characters.",
	ERR_NOT_HOST: "Only the host can start the game.",
	ERR_NOT_IN_ROOM: "You must join a room first.",
	ERR_HOST_LEFT: "Host left the room.",
	ERR_ALREADY_IN_ROOM: "You are already in a room.",
	ERR_ROOM_STARTED: "Game already in progress.",
	ERR_NOT_YOUR_TURN: "It's not your turn.",
	ERR_INVALID_CARD: "That card can't be played.",
	ERR_WRONG_PHASE: "That action isn't allowed right now.",
	ERR_NOT_IN_GAME: "The game hasn't started yet.",
	ERR_NOT_ENOUGH_PLAYERS: "Need at least 2 players to start.",
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

## Serialize a Card to the wire-format dict {suit:int, rank:int}.
## Returns an empty dict if `card` is null — callers should avoid passing null.
static func card_to_dict(card: Card) -> Dictionary:
	if card == null:
		return {}
	return {"suit": int(card.suit), "rank": int(card.rank)}

## Deserialize a {suit, rank} dict back into a Card. Returns null on bad input.
## Validates types and enum ranges so server-authoritative code can trust the
## result without additional guards.
static func dict_to_card(d: Dictionary) -> Card:
	if not d.has("suit") or not d.has("rank"):
		return null
	var suit_val = d["suit"]
	var rank_val = d["rank"]
	if typeof(suit_val) != TYPE_INT or typeof(rank_val) != TYPE_INT:
		return null
	var s := int(suit_val)
	var r := int(rank_val)
	if s < int(Card.Suit.SPADES) or s > int(Card.Suit.CLUBS):
		return null
	if r < int(Card.Rank.TWO) or r > int(Card.Rank.ACE):
		return null
	return Card.new(s as Card.Suit, r as Card.Rank)

## Build a list of card dicts from an Array[Card]. Non-Card entries are
## skipped with a warning — an untyped Array here usually signals a bug.
static func cards_to_dicts(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		if c is Card:
			out.append(card_to_dict(c as Card))
		else:
			push_warning("Protocol.cards_to_dicts: skipping non-Card entry")
	return out
