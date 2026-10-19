extends SceneTree
## The one script every tool starts with. The tool is its first user argument:
##   tools/run/godot_lock.sh godot --headless --path . --script res://tools/lib/tool_runner.gd -- res://tools/verify/physics/verify_audit.gd
## More arguments after the tool are the tool's own (OS.get_cmdline_user_args()
## lists the tool first).
##
## Godot compiles a script given to --script before it registers the
## autoloads, and the scripts the first one names are compiled with it. A tool
## that names the level or the player then fails on every autoload name. So
## this script names nothing of the game: it loads the tool once the autoloads
## are in place. A tool extends tool_script.gd (or level_tool.gd) and never
## SceneTree.
##
## `--check` in place of the tool runs no tool: it compiles every script under
## tools/ (or the scripts and folders named after it) as a run compiles a tool,
## and prints a line per script that fails, then "TOOL_CHECK scripts=<n>
## failed=<m>". A script fails when it does not compile, or when it extends a
## MainLoop: such a script starts by --script and compiles before the
## autoloads. Exit code 1 when one fails.
##   tools/run/godot_lock.sh godot --headless --path . --script res://tools/lib/tool_runner.gd -- --check
##
## A runtime error of a script or a push_error() while the tool runs fails
## the run (script_error_log.gd): at the exit it prints a line per error,
## "TOOL_SCRIPT_ERROR <text>", then "TOOL_RESULT FAIL script_errors=<n>",
## and the exit code is 1. The verdict of a tool goes through verdict() of
## tool_script.gd, which gives FAIL once an error came. An error the tool
## waits for is marked with expect_error() and prints "TOOL_EXPECTED_ERROR".

const CHECK := "--check"
const TOOLS := "res://tools"
const ScriptErrorLog := preload("res://tools/lib/script_error_log.gd")
## A run without a window has no RenderingDevice: the beer of the player's
## mug does not simulate, and beer_fluid.gd says so by push_error(). There the
## error is expected.
const NO_GPU_BEER := "Beer simulation requires Godot Forward+ or Mobile rendering."

var _tool: Object
var _errors: ScriptErrorLog
var _processes := false
var _physics_processes := false

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("tool_runner.gd: no tool given; pass res://tools/...gd after --")
		quit(2)
		return
	if arguments[0] == CHECK:
		quit(_check(arguments.slice(1) if arguments.size() > 1 else PackedStringArray([TOOLS])))
		return
	var script := load(arguments[0]) as GDScript
	if script == null or not script.can_instantiate():
		push_error("tool_runner.gd: cannot load the tool '%s'" % arguments[0])
		quit(2)
		return
	_tool = script.new()
	if _tool == null or not _tool.has_method("attach"):
		push_error("tool_runner.gd: '%s' does not extend tools/lib/tool_script.gd" % arguments[0])
		quit(2)
		return
	_errors = ScriptErrorLog.new(true)
	if DisplayServer.get_name() == "headless":
		_errors.expect(NO_GPU_BEER)
	OS.add_logger(_errors)
	set_meta(ScriptErrorLog.META, _errors)
	_tool.call("attach", self)
	_processes = _tool.has_method("_process")
	_physics_processes = _tool.has_method("_physics_process")
	_tool.call("_initialize")

## The errors caught while the tool ran fail the run, whatever exit code the
## tool gave: quit() here sets the exit code that Godot returns.
func _finalize() -> void:
	if _errors == null:
		return
	OS.remove_logger(_errors)
	for message: String in _errors.expected():
		print("TOOL_EXPECTED_ERROR ", message)
	var found := _errors.take()
	if found.is_empty():
		return
	for message: String in found:
		print("TOOL_SCRIPT_ERROR ", message)
	print("TOOL_RESULT FAIL script_errors=%d" % found.size())
	quit(1)

## Compiles the scripts at `paths` (files and folders); the exit code.
func _check(paths: PackedStringArray) -> int:
	var scripts: PackedStringArray = []
	for path: String in paths:
		if path.ends_with(".gd"):
			scripts.append(path)
		else:
			_collect(path, scripts)
	var failed := 0
	for path: String in scripts:
		var script := load(path) as GDScript
		var why := ""
		if script == null or not script.can_instantiate():
			why = "does not compile"
		elif path != get_script().resource_path and ClassDB.is_parent_class(script.get_instance_base_type(), "MainLoop"):
			why = "extends a MainLoop: it compiles before the autoloads; extend tools/lib/tool_script.gd"
		if not why.is_empty():
			failed += 1
			print("TOOL_CHECK_FAILED %s: %s" % [path, why])
	print("TOOL_CHECK scripts=%d failed=%d" % [scripts.size(), failed])
	return 1 if failed > 0 or scripts.is_empty() else 0

func _collect(folder: String, out: PackedStringArray) -> void:
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			out.append(folder.path_join(file))
	for child: String in DirAccess.get_directories_at(folder):
		_collect(folder.path_join(child), out)

## Tools that watch every frame give the same bool as a SceneTree: true quits.
func _process(delta: float) -> bool:
	return _processes and _tool.call("_process", delta)

func _physics_process(delta: float) -> bool:
	return _physics_processes and _tool.call("_physics_process", delta)
