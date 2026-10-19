extends Node
## The loading screen: builds the level of `region` under itself by stages
## behind an opaque overlay (docs/LEVEL.md, «Загрузка и запуск»). GameFlow
## opens the save's slot first and makes it the scene. A tool adds it alone
## (tools/lib/tool_level.gd): then the loop keeps nothing.

## The level stands and plays (`ok`), or the loading has failed (`error`).
signal finished(ok: bool)
## The level is made and has not entered the tree yet: a tool sets its
## switches (level.world) or gives its player another script here.
signal level_made(level: Node)
var loaded := false
var failed := false
## Why the loading failed; "" while it has not.
var error := ""
var _started := 0
var _stage_started := 0
## Keep the real first view behind an opaque overlay until staged construction,
## deferred habitat work and initial material uploads have completed.
const InputGate = preload("res://src/loading/input_gate.gd")
const WORLD := "res://scenes/alpine/main.tscn"
const PACK = preload("res://src/village/village_pack.gd")
const LEVEL = preload("res://src/alpine/level.gd")
const LoadWatch = preload("res://src/loading/load_watch.gd")
## A stage this long (ms) is most likely waiting for shaders to compile.
const NOTE_AFTER := 12000
## Per kind of launch, the engine build whose shaders the system has compiled.
const WARM_MARKER := "user://shader_warmup.cfg"
## One literal: a key of the table is the whole text.
const COLD_NOTE := "Первый запуск после обновления движка или шейдеров может занять несколько минут:\nсистема один раз собирает шейдеры. Следующие запуски будут быстрыми."
var _message: Label
var _overlay: CanvasLayer
## The level being built, then playing; null after a failure.
var world: Node
var _gate: InputGate
var _stage := "Загружаем долину…"
## The region to build: the one way a region comes into the game. Whoever
## starts the loader may set it first, or name its file in `region_path`
## (GameFlow does, and the region loads behind the overlay); the first region
## of the game's list (RegionDef.LIST) otherwise.
var region: RegionDef
var region_path := ""
## The spawn of the region the player comes in at (RegionSpawn.id); "" for
## its first.
var spawn := &""
var _watch := LoadWatch.new()
## The valley goes by itself once it stands (ValleyLoop). A tool that keeps
## the hour it gives, or starts the loop itself, turns this off first.
var starts_loop := true
var _note := false

func _ready() -> void:
	_started = Time.get_ticks_msec()
	_stage_started = _started
	_overlay = CanvasLayer.new()
	_overlay.layer = 120
	var background := ColorRect.new()
	background.color = Color("101d20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(background)
	_message = Label.new()
	_note = not _shaders_warm()
	_message.text = _text()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 24)
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(_message)
	add_child(_overlay)
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	# Parse the world's interconnected scripts on the main thread.
	# Loading this scripted scene on a worker deadlocks
	# on Godot 4.7.2 while the main thread waits on the script loader lock.
	_set_stage("Читаем сцену долины…")
	if region == null:
		var path := region_path if not region_path.is_empty() else RegionDef.path_of(&"")
		region = load(path) as RegionDef if not path.is_empty() else null
	var scene := load(WORLD) as PackedScene
	if scene == null or region == null:
		_fail("Не удалось загрузить сцену долины.")
		return
	var unreadable := DataFiles.unreadable(region)
	if not unreadable.is_empty():
		for problem in unreadable:
			push_error("World data: " + problem)
		_fail(tr("Данные области не читаются: %s") % unreadable[0])
		return
	# The village pack's models, for a region that has the pack.
	if region.has_part(&"village_pack"):
		_set_stage("Загружаем модели деревни…")
		var assets_ready := await PACK.prefetch_assets(get_tree(), _prefetch_progress, region.props)
		if failed:
			return
		if not assets_ready:
			_fail("Не удалось загрузить модели деревни.")
			return
	else:
		PACK.discard_prefetch()
	_set_stage("Создаём мир…")
	# A frame for the words: making the level holds the main thread.
	await get_tree().process_frame
	if failed:
		return
	var level: LEVEL = scene.instantiate()
	level.region = region
	level.spawn_id = spawn
	world = level
	level_made.emit(level)
	# Disabling the parent process_mode removes CollisionObject3Ds from physics.
	# Pause callbacks only, so placement rays see all real obstacles throughout.
	level.set_process(false)
	level.set_physics_process(false)
	_gate = InputGate.new()
	_gate.lock(level, get_tree())
	level.loading_stage.connect(_set_stage)
	add_child(level)
	# The level's player is known once the level is in the tree; no physics
	# frame has passed yet.
	level.player.set_physics_process(false)
	while not failed and not level.built():
		await get_tree().process_frame
	if failed:
		return
	_set_stage("Оживают лес и озеро…")
	# Deferred builders explicitly await physics frames even while player input
	# and world processing are held. No placeholder world is revealed.
	while not level.ready_for_visitors():
		await get_tree().physics_frame
		if failed:
			return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if failed:
		return
	_set_stage("Последние приготовления…")
	# The saved hour and weather, before the frames that warm the first view.
	if starts_loop:
		level.start_loop()
	level.set_process(true)
	level.set_physics_process(true)
	# Draw the actual materials at the actual camera. This warms the first view,
	# not every possible shader variant or future camera position.
	for frame in 6:
		await get_tree().process_frame
		if failed:
			return
	level.player.set_physics_process(true)
	_gate.release()
	_gate = null
	_overlay.queue_free()
	loaded = true
	mark_shaders_warm()
	print("WORLD_READY staged=true seconds=%.3f" % ((Time.get_ticks_msec() - _started) / 1000.0))
	finished.emit(true)

func _prefetch_progress(completed: int, total: int) -> bool:
	if failed:
		return false
	_set_stage(tr("Загружаем модели деревни… %d/%d") % [completed, total])
	return true

func _set_stage(message: String) -> void:
	if failed:
		return
	_stage = message
	_stage_started = Time.get_ticks_msec()
	_watch.begin()
	_message.text = _text()
	print("WORLD_LOADING %.2f s %s" % [(_stage_started - _started) / 1000.0, message])

## The screen's words: a stage is a key of the table or words translated.
func _text() -> String:
	return tr("Хмельная тропа") + "\n\n" + tr(_stage) + ("\n\n" + tr(COLD_NOTE) if _note else "")

## The system's shader cache is one per engine build and, on macOS, one per
## program and per Godot process running at a time: a game started from the
## open editor, the engine started alone and the exported game each fill
## their own, and each is slow exactly once.
static func launch_kind() -> String:
	if EngineDebugger.is_active():
		return "editor"
	return "standalone_" + OS.get_executable_path().md5_text().left(12)

static func _shaders_warm() -> bool:
	var config := ConfigFile.new()
	if config.load(WARM_MARKER) != OK:
		return false
	return str(config.get_value("shaders", launch_kind(), "")) == str(Engine.get_version_info().hash)

## A run without a window compiles no shaders, so it marks nothing.
static func mark_shaders_warm() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var config := ConfigFile.new()
	config.load(WARM_MARKER)
	config.set_value("shaders", launch_kind(), str(Engine.get_version_info().hash))
	config.save(WARM_MARKER)

func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	error = message
	PACK.discard_prefetch()
	_message.text = tr(message) + "\n" + tr("Перезапустите игру.")
	if _gate != null:
		_gate.release()
		_gate = null
	if is_instance_valid(world):
		world.queue_free()
	world = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	push_error("World startup failed at '%s': %s" % [_stage, message])
	finished.emit(false)

func _process(delta: float) -> void:
	if loaded or failed:
		return
	var stalled := _watch.tick(delta)
	if not _note and Time.get_ticks_msec() - _stage_started > NOTE_AFTER:
		_note = true
		_message.text = _text()
	if stalled:
		_fail(tr("Этап загрузки не завершился за 3 минуты: %s") % tr(_stage))
