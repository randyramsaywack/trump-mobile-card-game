extends Node

const PEERS: Array[int] = [101, 202, 303, 404]
const NAMES: Array[String] = ["Host", "Joiner", "Third", "Fourth"]
const ROOM_CODES: Array[String] = ["ABFKMR", "CDEGHJ", "KLMNPQ"]
const MAX_STEPS := 600

var _failures: Array[String] = []
var _room_manager: RoomManager
var _room_code := ""
var _round_ended_count := 0
var _next_round_started := false
var _active_human_count := 0

func _ready() -> void:
	var ok := _run()
	if ok:
		print("[rap31] PASS multiplayer smoke")
	else:
		for failure in _failures:
			push_error("[rap31] " + failure)
	_cleanup()
	get_tree().quit(0 if ok else 1)

func _run() -> bool:
	for human_count in [2, 3, 4]:
		_run_case(human_count)
	return _failures.is_empty()

func _run_case(human_count: int) -> void:
	_active_human_count = human_count
	_room_code = ""
	_round_ended_count = 0
	_next_round_started = false
	_room_manager = RoomManager.new()
	for i in human_count:
		_room_manager.register_peer(PEERS[i], NAMES[i])

	var out := _room_manager.handle_create_room(PEERS[0], {"code": ROOM_CODES[human_count - 2]})
	_expect(out.size() == 1, _case_msg("create_room should return one response"))
	if out.is_empty():
		return
	var joined_msg: Dictionary = out[0][1]
	_room_code = String(joined_msg["data"]["code"])
	_expect(_room_code.length() == Protocol.ROOM_CODE_LENGTH, _case_msg("room code should be 6 characters"))

	for i in range(1, human_count):
		out = _room_manager.handle_join_room(PEERS[i], {"code": _room_code})
		_expect(out.size() >= 2, _case_msg("join_room should notify joiner and existing peers for peer %d" % PEERS[i]))

	out = _room_manager.handle_start_game(PEERS[0])
	_track_events(out)
	var room := _room_manager.room_for_peer(PEERS[0])
	_expect(room != null, _case_msg("host should still be in a room after start"))
	if room == null:
		return
	var session := room.game_session
	_expect(session != null, _case_msg("room should have a GameSession after start_game"))
	if session == null:
		return
	_expect(session.peer_to_seat.size() == human_count, _case_msg("session should track %d human peer seats" % human_count))
	var ai_count := 0
	for p in session.players:
		if p is AIPlayer:
			ai_count += 1
	_expect(ai_count == 4 - human_count, _case_msg("session should fill %d AI seats, got %d" % [4 - human_count, ai_count]))

	var selector := session.round_manager.trump_selector_seat
	_expect(session.players[selector].hand.size() == 5, _case_msg("trump selector should have exactly 5 cards before trump"))
	for seat in 4:
		if seat != selector:
			_expect(session.players[seat].hand.size() == 0, _case_msg("non-selector seat %d should have 0 cards before trump" % seat))

	var final_deal_checked := false
	var first_round_dealer := session.dealer_seat
	var step := 0
	while step < MAX_STEPS and _round_ended_count == 0:
		step += 1
		_drive_session_once(session)
		_track_events(session.drain_events())
		if not final_deal_checked and session.round_manager.state == RoundManager.RoundState.PLAYER_TURN:
			_assert_all_hands(session, 13, "after final deal")
			final_deal_checked = true

	_expect(_round_ended_count > 0, _case_msg("first multiplayer round should reach round_ended"))
	if _round_ended_count == 0:
		_failures.append(_case_msg("stopped after %d steps with state=%s current_seat=%d books=%s hand_sizes=%s trick_cards=%d" % [
			step,
			str(session.round_manager.state),
			session.round_manager.current_player_seat,
			str(session.round_manager.books),
			str(_hand_sizes(session)),
			session.round_manager.current_trick.cards_played() if session.round_manager.current_trick != null else 0,
		]))
	_expect(final_deal_checked, _case_msg("smoke should observe final deal before round end"))
	_expect(session.between_rounds, _case_msg("session should be between rounds after round end"))
	_expect(session.round_manager.books[0] >= RoundManager.BOOKS_TO_WIN or session.round_manager.books[1] >= RoundManager.BOOKS_TO_WIN,
			_case_msg("one team should have 7+ books after round end"))

	var rotated_dealer := session.dealer_seat
	_expect(rotated_dealer != first_round_dealer, _case_msg("next dealer should rotate after round end"))

	out = _room_manager.handle_next_round(PEERS[0])
	_track_events(out)
	_expect(not session.between_rounds, _case_msg("next_round should clear between_rounds"))
	_expect(session.round_manager.state == RoundManager.RoundState.TRUMP_SELECTION, _case_msg("next round should pause at trump selection after initial deal"))
	_expect(session.round_number == 2, _case_msg("next_round should start round 2"))
	_next_round_started = true

	_expect(_next_round_started, _case_msg("next round should start successfully"))
	_cleanup()

func _drive_session_once(session: GameSession) -> void:
	var rm := session.round_manager
	match rm.state:
		RoundManager.RoundState.TRUMP_SELECTION:
			var seat := rm.trump_selector_seat
			var peer := _peer_for_seat(session, seat)
			if peer > 0:
				var suit := session.players[seat].hand.dominant_suit()
				_track_events(session.handle_declare_trump(peer, {"suit": int(suit)}))
			else:
				_tick_until_progress(session, rm.state)
		RoundManager.RoundState.PLAYER_TURN:
			var seat := rm.current_player_seat
			var peer := _peer_for_seat(session, seat)
			if peer > 0:
				var valid := session.players[seat].hand.get_valid_cards(rm.current_trick.led_suit, rm.trump_suit)
				_expect(not valid.is_empty(), "human seat %d should have a valid card" % seat)
				if not valid.is_empty():
					var card := valid[0] as Card
					_track_events(session.handle_play_card(peer, {"card": Protocol.card_to_dict(card)}))
			else:
				_tick_until_progress(session, rm.state)
		RoundManager.RoundState.TRICK_DISPLAY, RoundManager.RoundState.TRICK_RESOLUTION:
			_tick_until_progress(session, rm.state)
		_:
			_track_events(session.tick(0.25))

func _tick_until_progress(session: GameSession, previous_state: int) -> void:
	for _i in 12:
		_track_events(session.tick(0.25))
		var state := session.round_manager.state
		if state != previous_state or state == RoundManager.RoundState.ROUND_OVER:
			return

func _peer_for_seat(session: GameSession, seat: int) -> int:
	for peer in session.peer_to_seat.keys():
		if int(session.peer_to_seat[peer]) == seat:
			return int(peer)
	return -1

func _assert_all_hands(session: GameSession, expected: int, context: String) -> void:
	for seat in 4:
		var actual := session.players[seat].hand.size()
		_expect(actual == expected, _case_msg("seat %d should have %d cards %s, got %d" % [seat, expected, context, actual]))

func _hand_sizes(session: GameSession) -> Array[int]:
	var out: Array[int] = []
	for seat in 4:
		out.append(session.players[seat].hand.size())
	return out

func _track_events(outgoing: Array) -> void:
	for pair in outgoing:
		if pair.size() < 2:
			continue
		var msg: Dictionary = pair[1]
		var type := String(msg.get("type", ""))
		if type == Protocol.MSG_ROUND_ENDED:
			_round_ended_count += 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _case_msg(message: String) -> String:
	return "%d-human room: %s" % [_active_human_count, message]

func _cleanup() -> void:
	if _room_manager == null:
		return
	var room := _room_manager.room_for_peer(PEERS[0])
	if room != null and room.game_session != null and room.game_session.round_manager != null:
		room.game_session.round_manager.free()
		room.game_session.round_manager = null
	_room_manager = null
