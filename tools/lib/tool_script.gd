extends RefCounted
## The base of every tool script (probes, checks, pipeline steps). The tool
## is started by tool_runner.gd, which hands it the SceneTree; the tool never
## extends SceneTree itself (the reason is in tool_runner.gd).
##
## A tool uses what a script that extends SceneTree would: `root`,
## `process_frame`, `physics_frame`, `quit()`, and overrides _initialize()
## (and _process() or _physics_process() returning a bool, as a SceneTree
## does). `tree` is the SceneTree itself, for the code that takes one.

const ScriptErrorLog := preload("res://tools/lib/script_error_log.gd")

var tree: SceneTree
var root: Window
var process_frame: Signal
var physics_frame: Signal

## Called by tool_runner.gd before _initialize().
func attach(main_loop: SceneTree) -> void:
	tree = main_loop
	root = main_loop.root
	process_frame = main_loop.process_frame
	physics_frame = main_loop.physics_frame
	main_loop.set_meta("tool", self)

## The start of the tool. Override it.
func _initialize() -> void:
	pass

func quit(exit_code: int = 0) -> void:
	tree.quit(exit_code)

## "PASS" when `ok` and no script error came so far (tool_runner.gd), else
## "FAIL". Every verdict line of a check uses it.
func verdict(ok: bool) -> String:
	return "PASS" if ok and no_script_errors() else "FAIL"

## True when no script error came so far.
func no_script_errors() -> bool:
	return script_errors().is_empty()

## The errors of scripts and of push_error() caught so far.
func script_errors() -> PackedStringArray:
	var errors := error_log(tree)
	return errors.peek() if errors != null else PackedStringArray()

## Marks the errors whose text has `fragment` as expected: they do not fail
## the run. Call it before the code that gives them.
func expect_error(fragment: String) -> void:
	var errors := error_log(tree)
	if errors != null:
		errors.expect(fragment)

## The error log of the tool run in `main_loop` (tool_runner.gd); null when
## no runner set one.
static func error_log(main_loop: SceneTree) -> ScriptErrorLog:
	var meta: Object = main_loop.get_meta(ScriptErrorLog.META, null)
	return meta as ScriptErrorLog
