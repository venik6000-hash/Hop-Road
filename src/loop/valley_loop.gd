class_name ValleyLoop
extends Node
## What makes the valley go by itself in the game: the clock runs (GameClock),
## the weather changes, a bed in a guest room takes the night away, and the
## game's time, the weather and what the player has (PlayerState: the
## coins, the mug, the food in the hand, where they stood) are kept between
## sessions. The level starts it (start_loop): the
## world loader once the level stands; a level opened by a tool has none and
## stays at the hour it was given, unless the tool starts it.
##
## The loop gives SaveService the sections of the game: its own fields at the
## top of the file (to_dict), the player's (PlayerState.SECTION), and those
## of the region's parts it has: the
## villagers (NpcPopulation), the brewery (BrewHouse), the fires (CampSystem)
## and the catch (FishingState). The brewery and the fires keep places in the
## world coordinates of the region: they are sections of the region
## (SaveService.REGIONS). It tells GameEvents of the sleep and of the night
## slept, and watches the region's ways out (RegionDoors).

const REGION_DOORS = preload("res://src/world/region_doors.gd")
## Seconds a sleeper's eyes take to close, stay shut and open again.
const CLOSE_SECONDS := 1.4
const DARK_SECONDS := 0.8
const OPEN_SECONDS := 2.0
## Seconds between looks at which zone the player stands in.
const ZONE_SECONDS := 0.5
## Seconds of play the word about the help (Tab) stays on the screen, the last of them
## fading (LEVEL_HUD's "Hint").
const HINT_SECONDS := 14.0
const HINT_FADE := 2.0
## The moment in a level without the loop: a fair day that stands still.
const STILL := {"day": 1, "part": "day", "weather": "fair", "zone": "", "beer": "", "beer_flaw": ""}

## The region of the level.
var region: RegionDef
var weather: WeatherSystem
var player: Player
var interactions: TavernInteractions
## The region's people, whose sheets are saved; none in a region without them.
var population: NpcPopulation
## The fires, which are saved; none in a region without them.
var camping: CampSystem
## The lake's activities, whose catch is saved; none in a level without them.
var lakeside: LakesideSystem
## The brewery's day; none in a level without the brewery.
var brewing: BrewHouse
## The game's day (GameClock.day): from 1, a day begins at dawn (DayClock.DAY_START).
var day: int:
	get:
		return GameClock.day()
## The night is passing behind closed eyes.
var sleeping := false
var zones: ValleyZones
## The villagers' day: who is where at this hour.
var presence: VillagerPresence
## The zone the player stands in ("" out in the open valley).
var zone := ""

var _zone_in := 0.0
var _veil: ColorRect
var _hint: Label
var _hint_left := HINT_SECONDS
## The player's sections whose system the region does not have, as they were
## read: section key -> its data.
var _kept: Dictionary = {}

func _ready() -> void:
	brewing = get_tree().get_first_node_in_group(BrewHouse.GROUP) as BrewHouse
	# The brewery's trade pays from and into the player's purse.
	if brewing != null:
		brewing.trade.use_purse(player.state)
	# The loop's own fields first, then what the player has.
	SaveService.add_section(SaveService.ROOT, to_dict, restore)
	SaveService.add_section(PlayerState.SECTION, player_section, restore_player)
	if population != null:
		SaveService.add_section("people", population.to_dict, population.restore)
	else:
		_keep_section("people")
	if brewing != null:
		SaveService.add_section("brewing", brewing.to_dict, brewing.restore, region.id)
	if camping != null:
		SaveService.add_section("camping", camping.to_dict, camping.restore, region.id)

	if is_instance_valid(lakeside):
		SaveService.add_section("fishing", lakeside.fishing.to_dict, lakeside.fishing.restore)
		# A loop started again in the same level finds the catch tied already.
		if not lakeside.fishing.changed.is_connected(SaveService.save_soon):
			lakeside.fishing.changed.connect(SaveService.save_soon)
	else:
		_keep_section("fishing")
	SaveService.load_save()
	# The level stands in this region, whatever the save named.
	SaveService.region = region.id
	var doors: REGION_DOORS = REGION_DOORS.new()
	doors.name = "RegionDoors"
	doors.exits = region.exits
	doors.player = player
	add_child(doors)
	if population != null:
		presence = VillagerPresence.new()
		presence.name = "VillagerPresence"
		presence.population = population
		presence.player = player
		presence.camera = player.camera
		presence.weather = weather
		presence.interactions = interactions
		add_child(presence)
		presence.apply_now()
	GameClock.running = true
	weather.auto = true
	interactions.valley = self
	if camping != null:
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

## Keeps the player's section `key`, whose system the region does not have,
## as it was read. A region's sections stay in the file by themselves
## (SaveService.REGIONS); a player's section would be lost.
func _exit_tree() -> void:
	GameClock.running = false

func _keep_section(key: String) -> void:
	_kept[key] = {}
	SaveService.add_section(key, _kept_data.bind(key), _keep_data.bind(key))

func _kept_data(key: String) -> Dictionary:
	var data: Dictionary = _kept[key]
	return data

func _keep_data(data: Dictionary, key: String) -> void:
	_kept[key] = data

func _process(delta: float) -> void:
	_zone_in -= delta
	if _zone_in <= 0.0:
		_zone_in = ZONE_SECONDS
		zone = zones.zone_at(player.global_position)
		if _on_foot():
			player.state.place = {"at": player.global_position, "yaw": player.rig.yaw_deg}
			# The spawn the player came in at is behind them now.
			SaveService.spawn = &""
	if _hint != null and _hint.visible and InputActions.in_play():
		_hint_left -= delta
		_hint.modulate.a = clampf(_hint_left / HINT_FADE, 0.0, 1.0)
		if _hint_left <= 0.0:
			_hint.visible = false

## Whether the player stands on the ground on their own feet: a mode of the
## feet (Player.on_feet: not in a seat, on the ladder, in the boat or
## asleep), on the floor and not in the water. A body a tool or the loading
## holds still (its physics off) stands nowhere yet.
func _on_foot() -> bool:
	return player.on_feet() and player.is_physics_processing() and player.is_on_floor() and not player.swimming

## What a story may depend on, now: {day, part (DayClock.part), weather
## (WeatherSystem.kind), zone, beer and beer_flaw (beer_words)}.
func moment() -> Dictionary:
	var now := {"day": day, "part": DayClock.part(GameClock.hour()), "weather": weather.kind, "zone": zone}
	now.merge(beer_words(player.state.mug_beer,brewing.book if is_instance_valid(brewing) else null))
	return now

## The player's own beer in the mug as a moment has it: {beer (the recipe of
## the book it is, BrewBook.name_beer), beer_flaw (its first flaw)}; both ""
## for the tavern's old beer.
static func beer_words(beer: Dictionary, book: BrewBook) -> Dictionary:
	if beer.is_empty() or book == null:
		return {"beer": "", "beer_flaw": ""}
	var flaws: Array = beer.get("flaws", [])
	return {"beer": str(book.name_beer(beer).get("id", "")), "beer_flaw": str(flaws[0]) if not flaws.is_empty() else ""}

## A night in a guest room's bed: the eyes close, and open at DayClock.WAKE_HOUR
## of the morning with the weather the night has left. The night is lived
## (GameClock.pass_minutes: the brewery's hours); GameEvents hears of the
## sleep and of the night (the villagers' places); the valley is saved at the
## morning.
func sleep_till_morning() -> void:
	if sleeping or not player.enter(Player.SLEEP, self):
		return
	sleeping = true
	GameEvents.sleep_started.emit()
	var fade := create_tween()
	fade.tween_property(_veil, "color:a", 1.0, CLOSE_SECONDS)
	await fade.finished
	var slept := DayClock.hours_until_wake(GameClock.hour())
	weather.skip(DayClock.seconds_for(GameClock.hour(), slept))
	GameClock.pass_hours(slept)
	GameEvents.night_slept.emit(slept)
	SaveService.save()
	fade = create_tween()
	fade.tween_interval(DARK_SECONDS)
	fade.tween_property(_veil, "color:a", 0.0, OPEN_SECONDS)
	await fade.finished
	player.leave(self)
	sleeping = false

## How far the sleeper's eyes are shut: 0 open, 1 dark.
func eyes_shut() -> float:
	return _veil.color.a

## What a sleeper who lies down in day `of_day` at `hour` wakes to: {day, hour,
## seconds (of real time the clock would have taken)}.
static func night(of_day: int, hour: float) -> Dictionary:
	var hours := DayClock.hours_until_wake(hour)
	return {"day": of_day + DayClock.dawns_passed(hour, hours), "hour": DayClock.WAKE_HOUR,
		"seconds": DayClock.seconds_for(hour, hours)}

## The loop's section of the save: its fields at the top of the file (pack).
func to_dict() -> Dictionary:
	return pack(GameClock.minutes, weather.kind)

## Takes back to_dict() from a save (the whole file: unpack picks the fields).
func restore(saved: Dictionary) -> void:
	var fields := unpack(saved)
	var minutes := Values.real(fields.minutes)
	if minutes >= 0.0:
		# The saved time is set, not lived: nothing runs through the way to it.
		GameClock.set_minutes(minutes)
	weather.set_weather(str(fields.weather), true)

## The player's section of the save (PlayerState.to_dict). While the player
## has not stood in the region since a spawn, the place they stood at is of
## another region or of before: it is not written.
func player_section() -> Dictionary:
	return player.state.to_dict(SaveService.spawn.is_empty())

## Takes back player_section() from a save: what the player has, and the
## player at the place they stood, unless they come in at a spawn.
func restore_player(saved: Dictionary) -> void:
	player.state.restore(saved)
	if not SaveService.spawn.is_empty():
		player.state.place = {}
		return
	var place := player.state.place
	if place.is_empty():
		return
	var at: Vector3 = place.at
	var yaw: float = place.yaw
	player.global_position = at + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.rig.yaw_deg = yaw
	player.rig.apply_look(Vector2.ZERO)

## The loop's fields as they stand at the top of the file: `minutes` the
## game's time (GameClock.minutes) and the weather.
static func pack(minutes: float, kind: String) -> Dictionary:
	return {"minutes": minutes, "weather": kind}

## The loop's fields of a save (SaveService.read), checked: {minutes (the
## game's time, -1 when the save has none), day and hour (of those minutes:
## 1 and -1 when there are none), weather}; what is wrong takes the start's
## value.
static func unpack(data: Variant) -> Dictionary:
	var saved: Dictionary = data if data is Dictionary else {}
	var kind: Variant = saved.get("weather")
	var minutes := Values.number(saved.get("minutes"), -1.0, 0.0, 1e12)
	return {
		"minutes": minutes,
		"day": DayClock.day_of(minutes) if minutes >= 0.0 else 1,
		"hour": DayClock.hour_of(minutes) if minutes >= 0.0 else -1.0,
		"weather": kind if kind is String and WeatherTable.KINDS.has(kind) else "fair",
	}
