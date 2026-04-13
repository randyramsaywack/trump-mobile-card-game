extends Node

## Persistent user settings. Loaded on startup, saved whenever a value changes.

const CONFIG_PATH := "user://settings.cfg"
const MASTER_BUS := 0

enum AnimSpeed { SLOW, NORMAL, FAST }

const ANIM_MULTIPLIER := {
	AnimSpeed.SLOW: 1.5,
	AnimSpeed.NORMAL: 1.0,
	AnimSpeed.FAST: 0.5,
}

const ANIM_LABEL := {
	AnimSpeed.SLOW: "Slow",
	AnimSpeed.NORMAL: "Normal",
	AnimSpeed.FAST: "Fast",
}

signal changed()

const PLAYER_NAME_MAX_LEN := 12
const MP_USERNAME_DEFAULT := "Guest"

var volume: float = 100.0  # 0-100
var anim_speed: int = AnimSpeed.NORMAL
var vibration_enabled: bool = true
var mp_username: String = MP_USERNAME_DEFAULT
var auto_sort: bool = true

func _ready() -> void:
	_load()
	_apply_volume()

func anim_multiplier() -> float:
	return ANIM_MULTIPLIER[anim_speed]

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 100.0)
	_apply_volume()
	_save()
	changed.emit()

func set_anim_speed(value: int) -> void:
	if not ANIM_MULTIPLIER.has(value):
		return
	anim_speed = value
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
	var s := int(cfg.get_value("video", "anim_speed", AnimSpeed.NORMAL))
	if ANIM_MULTIPLIER.has(s):
		anim_speed = s
	vibration_enabled = bool(cfg.get_value("haptics", "vibration_enabled", true))
	var mp_val := String(cfg.get_value("player", "mp_username", MP_USERNAME_DEFAULT)).strip_edges()
	if mp_val == "":
		mp_val = MP_USERNAME_DEFAULT
	mp_username = mp_val.substr(0, PLAYER_NAME_MAX_LEN)
	auto_sort = bool(cfg.get_value("gameplay", "auto_sort", true))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("video", "anim_speed", anim_speed)
	cfg.set_value("haptics", "vibration_enabled", vibration_enabled)
	cfg.set_value("player", "mp_username", mp_username)
	cfg.set_value("gameplay", "auto_sort", auto_sort)
	cfg.save(CONFIG_PATH)
