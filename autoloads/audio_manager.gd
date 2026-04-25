extends Node

# Placeholder SFX autoload. Swap streams later when real assets arrive.

const STREAMS := {
	"card_play": preload("res://assets/sounds/card_play.wav"),
	"shuffle": preload("res://assets/sounds/shuffle.wav"),
	"trick_win": preload("res://assets/sounds/trick_win.wav"),
	"round_win": preload("res://assets/sounds/round_win.wav"),
	"round_loss": preload("res://assets/sounds/round_loss.wav"),
}

# Pool of players so overlapping SFX don't cut each other off
const POOL_SIZE := 6
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0

func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(sfx: String, volume_db: float = 0.0) -> void:
	var stream: AudioStream = STREAMS.get(sfx)
	if stream == null:
		push_warning("AudioManager: unknown sfx '%s'" % sfx)
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.play()
