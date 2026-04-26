extends Node

const PEERS: Array[int] = [101, 202, 303, 404]
const REJOIN_PEER := 505
const NAMES: Array[String] = ["Host", "Lefty", "Partner", "Righty"]
const ROOM_CODES: Array[String] = ["ABFKMR", "CDEGHJ", "KLMNPQ", "RSTUVW"]
const MAX_DRIVE_STEPS := 700

var _failures: Array[String] = []

func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("[rap32] PASS lifecycle regressions")
	else:
		for failure in _failures:
			push_error("[rap32] " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _run() -> void:
	_test_non_host_disconnect_active_turn_ai_takeover()
	_test_host_disconnect_promotes_new_host()
	_test_all_humans_disconnect_closes_room()
	_test_timer_expiry_trump_and_card_turn()
	_test_mid_round_rejoin_full_state()
	_test_between_round_rejoin_full_state()
	_test_live_trick_history_broadcasts_before_round_end()
	_test_trick_history_rotates_to_local_perspective()

func _test_non_host_disconnect_active_turn_ai_takeover() -> void:
	var ctx := _started_context(4)
	var manager: RoomManager = ctx.manager
	var session: GameSession = ctx.session
	_declare_trump_if_needed(session)
	var active := _advance_to_non_host_turn(session)
	_expect(active > 0, "Expected to reach a non-host active turn")
	var active_peer := _peer_for_seat(session, active)
	var hand_before := session.players[active].hand.size()
	var out := manager.handle_disconnect(active_peer)
	_expect(session.players[active] is AIPlayer, "Disconnecting active non-host should swap seat to AI")
	_expect(not session.peer_to_seat.has(active_peer), "Disconnected peer should no longer own a seat")
	_expect(_count_type(out, Protocol.MSG_SEAT_TAKEN_OVER_BY_AI) == max(0, session.peer_to_seat.size()), "Takeover should broadcast to remaining humans")
	_tick_until_card_count_changes(session, active, hand_before)
	_expect(session.players[active].hand.size() == hand_before - 1, "AI takeover should play exactly one card for active seat")
	_cleanup_context(ctx)

func _test_host_disconnect_promotes_new_host() -> void:
	var ctx := _started_context(4)
	var manager: RoomManager = ctx.manager
	var room: Room = ctx.room
	var session: GameSession = ctx.session
	var old_host := room.host_id
	manager.handle_disconnect(old_host)
	_expect(room.host_id != old_host and room.host_id != 0, "Host disconnect should promote another connected human")
	_expect(room.game_session == session, "Host disconnect should preserve active game session")
	_expect(not session.peer_to_seat.has(old_host), "Disconnected host should no longer own a game seat")
	_cleanup_context(ctx)

func _test_all_humans_disconnect_closes_room() -> void:
	var ctx := _started_context(2)
	var manager: RoomManager = ctx.manager
	var code: String = ctx.code
	manager.handle_disconnect(PEERS[1])
	manager.handle_disconnect(PEERS[0])
	manager.register_peer(REJOIN_PEER, "Nobody")
	var out := manager.handle_join_room(REJOIN_PEER, {"code": code})
	_expect(_error_code(out) == Protocol.ERR_ROOM_NOT_FOUND, "Room should close after all humans disconnect")
	_cleanup_context(ctx)

func _test_timer_expiry_trump_and_card_turn() -> void:
	var ctx := _started_context(4)
	var session: GameSession = ctx.session
	var selector := session.round_manager.trump_selector_seat
	_expect(not (session.players[selector] is AIPlayer), "Timer test expects human trump selector")
	_expire_turn_timer(session)
	var out := session.tick(0.1)
	_expect(_count_type(out, Protocol.MSG_TRUMP_DECLARED) == session.peer_to_seat.size(), "Expired trump timer should declare trump once to each human")
	_expect(session.round_manager.state == RoundManager.RoundState.PLAYER_TURN, "Expired trump timer should advance to player turn")

	var active := session.round_manager.current_player_seat
	var hand_before := session.players[active].hand.size()
	_expire_turn_timer(session)
	out = session.tick(0.1)
	_expect(_count_type(out, Protocol.MSG_CARD_PLAYED) == session.peer_to_seat.size(), "Expired card timer should play exactly one card to each human")
	_expect(session.players[active].hand.size() == hand_before - 1, "Expired card timer should remove exactly one card from active hand")
	out = session.tick(0.1)
	_expect(_count_type(out, Protocol.MSG_CARD_PLAYED) <= 1, "Timer should not duplicate AI play on immediate next tick")
	_cleanup_context(ctx)

func _test_mid_round_rejoin_full_state() -> void:
	var ctx := _started_context(4)
	var manager: RoomManager = ctx.manager
	var session: GameSession = ctx.session
	var code: String = ctx.code
	_declare_trump_if_needed(session)
	_play_one_human_or_ai_action(session)
	var leaving_peer := PEERS[1]
	var leaving_seat := int(session.peer_to_seat[leaving_peer])
	var hand_count := session.players[leaving_seat].hand.size()
	manager.handle_disconnect(leaving_peer)
	_expect(session.players[leaving_seat] is AIPlayer, "Disconnected player should be AI before rejoin")
	manager.register_peer(REJOIN_PEER, NAMES[1])
	var out := manager.handle_join_room(REJOIN_PEER, {"code": code})
	_expect(_count_type(out, Protocol.MSG_ROOM_JOINED, REJOIN_PEER) == 1, "Rejoin should send ROOM_JOINED")
	_expect(_count_type(out, Protocol.MSG_FULL_STATE, REJOIN_PEER) == 1, "Mid-round rejoin should send FULL_STATE")
	_expect(session.peer_to_seat.get(REJOIN_PEER, -1) == leaving_seat, "Rejoin should reclaim original seat")
	_expect(not (session.players[leaving_seat] is AIPlayer), "Rejoined seat should become human again")
	var snapshot := _message_data(out, Protocol.MSG_FULL_STATE, REJOIN_PEER)
	_expect(int(snapshot.get("your_seat", -1)) == leaving_seat, "FULL_STATE should identify reclaimed seat")
	_expect((snapshot.get("your_hand", []) as Array).size() == hand_count, "FULL_STATE should include returning player's hand")
	_expect((snapshot.get("hand_counts", []) as Array).size() == 4, "FULL_STATE should include all hand counts")
	_cleanup_context(ctx)

func _test_between_round_rejoin_full_state() -> void:
	var ctx := _started_context(4)
	var manager: RoomManager = ctx.manager
	var session: GameSession = ctx.session
	var code: String = ctx.code
	_drive_to_round_end(session)
	_expect(session.between_rounds, "Setup should reach between-rounds state")
	var leaving_peer := PEERS[1]
	var leaving_seat := int(session.peer_to_seat[leaving_peer])
	manager.handle_disconnect(leaving_peer)
	manager.register_peer(REJOIN_PEER, NAMES[1])
	var out := manager.handle_join_room(REJOIN_PEER, {"code": code})
	_expect(_count_type(out, Protocol.MSG_FULL_STATE, REJOIN_PEER) == 1, "Between-round rejoin should send FULL_STATE")
	var snapshot := _message_data(out, Protocol.MSG_FULL_STATE, REJOIN_PEER)
	_expect(bool(snapshot.get("between_rounds", false)), "Between-round FULL_STATE should mark between_rounds")
	_expect(int(snapshot.get("state", -1)) == int(RoundManager.RoundState.ROUND_OVER), "Between-round FULL_STATE should carry ROUND_OVER state")
	_expect(int(snapshot.get("your_seat", -1)) == leaving_seat, "Between-round rejoin should reclaim original seat")
	_cleanup_context(ctx)

func _test_live_trick_history_broadcasts_before_round_end() -> void:
	var ctx := _started_context(4)
	var session: GameSession = ctx.session
	_declare_trump_if_needed(session)
	var out := _drive_to_first_trick_completed(session)
	_expect(not out.is_empty(), "Setup should complete one trick before round end")
	var completed := _message_data(out, Protocol.MSG_TRICK_COMPLETED)
	_expect(completed.has("trick_history_entry"), "TRICK_COMPLETED should carry live trick history entry")
	var entry := completed.get("trick_history_entry", {}) as Dictionary
	_expect(int(entry.get("trick_number", 0)) == 1, "Live trick history entry should identify first trick")
	_expect((entry.get("cards_played", []) as Array).size() == 4, "Live trick history entry should include all four played cards")
	_cleanup_context(ctx)

func _test_trick_history_rotates_to_local_perspective() -> void:
	var view := NetGameView.new()
	view._server_local_seat = 1
	view.seat_usernames = ["You", "PartnerName", "Righty", "HostName"]
	var raw := [{
		"trick_number": 1,
		"winning_team": "opponent_team",
		"winning_card": {"suit": int(Card.Suit.SPADES), "rank": int(Card.Rank.ACE)},
		"cards_played": [
			{"position": "bottom", "player": "You", "card": {"suit": int(Card.Suit.HEARTS), "rank": int(Card.Rank.TWO)}},
			{"position": "left", "player": "Left", "card": {"suit": int(Card.Suit.SPADES), "rank": int(Card.Rank.ACE)}},
			{"position": "top", "player": "Partner", "card": {"suit": int(Card.Suit.HEARTS), "rank": int(Card.Rank.KING)}},
			{"position": "right", "player": "Right", "card": {"suit": int(Card.Suit.CLUBS), "rank": int(Card.Rank.THREE)}},
		],
	}]
	var history := view._deserialize_trick_history(raw)
	_expect(history.size() == 1, "Trick history should deserialize one entry")
	var entry: Dictionary = history[0]
	_expect(String(entry["winning_team"]) == "player_team", "Odd-seat multiplayer history should swap winning team into local perspective")
	var by_pos := {}
	for cp in entry["cards_played"]:
		var card_entry: Dictionary = cp
		by_pos[String(card_entry["position"])] = card_entry
	_expect(String((by_pos["bottom"] as Dictionary)["player"]) == "You", "Local server seat should render as You at bottom")
	_expect(String((by_pos["right"] as Dictionary)["player"]) == "HostName", "Opponent history card should use the multiplayer username")
	var bottom_card: Card = (by_pos["bottom"] as Dictionary)["card"] as Card
	_expect(bottom_card.suit == Card.Suit.SPADES and bottom_card.rank == Card.Rank.ACE, "Local bottom history card should be the original server-left card")
	view.free()

func _started_context(human_count: int) -> Dictionary:
	var manager := RoomManager.new()
	for i in human_count:
		manager.register_peer(PEERS[i], NAMES[i])
	var out := manager.handle_create_room(PEERS[0], {"code": ROOM_CODES[human_count - 1]})
	var code := String(out[0][1]["data"]["code"])
	for i in range(1, human_count):
		manager.handle_join_room(PEERS[i], {"code": code})
	manager.handle_start_game(PEERS[0])
	var room := manager.room_for_peer(PEERS[0])
	return {
		"manager": manager,
		"room": room,
		"session": room.game_session,
		"code": code,
	}

func _declare_trump_if_needed(session: GameSession) -> Array:
	if session.round_manager.state != RoundManager.RoundState.TRUMP_SELECTION:
		return []
	var seat := session.round_manager.trump_selector_seat
	var peer := _peer_for_seat(session, seat)
	var suit := session.players[seat].hand.dominant_suit()
	if peer > 0:
		return session.handle_declare_trump(peer, {"suit": int(suit)})
	else:
		session.round_manager.declare_trump(suit)
		return session.drain_events()

func _advance_to_non_host_turn(session: GameSession) -> int:
	for _i in 80:
		if session.round_manager.state == RoundManager.RoundState.PLAYER_TURN:
			var seat := session.round_manager.current_player_seat
			var peer := _peer_for_seat(session, seat)
			if peer > 0 and peer != PEERS[0]:
				return seat
			_play_one_human_or_ai_action(session)
		else:
			session.tick(0.5)
	return -1

func _play_one_human_or_ai_action(session: GameSession) -> Array:
	var rm := session.round_manager
	var out: Array = []
	match rm.state:
		RoundManager.RoundState.TRUMP_SELECTION:
			out = _declare_trump_if_needed(session)
		RoundManager.RoundState.PLAYER_TURN:
			var seat := rm.current_player_seat
			var peer := _peer_for_seat(session, seat)
			if peer > 0:
				var valid := session.players[seat].hand.get_valid_cards(rm.current_trick.led_suit, rm.trump_suit)
				if not valid.is_empty():
					out = session.handle_play_card(peer, {"card": Protocol.card_to_dict(valid[0])})
			else:
				_tick_until_progress(session, rm.state)
		RoundManager.RoundState.TRICK_DISPLAY, RoundManager.RoundState.TRICK_RESOLUTION:
			_tick_until_progress(session, rm.state)
		_:
			session.tick(0.25)
	if out.is_empty():
		out = session.drain_events()
	return out

func _drive_to_round_end(session: GameSession) -> void:
	var steps := 0
	while not session.between_rounds and steps < MAX_DRIVE_STEPS:
		steps += 1
		_play_one_human_or_ai_action(session)
	_expect(session.between_rounds, "Round should end within drive limit")

func _drive_to_first_trick_completed(session: GameSession) -> Array:
	for _i in MAX_DRIVE_STEPS:
		var before := session.round_manager.trick_history.size()
		var out := _play_one_human_or_ai_action(session)
		if session.round_manager.trick_history.size() > before:
			return out
	return []

func _tick_until_progress(session: GameSession, previous_state: int) -> void:
	for _i in 16:
		session.tick(0.25)
		if session.round_manager.state != previous_state or session.round_manager.state == RoundManager.RoundState.ROUND_OVER:
			return

func _tick_until_card_count_changes(session: GameSession, seat: int, before_count: int) -> void:
	for _i in 20:
		session.tick(0.25)
		session.drain_events()
		if session.players[seat].hand.size() != before_count:
			return

func _expire_turn_timer(session: GameSession) -> void:
	session._turn_deadline_sec = maxf(0.001, float(Time.get_ticks_msec()) / 1000.0 - 0.001)

func _peer_for_seat(session: GameSession, seat: int) -> int:
	for peer in session.peer_to_seat.keys():
		if int(session.peer_to_seat[peer]) == seat:
			return int(peer)
	return -1

func _count_type(outgoing: Array, type: String, target_peer: int = -1) -> int:
	var count := 0
	for pair in outgoing:
		if pair.size() < 2:
			continue
		if target_peer != -1 and int(pair[0]) != target_peer:
			continue
		var msg: Dictionary = pair[1]
		if String(msg.get("type", "")) == type:
			count += 1
	return count

func _message_data(outgoing: Array, type: String, target_peer: int = -1) -> Dictionary:
	for pair in outgoing:
		if pair.size() < 2:
			continue
		if target_peer != -1 and int(pair[0]) != target_peer:
			continue
		var msg: Dictionary = pair[1]
		if String(msg.get("type", "")) == type:
			return msg.get("data", {}) as Dictionary
	return {}

func _error_code(outgoing: Array) -> String:
	if outgoing.is_empty():
		return ""
	var msg: Dictionary = outgoing[0][1]
	if String(msg.get("type", "")) != Protocol.MSG_ERROR:
		return ""
	return String((msg.get("data", {}) as Dictionary).get("code", ""))

func _cleanup_context(ctx: Dictionary) -> void:
	var session := ctx.get("session", null) as GameSession
	if session != null and session.round_manager != null:
		session.round_manager.free()
		session.round_manager = null

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
