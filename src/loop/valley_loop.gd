class_name ValleyLoop
extends Node
## What makes the valley go by itself in the game: the clock runs, the weather
## changes, the days are counted, a bed in a guest room takes the night away,
## and the day, the hour, the weather, where the player stood and what they
## have with the villagers (PeopleBook) are kept between sessions. The world
## loader starts it once the level stands; a level opened by a tool has none
## and stays at the hour it was given.

const SAVE_VERSION := 1
## Seconds between saves while the game runs, and seconds within which a
## change that should not be lost is written (save_soon).
const SAVE_SECONDS := 20.0
const SOON_SECONDS := 2.0
## Seconds a sleeper's eyes take to close, stay shut and open again.
const CLOSE_SECONDS := 1.4
const DARK_SECONDS := 0.8
const OPEN_SECONDS := 2.0
## Seconds between looks at which zone the player stands in.
const ZONE_SECONDS := 0.5
## Seconds of play the word about Tab stays on the screen, the last of them
## fading (LEVEL_HUD's "Hint").
const HINT_SECONDS := 14.0
const HINT_FADE := 2.0
## How far from the middle of the map, and how low and high, a saved place
## may lie to be taken for one.
const PLACE_REACH := 2000.0
const PLACE_HEIGHTS := Vector2(-50.0, 300.0)
## The moment in a level without the loop: a fair day that stands still.
const STILL := {"day": 1, "part": "day", "weather": "fair", "zone": ""}

var sky: SkySystem
var weather: WeatherSystem
var player: Player
var interactions: TavernInteractions
var camping: CampSystem
## Where the valley is kept; empty keeps nothing (tools).
var save_path := "user://valley.json"
## Game days since the first; a day begins at dawn (DayClock.DAY_START).
var day := 1
## The night is passing behind closed eyes.
var sleeping := false
var zones: ValleyZones
## The villagers' day: who is where at this hour.
var presence: VillagerPresence
## The zone the player stands in ("" out in the open valley).
var zone := ""

var _last_hour := 0.0
var _save_in := SAVE_SECONDS
var _zone_in := 0.0
var _veil: ColorRect
## The last place the player stood on their feet: {at: Vector3, yaw: degrees};
## empty until they have.
var _place: Dictionary = {}
var _hint: Label
var _hint_left := HINT_SECONDS

## Starts the loop in the loaded alpine level (level.gd); the valley is kept
## in the file `path` (see save_path).
static func start(level: Node, path := "user://valley.json") -> ValleyLoop:
	var loop := ValleyLoop.new()
	loop.name = "ValleyLoop"
	loop.save_path = path
	loop.sky = level.sky_system
	loop.weather = level.weather
	loop.player = level.player
	loop.interactions = level.tavern_interactions
	loop.camping = level.camping
	level.add_child(loop)
	return loop

func _ready() -> void:
	zones = ValleyZones.load_file()
	_restore()
	presence = VillagerPresence.new()
	presence.name = "VillagerPresence"
	presence.population = camping.population
	presence.player = player
	presence.camera = player.get_node("CameraRig/Camera3D") as Camera3D
	presence.sky = sky
	presence.weather = weather
	presence.interactions = interactions
	add_child(presence)
	presence.apply_now()
	sky.day_minutes = DayClock.DAY_MINUTES
	sky.night_minutes = DayClock.NIGHT_MINUTES
	weather.auto = true
	_last_hour = sky.time_of_day
	interactions.valley = self
	camping.valley = self
	_hint = get_parent().get_node_or_null("Controls/Hint") as Label
	if _hint != null:
		_hint.visible = true
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	_veil = ColorRect.new()
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_veil)

func _process(delta: float) -> void:
	var hour := sky.time_of_day
	day = DayClock.day_after(day, _last_hour, hour)
	_last_hour = hour
	_zone_in -= delta
	if _zone_in <= 0.0:
		_zone_in = ZONE_SECONDS
		zone = zones.zone_at(player.global_position)
		if _on_foot():
			_place = {"at": player.global_position, "yaw": player.rig.yaw_deg}
	if _hint != null and _hint.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_hint_left -= delta
		_hint.modulate.a = clampf(_hint_left / HINT_FADE, 0.0, 1.0)
		if _hint_left <= 0.0:
			_hint.visible = false
	_save_in -= delta
	if _save_in <= 0.0:
		save()

## Whether the player stands on the ground on their own feet: not in a seat,
## on the ladder, in the boat, in the water or asleep.
func _on_foot() -> bool:
	return player.is_physics_processing() and player.is_on_floor() and not player.swimming \
		and interactions.seated.is_empty() and not interactions.climbing and not sleeping

## What a story may depend on, now: {day, part (DayClock.part), weather
## (WeatherSystem.kind), zone}.
func moment() -> Dictionary:
	return {"day": day, "part": DayClock.part(sky.time_of_day), "weather": weather.kind, "zone": zone}

## A night in a guest room's bed: the eyes close, and open at DayClock.WAKE_HOUR
## of the morning with the weather the night has left. Companions go home.
func sleep_till_morning() -> void:
	if sleeping:
		return
	sleeping = true
	player.movement_locked = true
	camping.fast_travel()
	var fade := create_tween()
	fade.tween_property(_veil, "color:a", 1.0, CLOSE_SECONDS)
	await fade.finished
	var morning := night(day, sky.time_of_day)
	weather.skip(morning.seconds)
	day = morning.day
	sky.time_of_day = morning.hour
	_last_hour = sky.time_of_day
	presence.apply_now()
	save()
	fade = create_tween()
	fade.tween_interval(DARK_SECONDS)
	fade.tween_property(_veil, "color:a", 0.0, OPEN_SECONDS)
	await fade.finished
	player.movement_locked = false
	sleeping = false

## What a sleeper who lies down in day `of_day` at `hour` wakes to: {day, hour,
## seconds (of real time the clock would have taken)}.
static func night(of_day: int, hour: float) -> Dictionary:
	var hours := DayClock.hours_until_wake(hour)
	return {"day": of_day + DayClock.dawns_passed(hour, hours), "hour": DayClock.WAKE_HOUR,
		"seconds": DayClock.seconds_for(hour, hours)}

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()

func _exit_tree() -> void:
	save()

## Saves within SOON_SECONDS: something the player would not want to lose
## has changed.
func save_soon() -> void:
	_save_in = minf(_save_in, SOON_SECONDS)

func save() -> void:
	_save_in = SAVE_SECONDS
	if save_path.is_empty() or not is_instance_valid(sky) or not is_instance_valid(weather) \
			or not is_instance_valid(camping) or not is_instance_valid(camping.population):
		return
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(pack(day, sky.time_of_day, weather.kind, camping.population.people.to_dict(), _place)))
	file.close()
	DirAccess.rename_absolute(save_path + ".tmp", save_path)

func _restore() -> void:
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return
	var saved := unpack(JSON.parse_string(FileAccess.get_file_as_string(save_path)))
	if saved.is_empty():
		return
	day = saved.day
	if saved.hour >= 0.0:
		sky.time_of_day = saved.hour
	weather.set_weather(saved.weather, true)
	_place = saved.player
	if not _place.is_empty():
		var at: Vector3 = _place.at
		var yaw: float = _place.yaw
		player.global_position = at + Vector3.UP * 0.05
		player.velocity = Vector3.ZERO
		player.rig.yaw_deg = yaw
		player.rig.apply_look(Vector2.ZERO)
	camping.population.people.restore(saved.people)
	# Those who told their names go by them again.
	camping.population.refresh_titles()

## The valley as it is written to disk; `people` is PeopleBook.to_dict(),
## `place` where the player stood ({at: Vector3, yaw}; {} for nowhere yet).
static func pack(of_day: int, hour: float, kind: String, people: Dictionary = {}, place: Dictionary = {}) -> Dictionary:
	var result := {"version": SAVE_VERSION, "day": of_day, "hour": hour, "weather": kind, "people": people}
	if not place.is_empty():
		var at: Vector3 = place.at
		var yaw: float = place.yaw
		result["player"] = {"at": [at.x, at.y, at.z], "yaw": yaw}
	return result

## A save as read from disk, checked: {} when it is not one, else {day, hour
## (-1 when the save has none), weather, people (for PeopleBook.restore),
## player ({at: Vector3, yaw} where the player stood; {} when the save has no
## place that can be one)}.
static func unpack(data: Variant) -> Dictionary:
	if not data is Dictionary or int(_number(data.get("version"), 0.0, 0.0, 1e6)) != SAVE_VERSION:
		return {}
	var kind: Variant = data.get("weather")
	var hour := _number(data.get("hour"), -1.0, 0.0, 24.0)
	var people: Variant = data.get("people")
	return {
		"day": int(_number(data.get("day"), 1.0, 1.0, 1e9)),
		"hour": fposmod(hour, 24.0) if hour >= 0.0 else -1.0,
		"weather": kind if kind is String and WeatherSystem.KINDS.has(kind) else "fair",
		"people": people if people is Dictionary else {},
		"player": _stood(data.get("player")),
	}

## The place a save holds, {} when it holds none that a player can stand at.
static func _stood(saved: Variant) -> Dictionary:
	if not saved is Dictionary:
		return {}
	var at: Variant = saved.get("at")
	if not at is Array or at.size() != 3:
		return {}
	for value: Variant in at:
		if not (value is float or value is int) or not is_finite(float(value)):
			return {}
	var point := Vector3(float(at[0]), float(at[1]), float(at[2]))
	if absf(point.x) > PLACE_REACH or absf(point.z) > PLACE_REACH or point.y < PLACE_HEIGHTS.x or point.y > PLACE_HEIGHTS.y:
		return {}
	return {"at": point, "yaw": wrapf(_number(saved.get("yaw"), 0.0, -360.0, 360.0), -180.0, 180.0)}

static func _number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback
