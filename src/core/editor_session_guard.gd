extends Node
## An embedded game can outlive a closed editor on macOS. Only editor-launched
## sessions opt in; ordinary game launches never monitor another process.
const POLL_SECONDS := 1.0
var _editor_pid := 0
var _poll_elapsed := 0.0
var _stopping := false

static func editor_pid_from_args(args: PackedStringArray, self_pid: int) -> int:
	for index in args.size():
		var argument := args[index]
		if argument == "--" or argument == "++":
			break
		var value := ""
		if argument == "--editor-pid":
			if index + 1 >= args.size():
				return 0
			value = args[index + 1]
		elif argument.begins_with("--editor-pid="):
			value = argument.trim_prefix("--editor-pid=")
		else:
			continue
		if value.length() > 10 or not value.is_valid_int():
			return 0
		var pid := value.to_int()
		return pid if pid > 0 and pid <= 2147483647 and pid != self_pid else 0
	return 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_editor_pid = _find_editor_pid()
	set_process(_editor_pid > 0)
	if _editor_pid > 0:
		_check_editor()

func _find_editor_pid() -> int:
	var self_pid := OS.get_process_id()
	var pid := editor_pid_from_args(OS.get_cmdline_args(), self_pid)
	if pid > 0 or OS.get_name() != "macOS" or not OS.has_feature("editor"):
		return pid
	# Godot 4.7 consumes --editor-pid before exposing get_cmdline_args(). Read
	# this process's original command once; never enumerate or alter processes.
	var output: Array = []
	var status := OS.execute("/bin/ps", PackedStringArray([
		"-ww", "-p", str(self_pid), "-o", "command=",
	]), output)
	if status != 0 or output.is_empty():
		return 0
	return editor_pid_from_args(str(output[0]).strip_edges().split(" ", false), self_pid)

func _process(delta: float) -> void:
	if _editor_pid <= 0 or _stopping:
		return
	_poll_elapsed += delta
	if _poll_elapsed < POLL_SECONDS:
		return
	_poll_elapsed = fmod(_poll_elapsed, POLL_SECONDS)
	_check_editor()

func _check_editor() -> void:
	if _editor_pid <= 0 or _stopping or _editor_is_running():
		return
	_stopping = true
	set_process(false)
	# Stop audible output before the scene tree begins releasing GPU resources.
	AudioServer.set_bus_mute(0, true)
	print("EDITOR_SESSION_ENDED editor_pid=", _editor_pid)
	_quit_game()

func _editor_is_running() -> bool:
	if OS.get_name() != "macOS":
		return OS.is_process_running(_editor_pid)
	# macOS's API falls back to child-only bookkeeping after NSRunningApplication
	# disappears. A PID lookup also handles detached/terminal editor processes.
	var output: Array = []
	var status := OS.execute("/bin/ps", PackedStringArray([
		"-p", str(_editor_pid), "-o", "pid=",
	]), output)
	if status == 1:
		return false
	if status != 0 or output.is_empty():
		return true # An unavailable lookup is not proof that the editor exited.
	return str(output[0]).strip_edges().to_int() == _editor_pid

func _quit_game() -> void:
	get_tree().quit()
