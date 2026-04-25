extends Node

## Persistent user settings. Loaded on startup, saved whenever a value changes.

const CONFIG_PATH := "user://settings.cfg"
const MASTER_BUS := 0

## Animation speed is fixed at the previous "Fast" multiplier — the user-facing
## slow/normal/fast toggle was removed from the settings overlay.
const ANIM_MULTIPLIER: float = 0.5

signal changed()

const PLAYER_NAME_MAX_LEN := 12
const MP_USERNAME_DEFAULT := "Guest"

var volume: float = 100.0  # 0-100
var vibration_enabled: bool = true
var mp_username: String = MP_USERNAME_DEFAULT
var auto_sort: bool = true
## The most recently joined/created room code. Drives the "Rejoin Last Room"
## shortcut on the multiplayer menu so the user doesn't have to retype after
## a crash, app kill, or quick relaunch. Cleared by setting to "".
var last_room_code: String = ""

func _ready() -> void:
	_load()
	_apply_volume()

func anim_multiplier() -> float:
	return ANIM_MULTIPLIER

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 100.0)
	_apply_volume()
	_save()
	changed.emit()

func set_vibration_enabled(value: bool) -> void:
	vibration_enabled = value
	_save()
	changed.emit()

func set_auto_sort(value: bool) -> void:
	if value == auto_sort:
		return
	auto_sort = value
	_save()
	changed.emit()

func set_last_room_code(value: String) -> void:
	var trimmed := value.strip_edges().to_upper()
	if trimmed == last_room_code:
		return
	last_room_code = trimmed
	_save()
	changed.emit()

func set_mp_username(value: String) -> void:
	var trimmed := value.strip_edges().substr(0, PLAYER_NAME_MAX_LEN)
	if trimmed == "":
		trimmed = MP_USERNAME_DEFAULT
	if trimmed == mp_username:
		return
	mp_username = trimmed
	_save()
	changed.emit()

func _apply_volume() -> void:
	var linear := volume / 100.0
	var db := -80.0 if linear <= 0.0 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(MASTER_BUS, db)

func _load() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return
	volume = clampf(float(cfg.get_value("audio", "volume", 100.0)), 0.0, 100.0)
	vibration_enabled = bool(cfg.get_value("haptics", "vibration_enabled", true))
	var mp_val := String(cfg.get_value("player", "mp_username", MP_USERNAME_DEFAULT)).strip_edges()
	if mp_val == "":
		mp_val = MP_USERNAME_DEFAULT
	mp_username = mp_val.substr(0, PLAYER_NAME_MAX_LEN)
	auto_sort = bool(cfg.get_value("gameplay", "auto_sort", true))
	last_room_code = String(cfg.get_value("multiplayer", "last_room_code", "")).strip_edges().to_upper()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("haptics", "vibration_enabled", vibration_enabled)
	cfg.set_value("player", "mp_username", mp_username)
	cfg.set_value("gameplay", "auto_sort", auto_sort)
	cfg.set_value("multiplayer", "last_room_code", last_room_code)
	cfg.save(CONFIG_PATH)
