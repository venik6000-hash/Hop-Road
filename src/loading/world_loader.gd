extends Node
## The loading screen: builds the level of `region` under itself by stages
## behind an opaque overlay (docs/LEVEL.md, «Загрузка и запуск»). GameFlow
## opens the save's slot first and makes it the scene; a tool may add it alone,
## and then the loop keeps nothing.

## The level stands and plays (`ok`), or the loading has failed (`error`).
signal finished(ok: bool)
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
## Seconds of frames that keep coming which one stage may take.
const STALL_SECONDS := 180.0
## The most one frame adds to that: a frame held up by the graphics driver is
## slow, not stalled.
const STALL_STEP := 0.25
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
## starts the loader may set it first; the first region of the game's list
## (RegionDef.listed()) otherwise.
var region: RegionDef
var _stage_idle := 0.0
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
		var regions := RegionDef.listed()
		region = regions[0] if not regions.is_empty() else null
	var scene := load(WORLD) as PackedScene
	if scene == null or region == null:
		_fail("Не удалось загрузить сцену долины.")
		return
	_set_stage("Загружаем модели деревни…")
	var assets_ready := await PACK.prefetch_assets(get_tree(), _prefetch_progress, region.props)
	if failed:
		return
	if not assets_ready:
		_fail("Не удалось загрузить модели деревни.")
		return
	_set_stage("Создаём мир…")
	var level: LEVEL = scene.instantiate()
	level.region = region
	world = level
	level.staged_loading = true
	# Disabling the parent process_mode removes CollisionObject3Ds from physics.
	# Pause callbacks only, so placement rays see all real obstacles throughout.
	level.set_process(false)
	level.set_physics_process(false)
	var player := level.get_node("Player")
	player.set_physics_process(false)
	_gate = InputGate.new()
	_gate.lock(level, get_tree())
	level.loading_stage.connect(_set_stage)
	add_child(level)
	while not failed and not level.has_meta("load_complete"):
		await get_tree().process_frame
	if failed:
		return
	_set_stage("Оживают лес и озеро…")
	# Deferred builders explicitly await physics frames even while player input
	# and world processing are held. No placeholder world is revealed.
	while not level.wildlife.ready_for_visitors or not level.village_pack.forest_ready or not level.flora.ready_for_visitors:
		await get_tree().physics_frame
		if failed:
			return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if failed:
		return
	_set_stage("Последние приготовления…")
	# The saved hour and weather, before the frames that warm the first view.
	ValleyLoop.start(level)
	level.set_process(true)
	level.set_physics_process(true)
	# Draw the actual materials at the actual camera. This warms the first view,
	# not every possible shader variant or future camera position.
	for frame in 6:
		await get_tree().process_frame
		if failed:
			return
	player.set_physics_process(true)
	_gate.release()
	_gate = null
	_overlay.queue_free()
	loaded = true
	_mark_shaders_warm()
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
	_stage_idle = 0.0
	_message.text = _text()
	print("WORLD_LOADING ", message)

## The screen's words: a stage is a key of the table or words translated.
func _text() -> String:
	return tr("Хмельная тропа") + "\n\n" + tr(_stage) + ("\n\n" + tr(COLD_NOTE) if _note else "")

## The system's shader cache is one per engine build and, on macOS, one per
## Godot process running at a time: a game started from the open editor fills
## another than a game started alone, and each is slow exactly once.
static func _launch_kind() -> String:
	return "editor" if EngineDebugger.is_active() else "standalone"

static func _shaders_warm() -> bool:
	var config := ConfigFile.new()
	if config.load(WARM_MARKER) != OK:
		return false
	return str(config.get_value("shaders", _launch_kind(), "")) == str(Engine.get_version_info().hash)

static func _mark_shaders_warm() -> void:
	var config := ConfigFile.new()
	config.load(WARM_MARKER)
	config.set_value("shaders", _launch_kind(), str(Engine.get_version_info().hash))
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
	# A new engine build has Metal compile every shader on first use, and the
	# frame that needs them waits, for minutes at worst. That is progress the
	# loader cannot see, so the watchdog counts the frames that do arrive: a
	# stage fails only when they keep coming and it stands still.
	_stage_idle += minf(delta, STALL_STEP)
	if not _note and Time.get_ticks_msec() - _stage_started > NOTE_AFTER:
		_note = true
		_message.text = _text()
	if _stage_idle > STALL_SECONDS:
		_fail(tr("Этап загрузки не завершился за 3 минуты: %s") % tr(_stage))
