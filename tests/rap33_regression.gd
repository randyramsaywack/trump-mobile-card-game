extends Node

const PEERS: Array[int] = [101, 202, 303, 404]
const NAMES: Array[String] = ["Host", "Lefty", "Partner", "Righty"]

var _failures: Array[String] = []

func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("[rap33] PASS regression checks")
	else:
		for failure in _failures:
			push_error("[rap33] " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _run() -> void:
	_test_deck_unique_52()
	_test_follow_suit_valid_cards()
	_test_trick_resolution()
	_test_round_initial_and_final_deal_counts()
	_test_round_ends_at_7_books()
	_test_dealer_rotation()
	_test_server_validation_errors()

func _test_deck_unique_52() -> void:
	var deck := Deck.new()
	_expect(deck.cards.size() == 52, "Deck should build 52 cards")
	var seen := {}
	for card in deck.cards:
		var c := card as Card
		var key := "%d:%d" % [int(c.suit), int(c.rank)]
		_expect(not seen.has(key), "Deck should not duplicate %s" % key)
		seen[key] = true
	_expect(seen.size() == 52, "Deck should contain 52 unique suit/rank pairs")

func _test_follow_suit_valid_cards() -> void:
	var hand := Hand.new()
	var spade := Card.new(Card.Suit.SPADES, Card.Rank.ACE)
	var heart := Card.new(Card.Suit.HEARTS, Card.Rank.TWO)
	var club := Card.new(Card.Suit.CLUBS, Card.Rank.KING)
	hand.add_cards([spade, heart, club])
	var valid := hand.get_valid_cards(Card.Suit.HEARTS, Card.Suit.SPADES)
	_expect(valid.size() == 1 and valid[0] == heart, "Hand must follow led suit when possible")
	valid = hand.get_valid_cards(Card.Suit.DIAMONDS, Card.Suit.SPADES)
	_expect(valid.size() == 3, "Hand may play any card when void in led suit")

func _test_trick_resolution() -> void:
	var trick := Trick.new(Card.Suit.SPADES)
	trick.play_card(0, Card.new(Card.Suit.HEARTS, Card.Rank.ACE))
	trick.play_card(1, Card.new(Card.Suit.HEARTS, Card.Rank.TWO))
	trick.play_card(2, Card.new(Card.Suit.SPADES, Card.Rank.THREE))
	trick.play_card(3, Card.new(Card.Suit.CLUBS, Card.Rank.ACE))
	_expect(trick.get_winner_index() == 2, "Trump should beat led-suit ace")

	var no_trump := Trick.new(Card.Suit.CLUBS)
	no_trump.play_card(0, Card.new(Card.Suit.DIAMONDS, Card.Rank.KING))
	no_trump.play_card(1, Card.new(Card.Suit.HEARTS, Card.Rank.ACE))
	no_trump.play_card(2, Card.new(Card.Suit.DIAMONDS, Card.Rank.TWO))
	no_trump.play_card(3, Card.new(Card.Suit.DIAMONDS, Card.Rank.ACE))
	_expect(no_trump.get_winner_index() == 3, "Highest led suit should win when no trump is played")

func _test_round_initial_and_final_deal_counts() -> void:
	var rm := RoundManager.new()
	add_child(rm)
	var players := _four_human_players()
	var dealer := 3
	rm.start_round(players, dealer)
	var selector := (dealer + 1) % 4
	for seat in 4:
		var expected := 5 if seat == selector else 0
		_expect(players[seat].hand.size() == expected, "Initial deal seat %d should have %d cards" % [seat, expected])
	rm.declare_trump(players[selector].hand.dominant_suit())
	for seat in 4:
		_expect(players[seat].hand.size() == 13, "Final deal seat %d should have 13 cards" % seat)
	_expect(rm.current_player_seat == selector, "Trump selector should lead first trick")
	rm.free()

func _test_round_ends_at_7_books() -> void:
	var rm := RoundManager.new()
	add_child(rm)
	var players := _four_human_players()
	rm.players = players
	rm.trump_suit = Card.Suit.SPADES
	rm.current_player_seat = 0
	rm.current_trick = Trick.new(rm.trump_suit)
	rm.books = [6, 0]
	var ended: Array[int] = []
	rm.round_ended.connect(func(winning_team: int): ended.append(winning_team))
	players[0].hand.add_cards([Card.new(Card.Suit.HEARTS, Card.Rank.ACE)])
	players[1].hand.add_cards([Card.new(Card.Suit.HEARTS, Card.Rank.KING)])
	players[2].hand.add_cards([Card.new(Card.Suit.HEARTS, Card.Rank.QUEEN)])
	players[3].hand.add_cards([Card.new(Card.Suit.HEARTS, Card.Rank.JACK)])
	for seat in 4:
		rm.play_card(seat, players[seat].hand.cards[0])
	_expect(rm.books[0] == 7, "Team 0 should reach 7 books after winning trick")
	_expect(rm.state == RoundManager.RoundState.TRICK_DISPLAY, "Round should pause in trick display after decisive trick")
	rm.tick(RoundManager.TRICK_DISPLAY_DURATION * Settings.anim_multiplier() + 0.1)
	_expect(ended.size() == 1 and ended[0] == 0, "Round should emit round_ended for team 0 at 7 books")
	_expect(rm.state == RoundManager.RoundState.ROUND_OVER, "Round state should be ROUND_OVER after decisive trick display")
	rm.free()

func _test_dealer_rotation() -> void:
	GameState._team_dealer = {0: 0, 1: 1}
	GameState._rotate_dealer(0)
	_expect(GameState.dealer_seat == 2, "Team 0 losing dealer should rotate 0 -> 2")
	GameState._rotate_dealer(0)
	_expect(GameState.dealer_seat == 0, "Team 0 losing dealer should rotate 2 -> 0")
	GameState._rotate_dealer(1)
	_expect(GameState.dealer_seat == 3, "Team 1 losing dealer should rotate 1 -> 3")
	GameState._rotate_dealer(1)
	_expect(GameState.dealer_seat == 1, "Team 1 losing dealer should rotate 3 -> 1")

func _test_server_validation_errors() -> void:
	var manager := RoomManager.new()
	for i in PEERS.size():
		manager.register_peer(PEERS[i], NAMES[i])
	var out := manager.handle_play_card(999, {"card": {"suit": 0, "rank": 2}})
	_expect(_error_code(out) == Protocol.ERR_NOT_IN_GAME, "Server should reject play_card from peer not in a game")

	out = manager.handle_create_room(PEERS[0])
	var code := String(out[0][1]["data"]["code"])
	for i in range(1, PEERS.size()):
		manager.handle_join_room(PEERS[i], {"code": code})
	manager.handle_start_game(PEERS[0])
	var room := manager.room_for_peer(PEERS[0])
	var session := room.game_session
	var selector := session.round_manager.trump_selector_seat
	var selector_peer := _peer_for_seat(session, selector)
	var other_peer := _peer_for_non_seat(session, selector)

	out = session.handle_play_card(selector_peer, {"card": Protocol.card_to_dict(session.players[selector].hand.cards[0])})
	_expect(_error_code(out) == Protocol.ERR_WRONG_PHASE, "Server should reject play_card during trump selection")

	out = session.handle_declare_trump(other_peer, {"suit": int(Card.Suit.SPADES)})
	_expect(_error_code(out) == Protocol.ERR_NOT_YOUR_TURN, "Server should reject trump declaration from non-selector")

	out = session.handle_declare_trump(selector_peer, {"suit": 99})
	_expect(_error_code(out) == Protocol.ERR_INVALID_CARD, "Server should reject invalid trump suit")

	var trump := session.players[selector].hand.dominant_suit()
	session.handle_declare_trump(selector_peer, {"suit": int(trump)})
	var current := session.round_manager.current_player_seat
	var current_peer := _peer_for_seat(session, current)
	var not_current_peer := _peer_for_non_seat(session, current)

	out = session.handle_play_card(not_current_peer, {"card": Protocol.card_to_dict(session.players[session.peer_to_seat[not_current_peer]].hand.cards[0])})
	_expect(_error_code(out) == Protocol.ERR_NOT_YOUR_TURN, "Server should reject play_card from non-active seat")

	out = session.handle_play_card(current_peer, {"card": {"suit": 9, "rank": 2}})
	_expect(_error_code(out) == Protocol.ERR_INVALID_CARD, "Server should reject malformed card payload")

	var illegal := _find_illegal_follow_suit_card(session, current)
	if illegal.is_empty():
		push_warning("[rap33] skipped illegal follow-suit server validation; current hand did not have a mixed-suit case")
	else:
		out = session.handle_play_card(current_peer, {"card": Protocol.card_to_dict(illegal["card"])})
		_expect(_error_code(out) == Protocol.ERR_INVALID_CARD, "Server should reject card that violates follow-suit")

	session.between_rounds = true
	out = session.handle_declare_trump(selector_peer, {"suit": int(Card.Suit.SPADES)})
	_expect(_error_code(out) == Protocol.ERR_WRONG_PHASE, "Server should reject trump declaration between rounds")
	session.round_manager.free()

func _four_human_players() -> Array[Player]:
	return [
		Player.new(0, "P0", true),
		Player.new(1, "P1", true),
		Player.new(2, "P2", true),
		Player.new(3, "P3", true),
	]

func _peer_for_seat(session: GameSession, seat: int) -> int:
	for peer in session.peer_to_seat.keys():
		if int(session.peer_to_seat[peer]) == seat:
			return int(peer)
	return -1

func _peer_for_non_seat(session: GameSession, seat: int) -> int:
	for peer in session.peer_to_seat.keys():
		if int(session.peer_to_seat[peer]) != seat:
			return int(peer)
	return -1

func _find_illegal_follow_suit_card(session: GameSession, current: int) -> Dictionary:
	var player := session.players[current]
	var suits := {}
	for c in player.hand.cards:
		if not suits.has(c.suit):
			suits[c.suit] = []
		suits[c.suit].append(c)
	if suits.size() < 2:
		return {}
	var led_suit: Card.Suit = suits.keys()[0] as Card.Suit
	var illegal: Card = null
	for c in player.hand.cards:
		if c.suit != led_suit:
			illegal = c
			break
	if illegal == null:
		return {}
	session.round_manager.current_trick = Trick.new(session.round_manager.trump_suit)
	session.round_manager.current_trick.play_card((current + 1) % 4, Card.new(led_suit, Card.Rank.TWO))
	return {"card": illegal}

func _error_code(outgoing: Array) -> String:
	if outgoing.is_empty():
		return ""
	var msg: Dictionary = outgoing[0][1]
	if String(msg.get("type", "")) != Protocol.MSG_ERROR:
		return ""
	return String((msg.get("data", {}) as Dictionary).get("code", ""))

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
