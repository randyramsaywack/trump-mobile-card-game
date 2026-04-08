extends Node

signal session_started()
signal round_started(dealer_seat: int, trump_selector_seat: int)
signal round_ended_session(winning_team: int, session_wins: Array)

var round_manager: RoundManager
var players: Array[Player] = []
var session_wins: Array[int] = [0, 0]  # [team0_wins, team1_wins]
var dealer_seat: int = 0
## Global AI difficulty — applied uniformly to all AI players at the start of
## every round. Session-only (not persisted to disk). Cannot change mid-round.
var ai_difficulty: int = AIPlayer.Difficulty.MEDIUM
## When true, the human's hand is kept visually sorted by suit/rank.
## Delegates to Settings.auto_sort for persistence.
var sort_enabled: bool:
	get: return Settings.auto_sort
	set(value): Settings.set_auto_sort(value)
## Tracks the current dealer seat for each team (for rotation within losing team).
## Team 0 = seats [0, 2] (human + partner). Team 1 = seats [1, 3] (opponents).
var _team_dealer: Dictionary = {0: 0, 1: 1}  # team -> current dealer seat within that team

func _ready() -> void:
	round_manager = RoundManager.new()
	add_child(round_manager)
	round_manager.round_ended.connect(_on_round_ended)
	# Single-player stats: track every trick and every round finish.
	round_manager.trick_completed.connect(_on_trick_completed_stats)
	round_manager.round_ended.connect(_on_round_ended_stats)

func _process(delta: float) -> void:
	if round_manager != null:
		round_manager.tick(delta)

## Start a fresh session: reset session wins, randomize dealer, begin first round.
func start_session() -> void:
	session_wins = [0, 0]
	_setup_players()
	dealer_seat = randi() % 4
	# Initialize dealer tracking for both teams
	var starting_dealing_team := 0 if dealer_seat in [0, 2] else 1
	var starting_other_team := 1 - starting_dealing_team
	_team_dealer[starting_dealing_team] = dealer_seat
	# Other team's default dealer: use the lower-index seat of that team
	_team_dealer[starting_other_team] = 0 if starting_other_team == 0 else 1
	session_started.emit()
	_start_round()

func _setup_players() -> void:
	players.clear()
	players.append(Player.new(0, "You", true))       # human
	players.append(AIPlayer.new(1, "West"))
	players.append(AIPlayer.new(2, "North"))
	players.append(AIPlayer.new(3, "East"))

func _start_round() -> void:
	# Apply current difficulty uniformly to all AIs before the round begins.
	for p in players:
		if p is AIPlayer:
			(p as AIPlayer).difficulty = ai_difficulty
	round_started.emit(dealer_seat, (dealer_seat + 1) % 4)
	round_manager.start_round(players, dealer_seat)

func _on_round_ended(winning_team: int) -> void:
	session_wins[winning_team] += 1
	round_ended_session.emit(winning_team, session_wins.duplicate())
	# Losing team deals next round — rotate within their two seats
	var losing_team := 1 - winning_team
	_rotate_dealer(losing_team)

## Alternate between the two seats of the losing team.
func _rotate_dealer(losing_team: int) -> void:
	var current: int = _team_dealer[losing_team]
	var team_seats: Array[int] = [0, 2] if losing_team == 0 else [1, 3]
	var other_seat: int = team_seats[1] if current == team_seats[0] else team_seats[0]
	_team_dealer[losing_team] = other_seat
	dealer_seat = other_seat

func start_next_round() -> void:
	_start_round()

## Convenience accessors for UI scripts
func get_player(seat: int) -> Player:
	if seat >= 0 and seat < players.size():
		return players[seat]
	return null

func get_round_manager() -> RoundManager:
	return round_manager

func get_books() -> Array:
	return round_manager.books.duplicate()

func get_trump_suit() -> Card.Suit:
	return round_manager.trump_suit

## Single-player stats hooks — single player is the only mode today, so every
## trick/round counts.
func _on_trick_completed_stats(winner_seat: int, _books: Array) -> void:
	var winning_team := 0 if winner_seat in [0, 2] else 1
	StatsManager.record_trick_winner(winning_team)

func _on_round_ended_stats(winning_team: int) -> void:
	StatsManager.record_round_end(winning_team)

## Trigger a handheld vibration for the given duration in milliseconds.
## Respects the persisted vibration toggle. Silently does nothing on
## non-mobile platforms so it is safe to call from shared code paths.
func vibrate(duration_ms: int) -> void:
	if Settings.vibration_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)
