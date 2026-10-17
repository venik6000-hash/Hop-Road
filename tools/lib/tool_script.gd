extends RefCounted
## The base of every tool script (probes, checks, pipeline steps). The tool
## is started by tool_runner.gd, which hands it the SceneTree; the tool never
## extends SceneTree itself (the reason is in tool_runner.gd).
##
## A tool uses what a script that extends SceneTree would: `root`,
## `process_frame`, `physics_frame`, `quit()`, and overrides _initialize()
## (and _process() or _physics_process() returning a bool, as a SceneTree
## does). `tree` is the SceneTree itself, for the code that takes one.

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
