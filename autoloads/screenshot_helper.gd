extends Node

## Dev-only autoload. Activates when launched with `-- --shot-out=<path>` and
## optionally `--shot-delay=<seconds>`. Captures the viewport after the delay,
## writes a PNG to `path`, then quits. No-op without --shot-out.

var _out_path: String = ""
var _delay: float = 4.0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-out="):
			_out_path = arg.substr("--shot-out=".length())
		elif arg.begins_with("--shot-delay="):
			_delay = float(arg.substr("--shot-delay=".length()))
	if _out_path == "":
		return
	get_tree().create_timer(_delay).timeout.connect(_capture)

func _capture() -> void:
	# game_table_ui._process handles the --shot-show-timer override directly,
	# so by the time we get here the label is already visible.
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_path)
	if err != OK:
		push_error("screenshot_helper: save_png failed err=%d path=%s" % [err, _out_path])
	else:
		print("[screenshot_helper] wrote %s" % _out_path)
	get_tree().quit()
