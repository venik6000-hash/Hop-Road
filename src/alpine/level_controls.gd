extends RefCounted
## The level's own keys: Tab for the controls help, and the debug ones —
## overview camera, teleports, the weather, the wind on the lake, time of day
## and screenshots. `level` is the alpine level node (level.gd).
const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")

## Standing on the bay's south beach, facing the island and the far lake.
const BEACH := Vector3(-58, 4, -6)
const BEACH_YAW := 20.0
const WEATHER_KEYS := {KEY_F1: "calm", KEY_F2: "breeze", KEY_F3: "choppy", KEY_F4: "storm"}

static func key_input(level: Node3D, event: InputEvent) -> void:
	if level.lakeside != null and level.lakeside.panel.visible:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: Key = event.physical_keycode
	if key == KEY_TAB:
		LEVEL_HUD.toggle_help(level)
	elif key == KEY_F9:
		toggle_overview(level)
	elif key == KEY_R:
		teleport(level, level.spawn_position, -30.0, 10.0)
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
	elif key == KEY_F12:
		level.capture()

static func teleport(level: Node3D, where: Vector3, yaw: float, pitch: float) -> void:
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

static func toggle_overview(level: Node3D) -> void:
	if level.lakeside != null and (level.lakeside.aboard or level.lakeside.rod_out or level.lakeside.panel.visible):
		return
	if level.camping != null and level.camping.placing:
		return
	if level.tavern_interactions != null and (level.tavern_interactions.climbing or not level.tavern_interactions.seated.is_empty()):
		return
	level.overview_active = not level.overview_active
	level.player.set_physics_process(not level.overview_active)
	level.player.set_process_unhandled_input(not level.overview_active)
	level.player.get_node("BeerViewmodel").visible = not level.overview_active
	level.overview.current = level.overview_active
	level.player_camera.current = not level.overview_active
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if level.overview_active else Input.MOUSE_MODE_CAPTURED
