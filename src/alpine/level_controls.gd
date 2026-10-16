extends RefCounted
## The level's own actions: "help" for the controls help and "screenshot",
## and in a debug build or the editor only (debug_keys) the debug ones:
## overview camera, teleports, the weather, the wind on the lake and time of
## day. `level` is the alpine level node (level.gd).
const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")
const LEVEL = preload("res://src/alpine/level.gd")

## Standing on the bay's south beach, facing the island and the far lake.
const BEACH := Vector3(-58, 4, -6)
const BEACH_YAW := 20.0
const WEATHER_KEYS := {KEY_F1: "calm", KEY_F2: "breeze", KEY_F3: "choppy", KEY_F4: "storm"}

## Whether the debug keys work: in a debug build or the editor, never in a
## player's release build.
static func debug_keys() -> bool:
	return OS.is_debug_build() or OS.has_feature("editor")

static func key_input(level: LEVEL, event: InputEvent) -> void:
	if level.lakeside != null and level.lakeside.panel.visible:
		return
	if event.is_echo():
		return
	# The debug keys are keys of the keyboard, never rebound.
	var key_event := event as InputEventKey
	var key: Key = key_event.physical_keycode if key_event != null and key_event.pressed else KEY_NONE
	if InputActions.pressed(event, "help"):
		LEVEL_HUD.toggle_help(level, debug_keys())
	elif InputActions.pressed(event, "screenshot"):
		level.capture()
	elif key == KEY_NONE:
		return
	elif debug_keys():
		_debug_key(level, key)

static func _debug_key(level: LEVEL, key: Key) -> void:
	if key == KEY_F9:
		toggle_overview(level)
	elif key == KEY_R:
		var spawn := level.region.spawn()
		teleport(level, level.spawn_position, spawn.yaw_deg, spawn.pitch_deg)
	elif key == KEY_B:
		teleport(level, BEACH, BEACH_YAW, -4.0)
	elif WEATHER_KEYS.has(key):
		level.water.ocean.set_preset(WEATHER_KEYS[key])
	elif key == KEY_F5 or key == KEY_F6:
		level.weather.cycle(-1 if key == KEY_F5 else 1)
	elif key == KEY_F7:
		level.weather.auto = not level.weather.auto
		level.update_status()
	elif key == KEY_BRACKETLEFT or key == KEY_BRACKETRIGHT:
		level.sky_system.time_of_day += -1.0 if key == KEY_BRACKETLEFT else 1.0

static func teleport(level: LEVEL, where: Vector3, yaw: float, pitch: float) -> void:
	if level.tavern_interactions.climbing:
		return
	level.lakeside.reset()
	level.tavern_interactions.reset()
	level.camping.fast_travel()
	if level.overview_active:
		toggle_overview(level)
	level.player.position = where
	level.player.velocity = Vector3.ZERO
	level.rig.yaw_deg = yaw
	level.rig.pitch_deg = pitch
	level.rig.apply_look(Vector2.ZERO)

static func toggle_overview(level: LEVEL) -> void:
	if level.lakeside != null and (level.lakeside.aboard or level.lakeside.rod_out or level.lakeside.panel.visible):
		return
	if level.camping != null and level.camping.placing:
		return
	if level.tavern_interactions != null and (level.tavern_interactions.climbing or not level.tavern_interactions.seated.is_empty()):
		return
	level.overview_active = not level.overview_active
	level.player.set_physics_process(not level.overview_active)
	level.player.set_process_unhandled_input(not level.overview_active)
	var first_person: CanvasLayer = level.player.get_node("BeerViewmodel")
	first_person.visible = not level.overview_active
	level.overview.current = level.overview_active
	level.player_camera.current = not level.overview_active
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if level.overview_active else Input.MOUSE_MODE_CAPTURED
