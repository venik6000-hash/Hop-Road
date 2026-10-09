extends Node
var loaded := false
var failed := false
var _started := 0
var _stage_started := 0
## Keep the real first view behind an opaque overlay until staged construction,
## deferred habitat work and initial material uploads have completed.
const InputGate = preload("res://src/loading/input_gate.gd")
const WORLD := "res://scenes/alpine/main.tscn"
const PACK = preload("res://src/village/village_pack.gd")
## Seconds of frames that keep coming which one stage may take.
const STALL_SECONDS := 180.0
## The most one frame adds to that: a frame held up by the graphics driver is
## slow, not stalled.
const STALL_STEP := 0.25
## A stage this long (ms) is most likely waiting for shaders to compile.
const NOTE_AFTER := 12000
## Per kind of launch, the engine build whose shaders the system has compiled.
const WARM_MARKER := "user://shader_warmup.cfg"
const COLD_NOTE := "Первый запуск после обновления движка или шейдеров может занять несколько минут:\n" \
	+ "система один раз собирает шейдеры. Следующие запуски будут быстрыми."
var _message: Label
var _overlay: CanvasLayer
var _world: Node
var _gate: RefCounted
var _stage := "Загружаем долину…"
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
	var scene := load(WORLD) as PackedScene
	if scene == null:
		_fail("Не удалось загрузить сцену долины.")
		return
	_set_stage("Загружаем модели деревни…")
	var assets_ready := await PACK.prefetch_assets(get_tree(), _prefetch_progress)
	if failed:
		return
	if not assets_ready:
		_fail("Не удалось загрузить модели деревни.")
		return
	_set_stage("Создаём мир…")
	var world := scene.instantiate()
	_world = world
	world.staged_loading = true
	# Disabling the parent process_mode removes CollisionObject3Ds from physics.
	# Pause callbacks only, so placement rays see all real obstacles throughout.
	world.set_process(false)
	world.set_physics_process(false)
	var player := world.get_node("Player")
	player.set_physics_process(false)
	_gate = InputGate.new()
	_gate.lock(world, get_tree())
	world.loading_stage.connect(_set_stage)
	add_child(world)
	while not failed and not world.has_meta("load_complete"):
		await get_tree().process_frame
	if failed:
		return
	_set_stage("Оживают лес и озеро…")
	# Deferred builders explicitly await physics frames even while player input
	# and world processing are held. No placeholder world is revealed.
	while not world.wildlife.ready_for_visitors or not world.village_pack.forest_ready or not world.flora.ready_for_visitors:
		await get_tree().physics_frame
		if failed:
			return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if failed:
		return
	_set_stage("Последние приготовления…")
	world.set_process(true)
	world.set_physics_process(true)
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

func _prefetch_progress(completed: int, total: int) -> bool:
	if failed:
		return false
	_set_stage("Загружаем модели деревни… %d/%d" % [completed, total])
	return true

func _set_stage(message: String) -> void:
	if failed:
		return
	_stage = message
	_stage_started = Time.get_ticks_msec()
	_stage_idle = 0.0
	_message.text = _text()
	print("WORLD_LOADING ", message)

func _text() -> String:
	return "Хмельная тропа\n\n" + _stage + ("\n\n" + COLD_NOTE if _note else "")

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
	PACK.discard_prefetch()
	_message.text = message + "\nПерезапустите игру."
	if _gate != null:
		_gate.release()
		_gate = null
	if is_instance_valid(_world):
		_world.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	push_error("World startup failed at '%s': %s" % [_stage, message])

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
		_fail("Этап загрузки не завершился за 3 минуты: " + _stage)
