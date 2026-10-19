extends Node
## The level's own keys: "help" for the controls help and "screenshot", and in
## a debug build or the editor only (debug_keys) the debug ones: overview
## camera, teleports, the weather, the wind on the lake and time of day. The
## level makes it and hands it what the keys work on before it enters the tree.
const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")

const WEATHER_KEYS := {KEY_F1: "calm", KEY_F2: "breeze", KEY_F3: "choppy", KEY_F4: "storm"}

## Told when the line of the weather and the hour is to be written again.
signal status_changed

## The node that holds the "Controls" canvas (LEVEL_HUD.build): the level's "Shared".
var hud: Node3D
var region: RegionDef
var player: Player
var overview: Camera3D
var sky: SkySystem
var weather: WeatherSystem
var water: WaterSystem
var interactions: TavernInteractions
var camping: CampSystem
var lakeside: LakesideSystem
## Where R takes the player: the level's spawn, on the ground once it stands,
## and the region's spawn it is (RegionSpawn.id).
var spawn := Vector3.ZERO
var spawn_id := &""
## The spawn of the region B took the player to last (an index of
## RegionDef.spawns); -1 before the first B.
var _toured := -1
## The overview camera shows in place of the player's eye (F9).
var overview_active := false

## Whether the debug keys work: in a debug build or the editor, never in a
## player's release build.
static func debug_keys() -> bool:
	return OS.is_debug_build() or OS.has_feature("editor")

func _unhandled_input(event: InputEvent) -> void:
	if lakeside != null and lakeside.panel.visible:
		return
	if event.is_echo():
		return
	# The debug keys are keys of the keyboard, never rebound.
	var key_event := event as InputEventKey
	var key: Key = key_event.physical_keycode if key_event != null and key_event.pressed else KEY_NONE
	if InputActions.pressed(event, "help"):
		LEVEL_HUD.toggle_help(hud, debug_keys())
	elif InputActions.pressed(event, "screenshot"):
		capture()
	elif key == KEY_NONE:
		return
	elif debug_keys():
		_debug_key(key)

func _debug_key(key: Key) -> void:
	if key == KEY_F9:
		toggle_overview()
	elif key == KEY_R:
		var start := region.spawn(spawn_id)
		teleport(spawn, start.yaw_deg, start.pitch_deg)
	elif key == KEY_B:
		tour()
	elif WEATHER_KEYS.has(key):
		weather.set_sea(str(WEATHER_KEYS[key]))
	elif key == KEY_F5 or key == KEY_F6:
		weather.cycle(-1 if key == KEY_F5 else 1)
	elif key == KEY_F7:
		weather.auto = not weather.auto
		status_changed.emit()
	elif key == KEY_BRACKETLEFT or key == KEY_BRACKETRIGHT:
		# An hour on is lived (the brewery boils it); an hour back is only set.
		if key == KEY_BRACKETRIGHT:
			GameClock.pass_hours(1.0)
		else:
			GameClock.set_minutes(GameClock.minutes - 60.0)

## The player at the region's next spawn (RegionDef.spawns), the one after the
## spawn R takes them to first: B goes round all of them.
func tour() -> void:
	var spawns := region.spawns
	if spawns.is_empty():
		return
	if _toured < 0:
		_toured = maxi(spawns.find(region.spawn(spawn_id)), 0)
	_toured = (_toured + 1) % spawns.size()
	var place := spawns[_toured]
	teleport(place.position, place.yaw_deg, place.pitch_deg)

## The player put at `where`, looking by `yaw` and `pitch`, out of the boat,
## a seat, a station and the overview.
func teleport(where: Vector3, yaw: float, pitch: float) -> void:
	if interactions.climbing:
		return
	if lakeside != null:
		lakeside.reset()
	interactions.reset()
	if camping != null:
		camping.fast_travel()
	if overview_active:
		toggle_overview()
	player.position = where
	player.velocity = Vector3.ZERO
	player.rig.yaw_deg = yaw
	player.rig.pitch_deg = pitch
	player.rig.apply_look(Vector2.ZERO)

## The overview camera in place of the player's eye, or back; not while the
## player is in the boat, laying a fire, on the ladder or in a seat.
func toggle_overview() -> void:
	if lakeside != null and (lakeside.aboard or lakeside.rod_out or lakeside.panel.visible):
		return
	if camping != null and camping.placing:
		return
	if interactions != null and (interactions.climbing or not interactions.seated.is_empty()):
		return
	overview_active = not overview_active
	player.set_physics_process(not overview_active)
	player.set_process_unhandled_input(not overview_active)
	player.set_first_person(not overview_active)
	overview.current = overview_active
	(player.rig.get_node("Camera3D") as Camera3D).current = not overview_active
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if overview_active else Input.MOUSE_MODE_CAPTURED

## The picture of the viewport saved under user://alpine-screenshots.
func capture() -> void:
	await RenderingServer.frame_post_draw
	var folder := "user://alpine-screenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "/" + Time.get_datetime_string_from_system().replace(":", "-") + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot saved: ", ProjectSettings.globalize_path(path))
