extends Node

signal session_started()
signal round_started(dealer_seat: int, trump_selector_seat: int)
signal round_ended_session(winning_team: int, session_wins: Array)

var round_manager: RoundManager
var players: Array[Player] = []
var session_wins: Array[int] = [0, 0]  # [team0_wins, team1_wins]
var dealer_seat: int = 0
## Tracks the current dealer seat for each team (for rotation within losing team)
var _team_dealer: Dictionary = {0: 0, 1: 2}  # team -> current dealer seat within that team

func _ready() -> void:
	round_manager = RoundManager.new()
	add_child(round_manager)
	round_manager.round_ended.connect(_on_round_ended)

func _process(delta: float) -> void:
	round_manager.tick(delta)

## Start a fresh session: reset session wins, randomize dealer, begin first round.
func start_session() -> void:
	session_wins = [0, 0]
	_setup_players()
	dealer_seat = randi() % 4
	# Track which team is dealing initially
	var dealing_team := 0 if dealer_seat in [0, 1] else 1
	_team_dealer[dealing_team] = dealer_seat
	session_started.emit()
	_start_round()

func _setup_players() -> void:
	players.clear()
	players.append(Player.new(0, "You", true))       # human
	players.append(AIPlayer.new(1, "North"))
	players.append(AIPlayer.new(2, "West"))
	players.append(AIPlayer.new(3, "East"))

func _start_round() -> void:
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
	var current := _team_dealer[losing_team]
	var team_seats: Array[int] = [0, 1] if losing_team == 0 else [2, 3]
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
