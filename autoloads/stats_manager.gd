extends Node

## Persistent single-player stats. Tracks rounds played/won/lost and cumulative
## books for the human team. Saved to disk on every update so partial sessions
## are never lost.

const CONFIG_PATH := "user://stats.cfg"
const STAT_KEYS: Array[String] = [
	"rounds_played",
	"rounds_won",
	"rounds_lost",
	"total_books_won",
	"total_books_lost",
]

signal changed()

var stats: Dictionary = {
	"rounds_played": 0,
	"rounds_won": 0,
	"rounds_lost": 0,
	"total_books_won": 0,
	"total_books_lost": 0,
}

func _ready() -> void:
	_load()

## Team 0 = human + partner. Team 1 = opponents.
func record_trick_winner(winning_team: int) -> void:
	if winning_team == 0:
		stats["total_books_won"] += 1
	else:
		stats["total_books_lost"] += 1
	_save()
	changed.emit()

func record_round_end(winning_team: int) -> void:
	stats["rounds_played"] += 1
	if winning_team == 0:
		stats["rounds_won"] += 1
	else:
		stats["rounds_lost"] += 1
	_save()
	changed.emit()

func reset() -> void:
	for key in STAT_KEYS:
		stats[key] = 0
	_save()
	changed.emit()

func win_rate_percent() -> float:
	var played: int = int(stats["rounds_played"])
	if played <= 0:
		return 0.0
	return float(stats["rounds_won"]) / float(played) * 100.0

func average_books_per_round() -> float:
	var played: int = int(stats["rounds_played"])
	if played <= 0:
		return 0.0
	return float(stats["total_books_won"]) / float(played)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for key in STAT_KEYS:
		stats[key] = int(cfg.get_value("stats", key, 0))

func _save() -> void:
	var cfg := ConfigFile.new()
	for key in STAT_KEYS:
		cfg.set_value("stats", key, stats[key])
	cfg.save(CONFIG_PATH)
