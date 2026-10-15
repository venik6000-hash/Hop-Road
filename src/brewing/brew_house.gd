class_name BrewHouse
extends Node3D
## The brewing in the brewery's rooms (docs/plans/brewing.md, stages 2 and 3):
## the brewery's table (brewery.json) made to work. Utensils are taken in the
## hand and put down (BrewCarry); at a station the mouse works it (BrewStation);
## the vessels' surfaces stand at their levels, coloured by the batch; streams
## run, steam rises, the fire under the copper burns; an instrument looked at
## shows its number by the crosshair; the book on the desk opens. The numbers
## are BrewDay's and the cellar's (BrewCellar). A full keg carried to the
## tavern's counter is the one Borr buys and pours from (draw_beer). The trade
## (BrewTrade) is bought at the stalls of the valley (BrewStalls) and its kegs
## sold to the order board and the cart. TavernInteractions asks this node for
## what E can do here. It stands in the building's frame.

const GROUP := &"brew_house"
const LIQUID := preload("res://src/brewing/brew_liquid.gdshader")
const STEAM := preload("res://src/brewing/brew_steam.gdshader")
const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")
## The vessels the day fills: their surfaces of the table.
const VESSELS: Array[String] = [BrewDay.COPPER, BrewDay.MASH_TUN, BrewDay.UNDERBACK, BrewDay.HOP_BACK, BrewDay.COOLSHIP]
## The fermenting tuns' surfaces of the table: the beer and its head of yeast.
const TUN_SURFACES: Array[String] = ["fermenting_tun_1_wort", "fermenting_tun_1_foam", "fermenting_tun_2_wort",
	"fermenting_tun_2_foam"]
## Where a keg stands under a lager cask's tap, from the tap's nozzle: its bung
## hole just in front of the cask's head, the keg lying across the tap on the
## floor. The radius of a keg (its axis lies at that height).
const KEG_AT_TAP := Vector3(0.12, 0.0, 0.0)
const KEG_RADIUS := 0.19
## How far a lager cask's stand keeps from the spring basin's inner rim: its
## wall and the body.
const BASIN_CLEAR := 0.45
## Where the bucket is tipped into a lager cask, from its tap's nozzle: over
## the head's upper rim.
const CASK_MOUTH := Vector3(-0.08, 0.6, 0.0)
## Where a keg lies on the tavern's counter, from the innkeeper's feet at work
## (VillageNPC.work_point): along the counter, on the other side of his place
## from the jug (VillagerPresence.JUG_AT).
const BAR_KEG := Vector3(-0.55, 1.09, -0.75)
const YEAST := Color(0.82, 0.74, 0.55)
## The maltings' grain: in the steeping tub, the heap on the floor, the kiln's.
const MALT_SURFACES: Array[String] = ["steep_grain", "couch_malt", "kiln_malt"]
## The spring's water, always full: the trough's in the brewhouse and the
## basin's in the cellar.
const SPRING_SURFACES: Array[String] = ["liquor_trough_water", "spring_basin_water"]
## Kg of a heap as it was modelled (the floor's, the kiln's).
const HEAP_KG := {"couch_malt": 90.0, "kiln_malt": BrewMaltings.KILN_KG}
## Green malt's tint; how much darker grain shows wet.
const GREEN_MALT := Color(0.68, 0.62, 0.36)
const WET_DARK := 0.3
## Metres an eye reaches, and how close to the middle of the view a thing
## must be to be looked at (TavernInteractions').
const REACH := TavernInteractions.REACH
const AIM := TavernInteractions.TARGET_DOT
## How near its stand the player must be to work a station, m; how near the
## building's origin to have anything of it in reach.
const STAND := 1.2
const NEAR := 20.0
## How much a thing off the middle of the view counts as farther.
const OFF_AIM := 60.0
## Where a held thing hangs before the eye by its kind (the eye's frame,
## turned with the look but kept upright): within the arms' reach (BrewArms).
const HOLD := {"sack": Vector3(0.0, -0.2, -0.4), "vessel": Vector3(0.2, -0.5, -0.36), "tool": Vector3(0.26, -0.3, -0.4),
	"instrument": Vector3(0.2, -0.22, -0.4), "raw": Vector3(0.2, -0.42, -0.4), "log": Vector3(0.22, -0.38, -0.4)}
## A keg is carried across the body by its two heads, its middle before the
## chest: both heads within the arms' reach.
const KEG_HOLD := Vector3(0.0, -0.45, -0.36)
## Where a tipped thing is held at a station, and where what it pours lands:
## anchors of the table, by the work.
const POURS := {"grain": ["mash_in", BrewDay.MASH_TUN], "bucket_mash": ["mash_in", BrewDay.MASH_TUN],
	"bucket_copper": ["copper_hatch", BrewDay.COPPER], "fill_bucket": ["liquor_trough_brim", ""],
	"pour_coolship": ["coolship_pour", BrewDay.COOLSHIP], "weigh_hops": ["balance_pan_left", ""],
	"steep_barley": ["steep_brim", "steep_grain"], "steep_water": ["steep_brim", "steep_grain"], "pour_hopper": ["quern_eye", ""],
	"pour_honey": ["copper_hatch", BrewDay.COPPER]}
## Works whose pour is grain, or as coarse as grain.
const GRAIN_POURS: Array[String] = ["grain", "steep_barley", "pour_hopper", "cherry_cask"]
## Honey and cherries in a stream.
const HONEY := Color(0.72, 0.45, 0.1)
const CHERRY := Color(0.32, 0.03, 0.05)
## The tap or pump a control's water runs through: [nozzle anchor, vessel it fills].
const TAPS := {"liquor_cock": ["liquor_main_outlet", BrewDay.MASH_TUN], "mash_tap": ["mash_tap_nozzle", BrewDay.UNDERBACK],
	"copper_tap": ["copper_tap_nozzle", BrewDay.HOP_BACK], "hop_back_tap": ["hop_back_tap_nozzle", ""]}
## Tilt of a tipped thing at full tip, radians.
const TIP := 1.9
## A held tool's swing at its work: the mallet's lift at a full wind-up,
## radians; how far a log or a handful is drawn back, and the shovel pushed
## along its pass, metres.
const STRIKE_LIFT := 1.2
const THROW_BACK := 0.18
const STRIPE_REACH := 0.25
## Seconds the fingers stay open where they let a thrown thing go.
const LET_GO := 0.3
## Where the body stands at a work the hands do away from it (a part, a pour,
## a paddle): this far from the point the right hand takes, short of its
## stand when there is no room; how far the eye may be over that point
## before the body crouches; the deepest crouch, and metres a second of it.
const ARM_STAND := 0.42
const OVER := 0.6
const CROUCH := 0.8
const CROUCH_PACE := 1.5
## How far to the left of a flat crank's middle the body stands.
const FLAT_CRANK_ASIDE := 0.3
## Room the body is tried for, a step at a time back towards the stand and
## on as many bearings round the point; the highest step or stand it gets
## onto there.
const ROOM_STEP := 0.1
const BEARINGS := 16
const STEP_UP := 0.35
## How high over where it pours a basket or a pot is held, tipped sideways.
const SIDE_OVER := 0.15
## How far before the eye a tipped thing is held over where it pours (no
## nearer its middle than a quarter metre); how far the body leans at a
## station to bring the shoulders (and the eye with them) to a bar out of the
## arm's reach, and metres a second of it.
const HOLD_OUT := 0.4
const LEAN := 0.8
const LEAN_PACE := 1.2
## Metres the eye and the shoulders go down for each metre of the lean over
## a low work: the body bows over it.
const BOW := 0.4
## The head's room, metres: the lean keeps the eye this far from a face,
## and this far back (level) from what it looks at OVER or more below it.
const HEAD := 0.15
const SIGHT := 0.3
## How far the body rises on its toes to a high one.
const RISE := 0.12
## A paddle at work: the blade goes round its vessel's middle, the hands hold
## it this high over the brim (the hatch, for the copper) on the stand's side,
## going round a little with the blade.
const STIR_TOP := 0.3
const STIR_HAND := 0.05
## What things look like: water in a stream, water in a vessel or a trough
## (its wood or stone seen through it), the mash, a sack's grain, hops.
const WATER := Color(0.05, 0.065, 0.07)
const DEEP_WATER := Color(0.3, 0.28, 0.22)
## Hands of depth a vessel's wort is seen through (wort_color).
const VESSEL_DEPTH := 4.0
const MASH := Color(0.5, 0.4, 0.27)
const GRAIN := Color(0.78, 0.62, 0.36)
const HOPS := Color(0.45, 0.55, 0.22)
## Seconds a word stays by the crosshair.
const SAY_SECONDS := 2.5
## Litres a keg must hold for the order board and the cart to take it.
const SALE_L := BrewCellar.KEG_L - 2.0
## What E does at each kind of the trade's places.
const TRADE_KINDS := {"stall": "buy", "order_board": "order", "cart": "cart"}
## Why a ware is not bought, by BrewTrade.buy's word.
const REFUSALS := {"coins": "Не хватает медяков", "full": "Класть некуда", "done": "Это уже есть",
	"order": "Сначала почините третью бочку"}

## Set before it enters the tree: the building's table and the building.
var table: Dictionary
var building: VillageBuilding
var day: BrewDay
var book: BrewBook
var cellar := BrewCellar.new()
var maltings := BrewMaltings.new()
var trade := BrewTrade.load_file()
## The trade's places in the valley; null until the level stands them.
var stalls: BrewStalls
var carry := BrewCarry.new()
## The station the hand works, null when the player walks.
var station: BrewStation
var station_id := ""

## id -> {entry, node (the utensil's own Node3D, origin at its `at`)}.
var _utensils := {}
## id -> {entry, node, material, built (the height it was modelled at)}.
var _surfaces := {}
var _anchors := {}
var _stations := {}
## Moving part id -> its group (BuildingMachinery).
var _groups := {}
## Group -> the pose last given, so a pose is set only when it changes.
var _posed := {}
var _streams := {}
var _steam := {}
## Moving part id -> its entry of the table.
var _moving := {}
var _arms: BrewArms
var _sounds: BrewSounds
## Whether the arms stood in place of the mug's hand in the last frame.
var _arms_shown := false
var _let_go := 0.0
## How far the eye is lowered at the work (the body crouched); how far the
## body leans now, world space.
var _crouch := 0.0
var _leaned := Vector3.ZERO
## What the eye is kept on at the station's work, building frame; whether
## the work is below the chest (the body bows over it as it leans).
var _look := Vector3.ZERO
var _low := false
var _fire: HearthFire
var _kiln_fire: HearthFire
var _interactions: TavernInteractions
var _player: Player
var _camera: Camera3D
var _label: Label
var _panel: BrewBookPanel
var _said := 0.0
var _last_hour := -1.0
## The keg on the counter waits for the world to stand before it is set there.
var _seat_tap := false
## Where the bar's keg lies, world space; found by a ray once the world stands.
var _bar := Transform3D()
var _bar_top := Vector3.ZERO
var _bar_found := false
var _minutes := 0.0
var _motion := Vector2.ZERO
## The held thing's place in the hold frame, as it was taken.
var _held_rest := Transform3D.IDENTITY
## Stall id -> the index of the ware its board offers (the mouse wheel).
var _wares := {}

func _init() -> void:
	add_to_group(GROUP)

func _ready() -> void:
	day = BrewDay.new()
	day.capacity = BrewDay.capacities(table)
	book = BrewBook.load_files()
	for entry: Dictionary in table.get("anchors", []):
		_anchors[entry.id] = _vector(entry.at)
	for entry: Dictionary in table.get("stations", []):
		_stations[entry.id] = entry
	# A station for each lager cask, in front of its tap; before the spring's
	# basin, off its side.
	var basin := _rim("spring_basin_brim")
	basin = basin.grow(BASIN_CLEAR) if basin.has_area() else basin
	for number in range(1, BrewCellar.CASKS + 1):
		var nozzle: Vector3 = _anchors["lager_tap_%d_nozzle" % number]
		var stand := Vector2(nozzle.x + 0.75, nozzle.z)
		if basin.has_point(stand):
			stand.y = basin.position.y
		_stations["lager_%d" % number] = {"id": "lager_%d" % number, "title": "Лагерная бочка",
			"stand": [stand.x, 0.0, stand.y], "look": [nozzle.x - 0.05, nozzle.y + 0.1, nozzle.z]}
	for entry: Dictionary in table.get("moving", []):
		_groups[entry.id] = str(entry.group)
		_moving[entry.id] = entry
	_arms = BrewArms.new()
	_arms.name = "Arms"
	_arms.top_level = true
	add_child(_arms)
	_sounds = BrewSounds.new()
	_sounds.name = "Sounds"
	add_child(_sounds)
	for key: String in ["grain", "pour", "liquor_cock", "mash_tap", "copper_tap", "hop_back_tap", "liquor_pipe", "wort_pump",
			"liquor_spout", "hops", "spout", "fermenter_tap_1", "fermenter_tap_2", "steep_drain", "lager_tap_1", "lager_tap_2", "lager_tap_3", "lager_tap_4"]:
		var stream := BrewStream.new()
		stream.name = key.to_pascal_case() + "Stream"
		add_child(stream)
		_streams[key] = stream
	_steam.copper = _plume(_anchors.copper_hatch, 0.5)
	_steam.mash = _plume(_surface_point(BrewDay.MASH_TUN), 0.6)
	_steam.hop_back = _plume(_surface_point(BrewDay.HOP_BACK), 0.4)
	_steam.coolship = _plume(_surface_point(BrewDay.COOLSHIP), 1.0)
	for vent: Dictionary in table.get("vents", []):
		if vent.kind == "steam":
			_steam.cupola = _plume(_vector(vent.at), 1.4)
	_fire = HearthFire.new()
	_fire.name = "CopperFire"
	add_child(_fire)
	var stoke: Vector3 = _anchors.copper_stoke
	_fire.configure(stoke + Vector3(0.0, -0.13, 0.4), Vector3.RIGHT, 0.45, 0.32)
	_fire.visible = false
	_kiln_fire = HearthFire.new()
	_kiln_fire.name = "KilnFire"
	add_child(_kiln_fire)
	_kiln_fire.configure(_anchors.kiln_stoke + Vector3(0.0, -0.1, 0.3), Vector3.RIGHT, 0.4, 0.3)
	_kiln_fire.visible = false
	for vent: Dictionary in table.get("vents", []):
		if vent.id == "kiln":
			_steam.kiln = _plume(_vector(vent.at), 1.2)

## The trade's stalls, board and cart for the level to stand.
func make_stalls() -> BrewStalls:
	stalls = BrewStalls.new()
	stalls.name = "BrewStalls"
	stalls.build(trade)
	return stalls

## Takes the utensils and the vessels' surfaces out of a part scene onto
## nodes of their own, before the building batches what is left; the scene
## is in the building's frame, as this node is.
func take(scene: Node3D) -> void:
	for entry: Dictionary in table.get("utensils", []):
		var node := _gather(scene, entry.nodes, _vector(entry.at))
		if node != null:
			node.name = str(entry.id).to_pascal_case()
			_utensils[entry.id] = {"entry": entry, "node": node}
	for entry: Dictionary in table.get("surfaces", []):
		if not VESSELS.has(entry.id) and not TUN_SURFACES.has(entry.id) and not MALT_SURFACES.has(entry.id) \
				and not SPRING_SURFACES.has(entry.id):
			continue
		# A heap grows from where it stands.
		var node := _gather(scene, [entry.node], _vector(entry.at) if entry.has("heap") else Vector3.ZERO)
		if node == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = LIQUID
		for item: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			item.material_override = material
		var built := 0.0
		if entry.has("brim"):
			built = float(entry.bottom) + (float(entry.brim) - float(entry.bottom)) * float(entry.level)
		if SPRING_SURFACES.has(entry.id):
			material.set_shader_parameter("tint", DEEP_WATER)
		_surfaces[entry.id] = {"entry": entry, "node": node, "material": material, "built": built}

## The scene's nodes named `names` hung on a new node at `origin`, where they stood.
func _gather(scene: Node3D, names: Array, origin: Vector3) -> Node3D:
	var holder: Node3D
	for name: String in names:
		var item := scene.find_child(name.validate_node_name(), true, false) as Node3D
		if item == null:
			continue
		if holder == null:
			holder = Node3D.new()
			holder.position = origin
			add_child(holder)
		var placed := item.transform
		var above := item.get_parent_node_3d()
		while above != null and above != scene.get_parent():
			placed = above.transform * placed
			above = above.get_parent_node_3d()
		item.get_parent().remove_child(item)
		item.owner = null
		for inner: Node in item.find_children("*", "", true, false):
			inner.owner = null
		holder.add_child(item)
		item.transform = holder.transform.affine_inverse() * placed
	return holder

## The player's hands and eyes; TavernInteractions calls it once it stands.
func attach(interactions: TavernInteractions) -> void:
	_interactions = interactions
	_player = interactions.player
	_camera = interactions.camera
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.offset_left = -300.0
	_label.offset_right = 300.0
	_label.offset_top = 22.0
	_label.offset_bottom = 52.0
	# A stall's price board or the order board is a long line: it wraps downwards.
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.grow_vertical = Control.GROW_DIRECTION_END
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LEVEL_HUD.style_label(_label)
	_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_label)
	_panel = BrewBookPanel.new()
	add_child(_panel)
	var linen := building.material("tav_linen")
	if linen != null:
		_arms.dress(linen)
	if building.sky_system != null:
		_last_hour = building.sky_system.time_of_day

func _input(event: InputEvent) -> void:
	if _panel != null and _panel.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var key: Key = event.physical_keycode
			if key == KEY_A or key == KEY_LEFT:
				_panel.turn(-1)
			elif key == KEY_D or key == KEY_RIGHT:
				_panel.turn(1)
			elif key == KEY_ESCAPE:
				interact_busy()
			else:
				return
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if station == null:
		_turn_wares(event)
		return
	if event is InputEventMouseMotion:
		_motion += event.relative
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var button: MouseButton = event.button_index
		if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
			station.next(day, 1 if button == MOUSE_BUTTON_WHEEL_DOWN else -1)
			_approach()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_tick_clock()
	if station != null:
		var work := station.work()
		var before := [station.gesture.count, station.gesture.amount, station.gesture.turns]
		var thrown := station.update(day, _motion, delta, _minutes)
		_sound_work(work, before, delta)
		if thrown:
			_throw_held()
		_motion = Vector2.ZERO
	_cellar_news()
	_pose_parts()
	_level_surfaces()
	_hold(delta)
	_place_hands(delta)
	_run_streams()
	_burn()
	_sound_running(delta)
	if _label != null:
		_said -= delta
		if _said <= 0.0:
			_label.text = _reading()

## Game minutes since the last frame go into the day and the cellar; the
## clock turned back (a debug key) gives none.
func _tick_clock() -> void:
	_minutes = 0.0
	if building == null or building.sky_system == null:
		return
	var hour := building.sky_system.time_of_day
	if _last_hour >= 0.0:
		_minutes = maxf(0.0, wrapf(hour - _last_hour, -12.0, 12.0)) * 60.0
		advance(_minutes, _last_hour)
	_last_hour = hour

## The night slept away goes by in the brewery too (ValleyLoop): the clock
## already stands at the morning.
func pass_hours(hours: float) -> void:
	if building == null or building.sky_system == null:
		advance(hours * 60.0, fposmod(DayClock.WAKE_HOUR - hours, 24.0))
		return
	var now: float = building.sky_system.time_of_day
	advance(hours * 60.0, fposmod(now - hours, 24.0))
	_last_hour = now

## `minutes` of game time from `hour` in the brewery and the cellar, an hour
## at a time; each dawn on the way is a day of fermentation and ageing.
func advance(minutes: float, hour: float) -> void:
	var left := minutes
	var at := hour
	while left > 0.0:
		var step := minf(left, 60.0)
		day.advance(step)
		cellar.advance(day, step, at)
		maltings.advance(step)
		for _dawn in DayClock.dawns_passed(at, step / 60.0):
			cellar.dawn()
			maltings.dawn()
			for keg: String in trade.dawn():
				if _utensils.has(keg):
					_home_keg(keg)
		at = fposmod(at + step / 60.0, 24.0)
		left -= step

# ---- What E does here (TavernInteractions) ----------------------------------

## A thing of the brewery E can be pointed at.
class Target:
	var kind := ""
	var id := ""
	## Where a thing put down lands (BrewCarry.place).
	var place := {}

## Whether the hand is busy here: a station worked or the book open.
func busy() -> bool:
	return station != null or (_panel != null and _panel.visible)

func busy_text() -> String:
	if _panel != null and _panel.visible:
		return "A / D — листать   ·   E — закрыть книгу"
	var work := station.work()
	var hint := {"tilt": "мышь от себя — наклонить", "circle": "мышь по кругу", "rock": "мышь вниз-вверх — качать",
		"draw": "мышь — тянуть", "stripe": "мышь полосами", "strike": "замах и удар", "throw": "замах вниз, бросок вверх"}
	var title := str(work.title)
	var text := "%s   ·   %s" % [title.left(1).to_upper() + title.substr(1), hint.get(work.gesture, "")]
	if station.works.size() > 1:
		text += "   ·   колесо — другое дело"
	return text + "   ·   E — отойти"

## E while busy: steps away from the station, shuts the book.
func interact_busy() -> void:
	if _panel != null and _panel.visible:
		_panel.visible = false
		_player.movement_locked = false
	elif station != null:
		_leave_station()

## What E would do nearest within `best` metres: {distance, target}; {} when
## nothing. Putting down what the hand holds comes last of all.
func find_target(best: float) -> Dictionary:
	if _interactions == null:
		return {}
	var trading := _trade_target(best)
	if not trading.is_empty() or not _near():
		return trading
	# Of what is in sight nearer than `best`, the thing the eye is most on:
	# in the cellar a tap, the funnel and a keg stand within a hand.
	var found := {}
	var score := INF
	var candidates: Array[Array] = []
	for id: String in _stations:
		var reads := id == "desk" and carry.held == ""
		if BrewStation.works_for(id, carry.held, cellar).is_empty() and not reads:
			continue
		# The look of a station may lie in a vessel, behind its rim: it is
		# looked at from where one stands to work it, through nothing.
		var stand := to_global(_vector(_stations[id].stand))
		if Vector2(stand.x - _player.global_position.x, stand.z - _player.global_position.z).length() > STAND:
			continue
		var look := to_global(_vector(_stations[id].look))
		candidates.append(["book" if reads else "station", id, look, _aimed(look)])
	if carry.held == "":
		for id: String in _utensils:
			if _hidden(id) or id == cellar.tap:
				continue
			candidates.append(["take", id, _grip(id), _interactions.target_distance(_grip(id), null, true)])
		var glass := _moving_point("hourglass")
		candidates.append(["hourglass", "hourglass", glass, _interactions.target_distance(glass, null, true)])
	for candidate: Array in candidates:
		var distance: float = candidate[3]
		if distance >= best:
			continue
		var point: Vector3 = candidate[2]
		var off := 1.0 - (-_camera.global_basis.z).dot((point - _camera.global_position).normalized())
		if distance * (1.0 + OFF_AIM * off) < score:
			score = distance * (1.0 + OFF_AIM * off)
			found = _target(str(candidate[0]), str(candidate[1]), distance)
	if carry.held != "" and found.is_empty():
		var place := _drop_place()
		if not place.is_empty():
			found = _target("put", carry.held, best - 0.001)
			(found.target as Target).place = place
	return found

func _target(kind: String, id: String, distance: float) -> Dictionary:
	var target := Target.new()
	target.kind = kind
	target.id = id
	return {"distance": distance, "target": target}

func target_text(target: Target) -> String:
	match target.kind:
		"station":
			var works := BrewStation.works_for(target.id, carry.held, cellar)
			return "E — %s · %s" % [str(works[0].title), _stations[target.id].title]
		"book":
			return "E — открыть книгу пивовара"
		"take":
			return "E — взять · %s" % _utensils[target.id].entry.title
		"hourglass":
			return "E — перевернуть песочные часы"
		"put":
			var where: String = " на стойку" if target.place.get("anchor", "") == "bar_keg" else ""
			return "E — поставить%s · %s" % [where, _utensils[carry.held].entry.title]
		"buy":
			var wares: Array = trade.stall(target.id).get("wares", [])
			var ware_id := _ware(target.id)
			var text := "E — купить: %s · %d медн. · в кошельке %d" % [str(trade.ware(ware_id).title), trade.price(ware_id),
				trade.coins]
			return text + ("   ·   колесо — другой товар" if wares.size() > 1 else "")
		"order":
			var index := trade.order_for(_held_beer(), book)
			if index < 0:
				return "Бочонок не подходит ни к одному заказу"
			var order: Dictionary = trade.orders[index]
			return "E — сдать бочонок по заказу · %s · %d медн." % [str(trade.template(str(order.id)).who),
				trade.order_pay(order)]
		"cart":
			return "E — погрузить бочонок на телегу · %d медн." % trade.cart_price(_held_beer(), book)
	return ""

func interact(target: Target) -> void:
	match target.kind:
		"station":
			_enter_station(target.id)
		"book":
			_panel.open(book.pages(_book_batch()))
			_player.movement_locked = true
		"take":
			_take(target.id)
		"hourglass":
			day.turn_hourglass()
		"put":
			_put(target.place)
		"buy":
			_buy(target.id)
		"order":
			var keg := carry.held
			var paid := trade.deliver(keg, _held_beer(), book)
			if paid > 0:
				_sold(keg, "Заказ сдан: %d медн. · в кошельке %d" % [paid, trade.coins])
			else:
				say("Бочонок не подходит ни к одному заказу")
		"cart":
			var keg := carry.held
			var paid := trade.load_cart(keg, _held_beer(), book)
			_sold(keg, "Бочонок на телеге: %d медн. · в кошельке %d" % [paid, trade.coins])

func holding() -> bool:
	return carry.held != ""

## Kg of what a carried thing holds: the brewing day's or the cellar's.
func load_kg(id: String) -> float:
	return day.load_kg(id) + cellar.load_kg(id) + maltings.load_kg(id)

## The batch the book's journal shows: the brewing day's, else the cellar's
## latest once the day has handed its wort over.
func _book_batch() -> BrewBatch:
	if day.batch.stage == "new" and cellar.latest_batch() != null:
		return cellar.latest_batch()
	return day.batch

# ---- The trade -----------------------------------------------------------------

## The trade's place the eye is on within `best` metres: a stall to buy at;
## with a full keg in the hand, the order board or the cart; {} when none.
func _trade_target(best: float) -> Dictionary:
	if stalls == null:
		return {}
	var found := {}
	for id: String in stalls.places:
		var place: Dictionary = stalls.places[id]
		var kind := str(TRADE_KINDS[place.kind])
		if kind != "buy" and not _keg_for_sale():
			continue
		for point: Vector3 in place.looks:
			var distance := _interactions.target_distance(point, null, true)
			if distance < best:
				best = distance
				found = _target(kind, id, distance)
	return found

## Whether the hand holds a full keg under its bung.
func _keg_for_sale() -> bool:
	if not cellar.kegs.has(carry.held):
		return false
	var keg: Dictionary = cellar.kegs[carry.held]
	return keg.bunged and float(keg.liters) >= SALE_L

## The beer of the keg in the hand.
func _held_beer() -> Dictionary:
	return cellar.kegs[carry.held].beer if cellar.kegs.has(carry.held) else {}

## The ware stall `id`'s board offers now.
func _ware(id: String) -> String:
	var wares: Array = trade.stall(id).get("wares", [])
	return str(wares[posmod(int(_wares.get(id, 0)), wares.size())]) if not wares.is_empty() else ""

## The mouse wheel at a stall: the next ware of its board.
func _turn_wares(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or _interactions == null:
		return
	var button: MouseButton = event.button_index
	if button != MOUSE_BUTTON_WHEEL_UP and button != MOUSE_BUTTON_WHEEL_DOWN:
		return
	var selected: Variant = _interactions.selected
	if not selected is Target or (selected as Target).kind != "buy":
		return
	var id := (selected as Target).id
	_wares[id] = int(_wares.get(id, 0)) + (1 if button == MOUSE_BUTTON_WHEEL_DOWN else -1)
	get_viewport().set_input_as_handled()

## The ware stall `id` offers bought: the coins left in its box.
func _buy(id: String) -> void:
	var ware_id := _ware(id)
	var refused := trade.buy(ware_id, day, cellar, maltings)
	if refused != "":
		say("%s: %s" % [str(REFUSALS[refused]), str(trade.ware(ware_id).title)])
		return
	say("Куплено: %s · в кошельке %d медн." % [str(trade.ware(ware_id).title), trade.coins])
	_save_soon()

## Keg `keg` in the hand went away with its beer: the hand is empty.
func _sold(keg: String, words: String) -> void:
	cellar.empty_keg(keg)
	carry.held = ""
	_home_keg(keg)
	_player.pace = 1.0
	if _player.viewmodel != null:
		_player.viewmodel.visible = true
	say(words)
	_save_soon()

## Whether utensil `id` is a keg the brewery does not have now: not bought
## yet, or away with the cart or an order.
func _hidden(id: String) -> bool:
	return BrewCellar.KEGS.has(id) and not trade.rack_kegs().has(id)

## What the eye reads off the trade's place looked at: a stall's price board,
## the order board's orders, the cart's terms; "" when none is looked at.
func _trade_reading() -> String:
	if stalls == null:
		return ""
	for id: String in stalls.places:
		var place: Dictionary = stalls.places[id]
		var looked := false
		for point: Vector3 in place.looks:
			looked = looked or _aimed(point) < INF
		if not looked:
			continue
		match str(place.kind):
			"stall":
				var prices := PackedStringArray()
				for ware_id: Variant in trade.stall(id).get("wares", []):
					prices.append("%s — %d" % [str(trade.ware(str(ware_id)).title), trade.price(str(ware_id))])
				return "%s: %s" % [str(place.title), "; ".join(prices)]
			"order_board":
				if trade.orders.is_empty():
					return "Доска заказов пуста"
				var lines := PackedStringArray()
				for order: Dictionary in trade.orders:
					lines.append(trade.order_words(order, book))
				return "Заказы · " + " · ".join(lines)
			"cart":
				return "Телега берёт бочонки за половину цены Борра, кислое пиво — на уксус"
	return ""

## The valley is saved soon: coins changed hands.
func _save_soon() -> void:
	if _interactions != null and _interactions.valley != null:
		_interactions.valley.save_soon()

# ---- Carrying -----------------------------------------------------------------

func _take(id: String) -> void:
	if not trade.has_log(id):
		say("Поленница пуста: вязанки продаёт лавка рынка")
		return
	carry.held = id
	if id == "hoist_bucket":
		day.hang_bucket(false)
	match BrewCarry.snaps_to(id):
		"keg":
			cellar.stand_keg(id, 0)
			cellar.take_tap(id)
		"funnel":
			cellar.funnel_on = ""
		"bucket":
			if id == "cellar_bucket":
				cellar.bucket_at = ""
	var node: Node3D = _utensils[id].node
	# A carried thing is the level's: out of the brewery the building may be
	# hidden as a whole (TavernPortals), and the thing with it.
	node.reparent(_level())
	_held_rest = _hold_frame().affine_inverse() * node.global_transform
	if id.begins_with("keg_"):
		# Its axis (its node's x, from the foot to the grip) across the view.
		_held_rest.basis = Basis.IDENTITY
	var grip := _grip_local(id)
	_held_rest.origin = _hold_offset(id) - _held_rest.basis * grip
	if _player.viewmodel != null:
		_player.viewmodel.visible = false

func _put(place: Dictionary) -> void:
	var id := carry.held
	var node: Node3D = _utensils[id].node
	var at: Vector3 = place.at
	var anchor := str(place.anchor)
	var facing := Basis(Vector3.UP, float(place.get("yaw", 0.0)))
	if anchor.begins_with("lager_") or anchor == "bar_keg":
		facing = facing * _keg_upright(id)
	if anchor == "" and _home(id).distance_to(at) > 0.001:
		var eye := to_local(_camera.global_position) - at
		facing = Basis(Vector3.UP, atan2(eye.x, eye.z))
	if anchor == "bar_keg":
		var refused := cellar.set_tap(id)
		if refused != "":
			say(str({"busy": "На стойке уже стоит бочонок", "not_ready": "Борр берёт только полный бочонок под пробкой",
				"ruined": "Борр нюхает и качает головой: это не пиво"}[refused]))
			return
		var paid := trade.sell_to_borr(cellar.kegs[id].beer, book)
		say("Борр берёт бочонок: %d медн. · в кошельке %d" % [paid, trade.coins])
		_save_soon()
		node.global_transform = _bar
	else:
		node.reparent(self)
		node.transform = Transform3D(facing, at)
	if anchor.begins_with("lager_"):
		cellar.stand_keg(id, int(anchor.get_slice("_", 1)))
	elif anchor.begins_with("funnel_"):
		cellar.funnel_on = anchor.trim_prefix("funnel_")
	elif id == "cellar_bucket":
		cellar.bucket_at = anchor
	if id == "hoist_bucket":
		match str(place.anchor):
			"lift_floor", "hop_back_bucket":
				day.hang_bucket(true, false)
			"lift_top":
				day.hang_bucket(true, true)
			_:
				if _home(id).distance_to(at) < 0.001:
					day.hang_bucket(true, false)
	carry.held = ""
	_player.pace = 1.0
	if _player.viewmodel != null:
		_player.viewmodel.visible = true

## Where the held thing would land: a place of its own on the line of sight
## before the face the eye meets (or within reach, with no face), else
## BrewCarry.place at that face.
func _drop_place() -> Dictionary:
	var from := _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - _camera.global_basis.z * REACH)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	var entry: Dictionary = _utensils[carry.held].entry
	var anchors := _all_anchors()
	var toward := global_basis.inverse() * -_camera.global_basis.z
	if hit.is_empty():
		return BrewCarry.on_ray(entry, to_local(from), toward, REACH, anchors)
	# A place of its own on the line of sight before the face it meets: a
	# keg's bung hole has no face of its own.
	var before := BrewCarry.on_ray(entry, to_local(from), toward, from.distance_to(hit.position), anchors)
	if not before.is_empty():
		return before
	var normal: Vector3 = hit.normal
	return BrewCarry.place(entry, to_local(hit.position), global_basis.inverse() * normal, anchors)

## The table's anchors and the cellar's own: a keg's place under each sound
## cask's tap, the bung hole of a keg standing there for the funnel, and the
## keg's place on the tavern's counter.
func _all_anchors() -> Array:
	var anchors: Array = (table.get("anchors", []) as Array).duplicate()
	for number in range(1, cellar.sound_casks + 1):
		var place := _keg_at_tap(number)
		var middle := _keg_aim(number)
		anchors.append({"id": "lager_%d_keg" % number, "kind": "keg", "at": [place.origin.x, place.origin.y, place.origin.z],
			"aim": [middle.x, middle.y, middle.z], "yaw": PI * 0.5})
		var keg := cellar.keg_under[number - 1]
		if keg != "":
			var bung := _bung(keg)
			anchors.append({"id": "funnel_" + keg, "kind": "funnel", "at": [bung.x, bung.y, bung.z]})
	if _find_bar():
		var spot := global_transform.affine_inverse() * _bar
		var top := to_local(_bar_top)
		anchors.append({"id": "bar_keg", "kind": "keg", "at": [spot.origin.x, spot.origin.y, spot.origin.z],
			"aim": [top.x, top.y, top.z], "yaw": spot.basis.get_euler().y})
	return anchors

## The level the brewery stands in: carried things and the counter's keg are its.
func _level() -> Node:
	return building.get_parent() if building != null and building.get_parent() != null else self

## The turn about its own length that lays a keg with its bung hole up; kegs
## lie on the rack with it to the side.
func _keg_upright(id: String) -> Basis:
	var bung := _bung_local(id)
	return Basis(Vector3.RIGHT, -atan2(bung.z, bung.y))

## The bung hole of keg `id` in its own frame: the oak plug of its model.
func _bung_local(id: String) -> Vector3:
	var node: Node3D = _utensils[id].node
	for item: MeshInstance3D in node.find_children("*oak_end*", "MeshInstance3D", true, false):
		var box := item.get_aabb()
		return node.global_transform.affine_inverse() * item.global_transform * box.get_center()
	return Vector3(0.25, KEG_RADIUS, 0.0)

## The bung hole of keg `id` where it stands, building frame.
func _bung(id: String) -> Vector3:
	var node: Node3D = _utensils[id].node
	return to_local(node.global_transform * _bung_local(id))

## Where a keg lies under the tap of cask `number`, building frame: its bung
## hole up under the nozzle, the keg across the tap on the floor. The kegs
## are one model.
func _keg_at_tap(number: int) -> Transform3D:
	var nozzle: Vector3 = _anchors["lager_tap_%d_nozzle" % number]
	var facing := Basis(Vector3.UP, PI * 0.5) * _keg_upright(BrewCellar.KEGS[0])
	var origin := nozzle + KEG_AT_TAP - facing * _bung_local(BrewCellar.KEGS[0])
	origin.y = KEG_RADIUS
	return Transform3D(facing, origin)

## Where the eye puts a keg under the tap of cask `number`, building frame:
## the floor under the keg's middle.
func _keg_aim(number: int) -> Vector3:
	var middle := _keg_at_tap(number) * Vector3(_bung_local(BrewCellar.KEGS[0]).x, 0.0, 0.0)
	return Vector3(middle.x, 0.0, middle.z)

## The keg's place on the tavern's counter, world space: BAR_KEG from the
## innkeeper's place at work, on the top a ray finds under it, the keg along
## the counter with its bung hole up. False while there is no innkeeper or no
## counter under the place.
func _find_bar() -> bool:
	if _bar_found or _interactions == null or _interactions.population == null:
		return _bar_found
	var keeper := _interactions.population.bartender
	if keeper == null:
		return false
	var turn := Basis(Vector3.UP, keeper.work_yaw)
	var over := keeper.work_point + turn * BAR_KEG
	var query := PhysicsRayQueryParameters3D.create(over + Vector3.UP * 0.4, over - Vector3.UP * 0.4)
	query.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var facing := turn * _keg_upright(BrewCellar.KEGS[0])
	var middle := facing * Vector3(_bung_local(BrewCellar.KEGS[0]).x, 0.0, 0.0)
	_bar_top = hit.position
	_bar = Transform3D(facing, _bar_top + Vector3.UP * KEG_RADIUS - middle)
	_bar_found = true
	return true

## The eye's frame turned with the look about the vertical, kept upright.
func _hold_frame() -> Transform3D:
	var ahead := -_camera.global_basis.z
	return Transform3D(Basis(Vector3.UP, atan2(-ahead.x, -ahead.z)), _camera.global_position)

func _hold_offset(id: String) -> Vector3:
	if id.begins_with("keg_"):
		return KEG_HOLD
	return HOLD.get(_utensils[id].entry.kind, HOLD.tool)

## The held thing before the eye, or at the station's work: tipped over where
## it pours, the paddle round the vessel.
func _hold(_delta: float) -> void:
	if _player == null:
		return
	_player.pace = BrewCarry.pace(BrewCarry.weight(_utensils[carry.held].entry, load_kg(carry.held))) if holding() else 1.0
	var bucket: Dictionary = _utensils.get("hoist_bucket", {})
	if not bucket.is_empty() and carry.held != "hoist_bucket" and day.hooked:
		var node: Node3D = bucket.node
		node.position = (_anchors.lift_floor as Vector3) + Vector3.UP * day.lift
	if not holding():
		return
	var node: Node3D = _utensils[carry.held].node
	var frame := _hold_frame()
	if station != null:
		var work := station.work()
		var over := _pour_over(str(work.id))
		if over.is_finite() and _sideways(carry.held):
			# Held to the right of where it pours and tipped over to the
			# left: what it pours into stays in sight.
			var rest := _held_rest
			rest.origin = rest.basis * -_grip_local(carry.held)
			var spot := to_global(over + Vector3.UP * SIDE_OVER) + frame.basis.x * _radius(carry.held)
			node.global_transform = Transform3D(Basis(frame.basis.z, station.gesture.amount * TIP) * frame.basis, spot) * rest
			return
		if over.is_finite():
			var mouth := over + Vector3.UP * 0.3
			var toward := (to_local(_camera.global_position) - mouth) * Vector3(1.0, 0.0, 1.0)
			var spot := to_global(mouth + toward.normalized() * maxf(0.25, toward.length() - HOLD_OUT))
			var tip := Basis(frame.basis.x, -station.gesture.amount * TIP)
			var rest := _held_rest
			rest.origin = rest.basis * -_grip_local(carry.held)
			node.global_transform = Transform3D(tip * frame.basis, spot) * rest
			return
		if work.gesture == "circle":
			var stir := _stir(str(work.id))
			var round := Vector3(cos(station.gesture.amount), 0.0, sin(station.gesture.amount))
			var foot: Vector3 = stir.centre + round * float(stir.reach) + Vector3.DOWN * 0.15
			var top: Vector3 = stir.top + round * STIR_HAND
			var entry: Dictionary = _utensils[carry.held].entry
			var shaft := _vector(entry.grip) - _vector(entry.at)
			var along := (top - foot).normalized()
			# A shaft longer than the way from the blade to the hands goes
			# deeper: the hands stay at the top.
			var grip := foot + along * shaft.length()
			if grip.y > top.y:
				foot -= along * (grip.y - top.y) / maxf(along.y, 0.1)
			node.global_transform = global_transform * Transform3D(Basis(Quaternion(shaft.normalized(), along)), foot)
			return
		node.global_transform = _swing(work, station.gesture, frame) * frame * _held_rest
		return
	node.global_transform = frame * _held_rest

## Where a paddle stirs at work `work_id`, building frame: {centre (the
## middle its blade goes round), reach (how far out), top (where the hands
## hold it, over the brim on the stand's side; through the hatch, for the
## copper), look (what the eye is on: the mash, the copper's hatch)}.
func _stir(work_id: String) -> Dictionary:
	var stand := _vector(_stations[station_id].stand)
	if work_id == "stir_copper":
		var hatch: Vector3 = _anchors.copper_hatch
		var centre := Vector3(hatch.x, _surface_height(BrewDay.COPPER), hatch.z + 0.3)
		var out := (stand - hatch) * Vector3(1.0, 0.0, 1.0)
		return {"centre": centre, "reach": 0.12, "top": hatch + out.normalized() * 0.15 + Vector3.UP * STIR_TOP * 0.9,
			"look": hatch}
	var brim: Vector3 = _anchors.mash_tun_brim
	var toward := (stand - brim) * Vector3(1.0, 0.0, 1.0)
	return {"centre": _surface_point(BrewDay.MASH_TUN), "reach": 0.25,
		"top": brim + toward.normalized() * (float(_brim_radius("mash_tun_brim")) - 0.05) + Vector3.UP * STIR_TOP,
		"look": _surface_point(BrewDay.MASH_TUN)}

## The level rectangle the table gives anchor `id` (a brim), x and z of the
## building frame; empty when none.
func _rim(id: String) -> Rect2:
	for entry: Dictionary in table.get("anchors", []):
		if entry.id == id and entry.has("rect"):
			var corners: Array = entry.rect
			return Rect2(Vector2(corners[0][0], corners[0][1]), Vector2.ZERO).expand(Vector2(corners[1][0], corners[1][1]))
	return Rect2()

## The radius the table gives anchor `id` (a brim), 0 when none.
func _brim_radius(id: String) -> float:
	for entry: Dictionary in table.get("anchors", []):
		if entry.id == id:
			return float(entry.get("radius", 0.0))
	return 0.0

## A held tool's swing at its work, a short clip the gesture drives: the
## mallet raised by the wind-up and brought down, a log or a handful drawn
## back and flung, the shovel pushed along its pass. World space.
func _swing(work: Dictionary, gesture: BrewGesture, frame: Transform3D) -> Transform3D:
	match str(work.gesture):
		"strike":
			var grip := frame * _hold_offset(carry.held)
			var lift := Basis(frame.basis.x, gesture.amount * STRIKE_LIFT)
			return Transform3D(lift, grip - lift * grip)
		"throw":
			return Transform3D(Basis.IDENTITY, (frame.basis.z * THROW_BACK + Vector3.DOWN * 0.1) * gesture.amount)
		"stripe":
			return Transform3D(Basis.IDENTITY, -frame.basis.z * gesture.pass_part() * STRIPE_REACH)
	return Transform3D.IDENTITY

## The hands on what they hold or turn (BrewHands), the arms bent to them
## (BrewArms). The arms stand in for the mug's hand while they show.
func _place_hands(delta: float) -> void:
	if _camera == null:
		return
	# Over a low work the body bows as it leans.
	var bow := BOW * _leaned.length() if _low else 0.0
	_player.rig.crouch = move_toward(_player.rig.crouch, minf(_crouch + bow, CROUCH), CROUCH_PACE * delta)
	# The body's own frame, without the lean: the lean is reckoned from it.
	var frame := Transform3D(_hold_frame().basis, _player.global_position + Vector3.UP * _player.rig.position.y)
	_arms.global_transform = frame
	_let_go = maxf(_let_go - delta, 0.0)
	var shoulders: Array[Vector3] = [_arms.shoulder(BrewHands.RIGHT), _arms.shoulder(BrewHands.LEFT)]
	var hands := _hands_now(frame, shoulders)
	var toward := _clear_lean(_lean(_far_round(hands), shoulders)) if station != null else Vector3.ZERO
	_leaned = _leaned.move_toward(toward, LEAN_PACE * delta)
	var lean := _player.global_basis.inverse() * _leaned
	_player.rig.position = Vector3(lean.x, _player.rig.position.y, lean.z)
	if station != null:
		_aim(_player.rig.global_position)
	_arms.global_transform = frame.translated(_leaned)
	if _let_go <= 0.0:
		_arms.reach(_in_reach(hands, [shoulders[0] + _leaned, shoulders[1] + _leaned]))
	_arms.pose(delta)
	if _arms.visible != _arms_shown and _player.viewmodel != null and not holding():
		_player.viewmodel.visible = not _arms.visible
	_arms_shown = _arms.visible

## How far the body leans (world space, level) to bring the shoulders within
## the arm's reach of the hand farthest out of it; LEAN at most.
func _lean(hands: Array[Dictionary], shoulders: Array[Vector3]) -> Vector3:
	var lean := Vector3.ZERO
	var reach := BrewArms.REACH - 0.02
	# Each hand in turn pulls the shoulders level towards its bar, a few
	# rounds, so that one lean serves both hands.
	for _round in 4:
		for hand: Dictionary in hands:
			var to := (hand.at as Transform3D).origin - shoulders[int(hand.side)] - lean
			var flat := to * Vector3(1.0, 0.0, 1.0)
			if to.length() <= reach or flat.length() < 0.01:
				continue
			# The level shift that leaves the bar just within the reach.
			var level := sqrt(maxf(reach * reach - to.y * to.y, 0.0))
			lean = (lean + flat.normalized() * (flat.length() - level)).limit_length(LEAN)
	return lean

## The hands on a crank where it goes farthest from the body: the body
## leans once for the whole round. Other hands as they are.
func _far_round(hands: Array[Dictionary]) -> Array[Dictionary]:
	var work := station.work()
	if not work.has("part") or not _moving.has(work.part) or str(_moving[work.part].kind) != "spin":
		return hands
	var pivot := to_global(_vector(_moving[work.part].pivot))
	var away := ((pivot - _player.global_position) * Vector3(1.0, 0.0, 1.0)).normalized()
	var far: Array[Dictionary] = []
	for hand: Dictionary in hands:
		var at: Transform3D = hand.at
		var round := (at.origin - pivot) * Vector3(1.0, 0.0, 1.0)
		var moved := hand.duplicate()
		moved.at = Transform3D(at.basis, pivot + away * round.length() + Vector3.UP * (at.origin.y - pivot.y))
		far.append(moved)
	return far

## As much of `lean` (world space) as the head has room for: it stops
## short of a wall or a vessel.
func _clear_lean(lean: Vector3) -> Vector3:
	# The eye stays back from what it looks at, the more the higher it is
	# over it: it does not look straight down.
	var eye := _player.rig.global_position - _leaned
	var back := (to_global(_look) - eye) * Vector3(1.0, 0.0, 1.0)
	if back.length() > 0.001:
		var along := lean.dot(back.normalized())
		var most := maxf(back.length() - SIGHT * clampf((eye.y - to_global(_look).y) / OVER, 0.0, 1.0), 0.0)
		if along > most:
			lean -= back.normalized() * (along - most)
	if lean.length() < 0.01:
		return lean
	var head := SphereShape3D.new()
	head.radius = HEAD
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = head
	query.transform = Transform3D(Basis.IDENTITY, eye)
	query.motion = lean
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	var free := _player.get_world_3d().direct_space_state.cast_motion(query)
	return lean * free[0]

## The hands within the arm's reach of their shoulders. A hand out of it is
## not shown on its bar; without the right one the arms do not show at all.
func _in_reach(hands: Array[Dictionary], shoulders: Array[Vector3]) -> Array[Dictionary]:
	var near: Array[Dictionary] = []
	for hand: Dictionary in hands:
		if (hand.at as Transform3D).origin.distance_to(shoulders[int(hand.side)]) <= BrewArms.REACH:
			near.append(hand)
	if not near.any(func(hand: Dictionary) -> bool: return int(hand.side) == BrewHands.RIGHT):
		near.clear()
	return near

## Where the hands go now: on the held thing (the left one under it while it
## is tipped), or on the part the station's work turns.
func _hands_now(frame: Transform3D, shoulders: Array[Vector3]) -> Array[Dictionary]:
	var right := frame.basis.x
	var hands: Array[Dictionary] = []
	if holding():
		var id := carry.held
		# A basket or a pot tipped sideways is held by the one hand.
		var tipping: bool = station != null and station.work().gesture == "tilt" and not _sideways(id)
		hands = BrewHands.on_utensil(id, _utensils[id].entry, (_utensils[id].node as Node3D).global_transform, shoulders,
			right, tipping, station != null)
	elif station != null and station.work().has("part") and building != null and building.machinery != null:
		var work := station.work()
		var pivot := building.machinery.pivot(str(work.part))
		if pivot != null and _moving.has(work.part):
			var part: Dictionary = _moving[work.part]
			var pull := str(part.group) + "_pull"
			if _anchors.has(pull):
				# Taken by its pull: the hand on the pull, whatever the part's pose.
				part = part.duplicate()
				part.grip = [_anchors[pull].x, _anchors[pull].y, _anchors[pull].z]
				hands = BrewHands.on_part(part, global_transform * Transform3D(Basis.IDENTITY, _vector(part.pivot)), shoulders,
					right)
			else:
				hands = BrewHands.on_part(part, pivot.global_transform, shoulders, right,
					work.gesture == "rock" or work.gesture == "circle")
	return hands

## A log thrown into the fire goes to the woodpile again: the pile has more.
func _throw_held() -> void:
	var id := carry.held
	if id == "":
		return
	var node: Node3D = _utensils[id].node
	node.reparent(self)
	carry.held = ""
	_arms.let_go()
	_let_go = LET_GO
	trade.burn_log(id)
	_player.pace = 1.0
	if _player.viewmodel != null:
		_player.viewmodel.visible = true
	var flight := create_tween()
	var mouth: Vector3 = _anchors.kiln_stoke if station_id == "kiln" else _anchors.copper_stoke
	flight.tween_property(node, "position", mouth + Vector3(0.0, 0.0, 0.3), 0.3)
	flight.tween_callback(func() -> void: node.transform = Transform3D(Basis.IDENTITY, _home(id)))
	_leave_station()

## Whether utensil `id` is tipped over sideways at a pour: a basket or a
## pot, held by its rim or its handle.
func _sideways(id: String) -> bool:
	return str(_utensils[id].entry.kind) == "raw"

## Half the widest of utensil `id` across, metres: its rim's radius.
func _radius(id: String) -> float:
	var entry: Dictionary = _utensils[id]
	if not entry.has("radius"):
		var node: Node3D = entry.node
		var whole := AABB()
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var box := node.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			whole = box if whole.size == Vector3.ZERO else whole.merge(box)
		entry.radius = maxf(whole.size.x, whole.size.z) * 0.5
	return float(entry.radius)

## Where the hand takes a utensil, world space.
func _grip(id: String) -> Vector3:
	var node: Node3D = _utensils[id].node
	return node.global_transform * _grip_local(id)

func _grip_local(id: String) -> Vector3:
	var entry: Dictionary = _utensils[id].entry
	return _vector(entry.grip) - _vector(entry.at)

func _home(id: String) -> Vector3:
	return _vector(_utensils[id].entry.at)

## A moving part's pivot, world space.
func _moving_point(id: String) -> Vector3:
	for entry: Dictionary in table.get("moving", []):
		if entry.id == id:
			return to_global(_vector(entry.pivot))
	return Vector3(INF, INF, INF)

# ---- Stations -------------------------------------------------------------------

func _enter_station(id: String) -> void:
	var mode := BrewStation.open(id, carry.held, day, cellar, maltings)
	if mode == null:
		return
	station = mode
	station_id = id
	_motion = Vector2.ZERO
	var entry: Dictionary = _stations[id]
	_player.movement_locked = true
	_player.velocity = Vector3.ZERO
	_approach()

## The body at the station's work: on its stand, or stepped up to the point
## the hands work at (as near as there is room) and crouched to a low one;
## the eye on that point, else on what the station looks at.
func _approach() -> void:
	var entry: Dictionary = _stations[station_id]
	var stand := _vector(entry.stand)
	var look := _vector(entry.look)
	var point := _work_reach()
	_crouch = 0.0
	_low = false
	if point.is_finite():
		stand = _stand_by(point, stand)
		if _flat_crank():
			stand = _aside(stand)
		_crouch = clampf(stand.y + Player.EYE_HEIGHT - point.y - OVER, -RISE, CROUCH)
		# A flat crank is turned standing: the head keeps over what hangs above it.
		_low = point.y < stand.y + Player.EYE_HEIGHT - _crouch - OVER * 0.5 and not _flat_crank()
		look = _work_look(point)
	_player.global_position = to_global(stand) + Vector3.UP * 0.02
	_look = look
	_aim(_player.global_position + Vector3.UP * (Player.EYE_HEIGHT - _crouch))

## Whether the station's work turns a crank round an upright axis (a quern).
func _flat_crank() -> bool:
	var work := station.work()
	if not work.has("part") or not _moving.has(work.part):
		return false
	var part: Dictionary = _moving[work.part]
	return str(part.kind) == "spin" and absf(_vector(part.axis).normalized().y) > 0.9

## The eye at `eye` (world) turned to what it is kept on at the work.
func _aim(eye: Vector3) -> void:
	var aim := to_global(_look) - eye
	_player.rig.yaw_deg = rad_to_deg(atan2(-aim.x, -aim.z))
	_player.rig.pitch_deg = rad_to_deg(asin(clampf(aim.normalized().y, -1.0, 1.0)))
	_player.rig.apply_look(Vector2.ZERO)

## What the eye is on at a work whose hands are at `point` (building
## frame): where a tipped thing pours, the inside of the vessel a paddle
## stirs, the middle a flat crank goes round, else the point.
func _work_look(point: Vector3) -> Vector3:
	var work := station.work()
	if _flat_crank():
		var pivot := _vector(_moving[work.part].pivot)
		return Vector3(pivot.x, point.y, pivot.z)
	var over := _pour_over(str(work.id))
	if over.is_finite():
		return over
	if work.gesture == "circle" and holding():
		return _stir(str(work.id)).look
	return point

## The point the right hand works at the station's work, building frame: the
## part it turns (by its pull, where it has one), over where a tipped thing
## pours, a paddle's top; INF for a work done before the eye.
func _work_reach() -> Vector3:
	var work := station.work()
	if work.has("part") and _moving.has(work.part):
		var pull := str(_groups.get(work.part, "")) + "_pull"
		return _anchors[pull] if _anchors.has(pull) else _vector(_moving[work.part].grip)
	var over := _pour_over(str(work.id))
	if over.is_finite():
		var stand := _vector(_stations[station_id].stand)
		var toward := (stand - over) * Vector3(1.0, 0.0, 1.0)
		return over + Vector3.UP * 0.3 + toward.normalized() * 0.25
	if work.gesture == "circle" and holding():
		return _stir(str(work.id)).top
	return Vector3.INF

## The nearest spot (building frame) to `point` where the body has room,
## a floor under it and a clear sight of the point: at each distance, first
## on the way back to `stand`, then on the bearings round the point farther
## and farther from that way. `stand` when no spot short of it serves.
func _stand_by(point: Vector3, stand: Vector3) -> Vector3:
	var away := (stand - point) * Vector3(1.0, 0.0, 1.0)
	var step := ARM_STAND
	while step < away.length():
		for turn in BEARINGS:
			var angle := TAU / BEARINGS * ceili(turn / 2.0) * (1.0 if turn % 2 == 1 else -1.0)
			var spot := Vector3(point.x, stand.y, point.z) + away.normalized().rotated(Vector3.UP, angle) * step
			spot.y = _ground(spot)
			if not is_nan(spot.y) and _room(spot) and _sees(spot, point):
				return spot
		step += ROOM_STEP
	return stand

## The body at a flat crank stands to the left of the middle it goes
## round, its right shoulder before it: the head bows past what hangs over
## the crank. `stand` when there is no room there.
func _aside(stand: Vector3) -> Vector3:
	var pivot := _vector(_moving[station.work().part].pivot)
	var toward := ((pivot - stand) * Vector3(1.0, 0.0, 1.0)).normalized()
	var spot := stand + toward.cross(Vector3.UP) * -FLAT_CRANK_ASIDE
	spot.y = _ground(spot)
	return spot if not is_nan(spot.y) and _room(spot) else stand

## The floor under `spot` (building frame) the body can step onto: a step
## or a stand up to STEP_UP over it, else `spot`'s own height; NAN with
## nothing under it.
func _ground(spot: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(to_global(spot + Vector3.UP * STEP_UP),
		to_global(spot + Vector3.DOWN * 0.05), _player.collision_mask, [_player.get_rid()])
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return to_local(hit.position).y if (hit.normal as Vector3).y > 0.7 else spot.y

## Whether the eye of the body standing at `spot` sees `point` (building
## frame), with no wall or vessel between. The ray goes from the point: a
## part inside its vessel's collider does not hide itself.
func _sees(spot: Vector3, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(to_global(point), to_global(spot + Vector3.UP * Player.EYE_HEIGHT),
		_player.collision_mask, [_player.get_rid()])
	return _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## Whether the body has room standing at `spot` (building frame).
func _room(spot: Vector3) -> bool:
	var body := _player.get_node("Collision") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body.shape
	query.transform = Transform3D(Basis.IDENTITY, to_global(spot) + body.position + Vector3.UP * 0.05)
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Steps away from the station: the body back on the station's stand, as
## entering put it there, straight again.
func _leave_station() -> void:
	_player.global_position = to_global(_vector(_stations[station_id].stand)) + Vector3.UP * 0.02
	_leaned = Vector3.ZERO
	_player.rig.position = Vector3(0.0, _player.rig.position.y, 0.0)
	station = null
	station_id = ""
	_crouch = 0.0
	_player.movement_locked = false

## The taps, cocks, damper and hatch as the day has them; the work's part as
## the hand holds it; the windlass at the bucket's height; the hourglass.
func _pose_parts() -> void:
	if building == null or building.machinery == null:
		return
	for work_id: String in BrewStation.CONTROLS:
		_set_pose(_part_of(work_id), float(day.controls[work_id]))
	for control: String in BrewCellar.CONTROLS:
		_set_pose(str(BrewCellar.PARTS[control]), float(cellar.controls[control]))
	for control: String in BrewMaltings.CONTROLS:
		_set_pose(str(BrewMaltings.PARTS[control]), float(maltings.controls[control]))
	_set_pose("quern_runner", maltings.quern_angle)
	_set_pose("windlass", day.lift / BrewDay.LIFT_TURN * TAU)
	_set_pose("hourglass", 1.0 if day.hourglass_up else 0.0)
	if station != null and station.work().has("part") and (station.work().gesture == "rock" or station.work().id == "taste"):
		_set_pose(str(station.work().part), station.pose(day))

func _part_of(work_id: String) -> String:
	for works: Array in BrewStation.WORKS.values():
		for work: Dictionary in works:
			if work.id == work_id:
				return str(work.get("part", ""))
	return ""

func _set_pose(part: String, amount: float) -> void:
	var group := str(_groups.get(part, ""))
	if group == "" or is_equal_approx(float(_posed.get(group, NAN)), amount):
		return
	_posed[group] = amount
	building.machinery.set_pose(group, amount)

# ---- What the cellar did --------------------------------------------------------

## The taste a cask gave goes into the mug; a keg the counter emptied goes
## back to the rack; the keg of a save is set on the counter once it stands.
func _cellar_news() -> void:
	var taste := cellar.take_taste()
	if not taste.is_empty() and _player != null:
		if _player.viewmodel != null:
			_player.viewmodel.refill(taste)
		say(taste_words(taste, book))
	var back := cellar.take_emptied()
	if back != "" and _utensils.has(back):
		_home_keg(back)
	for id: String in BrewCellar.KEGS:
		if _utensils.has(id):
			(_utensils[id].node as Node3D).visible = not _hidden(id)
	if _seat_tap and cellar.tap != "" and _find_bar():
		_seat_tap = false
		var node: Node3D = _utensils[cellar.tap].node
		node.reparent(_level())
		node.global_transform = _bar

## What a taste says by the crosshair: green while the cask ages, else the
## beer the book names and its flaws.
static func taste_words(taste: Dictionary, brew_book: BrewBook) -> String:
	var flaws: Array = taste.get("flaws", [])
	if flaws.has("green"):
		return "Зелёное и резкое: бочке стоять ещё %d дн." % int(taste.get("days_left", 0))
	var words: String = "%s, %.1f %%" % [str(brew_book.name_beer(taste).get("name", "")), float(taste.get("strength", 0.0))]
	var names := PackedStringArray()
	for id: Variant in flaws:
		names.append(str(brew_book.flaws.get(id, {}).get("name", id)))
	if not names.is_empty():
		words += " · " + ", ".join(names)
	return words

func _home_keg(id: String) -> void:
	var node: Node3D = _utensils[id].node
	node.reparent(self)
	node.transform = Transform3D(Basis.IDENTITY, _home(id))

## A mug drawn from the keg on the tavern's counter: the beer's profile, {}
## for the old beer when no keg stands there or the world has no brewery.
static func draw_beer(tree: SceneTree) -> Dictionary:
	var house := tree.get_first_node_in_group(GROUP) as BrewHouse
	return house.cellar.pour_mug() if house != null else {}

# ---- The look of the day ---------------------------------------------------------

## Each vessel's surface at its level, of the colour of what it holds.
func _level_surfaces() -> void:
	for id: String in _surfaces:
		var surface: Dictionary = _surfaces[id]
		var node: Node3D = surface.node
		if TUN_SURFACES.has(id):
			_level_tun(id, surface)
			continue
		if MALT_SURFACES.has(id):
			_level_malt(id, surface)
			continue
		if SPRING_SURFACES.has(id):
			continue
		var held := day.contents(id)
		node.visible = held != ""
		if held == "":
			continue
		node.position.y = _surface_height(id) - float(surface.built)
		var material: ShaderMaterial = surface.material
		var boil := 0.0
		var foam := 0.0
		if id == BrewDay.COPPER:
			boil = _boil()
			if held == "wort" and boil > 0.5:
				foam = 0.85 if day.batch.boil_minutes < BrewBatch.FOAM_MINUTES else 0.3
		elif held == "wort":
			foam = 0.15
		material.set_shader_parameter("tint", _tint(id, held))
		material.set_shader_parameter("boil", boil)
		material.set_shader_parameter("foam", foam)
		material.set_shader_parameter("thick", 1.0 if held == "mash" or held == "grain" else 0.0)
	for key: String in _steam:
		var plume: CPUParticles3D = _steam[key]
		if key == "kiln":
			# Drying malt breathes out of the kiln's cowl.
			plume.emitting = maltings.kiln != null and maltings.kiln.stage == "green" and maltings.kiln.moisture > MaltLot.DAMP \
				and maltings.kiln_temp > MaltLot.WARM
			continue
		var hot := 0.0
		match key:
			"copper":
				hot = (day.temperature(BrewDay.COPPER) - 60.0) / 40.0 * float(day.controls.hatch)
			"cupola":
				hot = (day.temperature(BrewDay.COPPER) - 95.0) / 5.0
			"mash":
				hot = (day.temperature(BrewDay.MASH_TUN) - 45.0) / 30.0
			"hop_back":
				hot = (day.temperature(BrewDay.HOP_BACK) - 50.0) / 40.0
			"coolship":
				hot = (day.temperature(BrewDay.COOLSHIP) - 35.0) / 50.0
		var vessel := str({"mash": BrewDay.MASH_TUN, "hop_back": BrewDay.HOP_BACK, "coolship": BrewDay.COOLSHIP}.get(key, BrewDay.COPPER))
		plume.emitting = hot > 0.0 and day.contents(vessel) != ""
		plume.speed_scale = clampf(0.5 + hot, 0.5, 1.5)

## The maltings' grain: the tub's at the level of its grain and water, a heap
## as large as its kg; tinted by how far the grain has come.
func _level_malt(id: String, surface: Dictionary) -> void:
	var node: Node3D = surface.node
	var lot: MaltLot = {"steep_grain": maltings.steep, "couch_malt": maltings.couch, "kiln_malt": maltings.kiln}[id]
	var water := maltings.steep_water_l if id == "steep_grain" else 0.0
	node.visible = lot != null or water > 0.5
	if not node.visible:
		return
	var material: ShaderMaterial = surface.material
	var entry: Dictionary = surface.entry
	if entry.has("heap"):
		var size := clampf(lot.kg / float(HEAP_KG[id]), 0.15, 1.2)
		node.scale = Vector3(sqrt(size), size, sqrt(size))
	else:
		var bulk := (lot.kg * BrewDay.GRAIN_BULK if lot != null else 0.0) + water
		var full := float(day.capacity.get(id, 0.0))
		var fill := clampf(bulk / full, 0.0, 1.0) if full > 0.0 else 0.0
		node.position.y = lerpf(float(entry.bottom), float(entry.brim), fill) - float(surface.built)
	var wet := water > 0.5 or (lot != null and (lot.stage == "steeped" or (lot.stage == "green" and lot.moisture > MaltLot.WET)))
	var tint := DEEP_WATER if lot == null else malt_tint(lot)
	material.set_shader_parameter("tint", tint.darkened(WET_DARK) if wet and lot != null else tint)
	material.set_shader_parameter("boil", 0.0)
	material.set_shader_parameter("foam", 0.0)
	material.set_shader_parameter("thick", 1.0 if lot != null else 0.0)

## The colour of a lot of grain: barley straw-gold, green malt duller, kilned
## malt as dark as its colour, the kiln's darkening as it roasts.
static func malt_tint(lot: MaltLot) -> Color:
	var base := GREEN_MALT if lot.stage == "steeped" or lot.stage == "green" else GRAIN
	var dark := clampf(log(maxf(lot.color, 4.0) / 4.0) / log(150.0), 0.0, 0.9)
	if lot.stage == "green":
		dark = maxf(dark, clampf(lot.roast_minutes / 120.0, 0.0, 0.7))
		if lot.stew_minutes >= MaltLot.STEW_MINUTES:
			dark = maxf(dark, 0.3)
		if lot.peak_heat > MaltLot.BURN_HEAT:
			dark = 0.9
	return base.darkened(dark)

## A fermenting tun's beer at its level, its head of yeast over it while one
## stands to be skimmed.
func _level_tun(id: String, surface: Dictionary) -> void:
	var node: Node3D = surface.node
	var foam := id.ends_with("_foam")
	var number := int(id.get_slice("_", 2))
	node.visible = cellar.tun_l(number) > 0.5 and (not foam or cellar.head(number))
	if not node.visible:
		return
	var wort := "fermenting_tun_%d_wort" % number
	node.position.y = _surface_height(wort) - float(_surfaces[wort].built) + (0.03 if foam else 0.0)
	var material: ShaderMaterial = surface.material
	var batch := cellar.tun_batch(number)
	var working := batch.stage == "pitched" and batch.ferment_days >= 1 and batch.ferment < 1.0
	material.set_shader_parameter("tint", YEAST if foam else wort_color(_batch_ebc(batch), VESSEL_DEPTH))
	material.set_shader_parameter("boil", 0.0)
	material.set_shader_parameter("foam", 1.0 if foam else (0.35 if working else 0.15))
	material.set_shader_parameter("thick", 1.0 if foam else 0.0)

func _surface_height(id: String) -> float:
	var entry: Dictionary = _surfaces[id].entry
	return lerpf(float(entry.bottom), float(entry.brim), _fill(id))

## How full a vessel is, 0..1: the brewing day's, or a fermenting tun.
func _fill(id: String) -> float:
	if not TUN_SURFACES.has(id):
		return day.fill(id)
	var full := float(day.capacity.get(id, 0.0))
	var liters := cellar.tun_l(int(id.get_slice("_", 2)))
	return clampf(liters / full, 0.0, 1.0) if full > 0.0 else 0.0

## EBC of a batch's wort or beer.
static func _batch_ebc(batch: BrewBatch) -> float:
	return 300.0 * (1.0 - exp(-batch.color_points / maxf(batch.volume_l, 1.0) * 7.0 / 300.0))

## The middle of a vessel's surface at its level, building frame.
func _surface_point(id: String) -> Vector3:
	for entry: Dictionary in table.get("surfaces", []):
		if entry.id == id:
			var at := _vector(entry.at)
			if day != null and _surfaces.has(id):
				at.y = _surface_height(id)
			return at
	return Vector3.ZERO

## The colour of what a vessel holds.
func _tint(id: String, held: String) -> Color:
	match held:
		"water":
			return DEEP_WATER
		"mash", "grain":
			return MASH.darkened(clampf(_ebc(id) / 120.0, 0.0, 0.6) + (0.25 if held == "grain" else 0.0))
	return wort_color(_ebc(id), VESSEL_DEPTH)

## EBC of the wort or mash in a vessel now.
func _ebc(id: String) -> float:
	var liters := day.batch.volume_l if day.batch.volume_l > 0.0 else maxf(day.liters(id), day.batch.mash_l)
	return 300.0 * (1.0 - exp(-day.batch.color_points / maxf(liters, 1.0) * 7.0 / 300.0))

## The colour wort of `ebc` shows: light through `depth` hands of it, the
## red going through farthest. A vessel shows more depth than a stream, and
## its body sends back less light than a thin jet lit through. Pale wort
## (8 EBC) is gold in a vessel; dark goes red-brown, then near black.
static func wort_color(ebc: float, depth := 1.0) -> Color:
	var through := Vector3(exp(-ebc * 0.003 * depth), exp(-ebc * 0.008 * depth), exp(-ebc * 0.035 * depth))
	var body := 1.0 if depth <= 1.0 else 0.9
	return Color(0.68 * through.x * body, 0.54 * through.y * body, 0.22 * through.z * body)

## The streams that run now.
func _run_streams() -> void:
	for key: String in _streams:
		(_streams[key] as BrewStream).stop()
	for control: String in TAPS:
		var open := float(day.controls[control])
		var source := BrewDay.HOP_BACK if control == "hop_back_tap" else BrewDay.MASH_TUN if control == "mash_tap" else BrewDay.COPPER
		var runs := day.liters(source) > 0.01
		match control:
			"liquor_cock":
				runs = day.contents(BrewDay.COPPER) == "water"
			"mash_tap":
				runs = day.free_wort() > 0.0
		if open <= 0.0 or not runs:
			continue
		var from: Vector3 = _anchors[TAPS[control][0]]
		var into: String = TAPS[control][1]
		var to := _surface_point(into) if into != "" else _floor_under(control, from)
		var colour := WATER if control == "liquor_cock" else wort_color(_ebc(source))
		(_streams[control] as BrewStream).pour(to_global(from), to_global(Vector3(from.x, to.y, from.z)), open, 0.035,
			Color(colour, 0.85))
	_run_cellar_streams()
	var plug := float(maltings.controls.steep_plug)
	if plug > 0.0 and maltings.steep_water_l > 0.01:
		var drain: Vector3 = _anchors.steep_drain
		var under := _floor_under("steep_drain", drain)
		(_streams.steep_drain as BrewStream).pour(to_global(drain), to_global(Vector3(drain.x, under.y, drain.z)), plug, 0.03,
			Color(WATER, 0.85))
	if station == null:
		return
	var work := station.work()
	var land := _pour_landing(str(work.id))
	if land.is_finite() and station.gesture.flow() > 0.0:
		var node: Node3D = _utensils[carry.held].node
		var mouth := node.global_transform * (_grip_local(carry.held) * 1.05)
		if _sideways(carry.held):
			mouth = _grip(carry.held) - _hold_frame().basis.x * _radius(carry.held)
		var grain: bool = GRAIN_POURS.has(work.id) or work.id == "weigh_hops"
		var colour := GRAIN if GRAIN_POURS.has(work.id) else HOPS if work.id == "weigh_hops" else WATER
		if work.id == "pour_honey":
			colour = HONEY
		elif work.id == "cherry_cask":
			colour = CHERRY
		match str(work.id):
			"pour_coolship":
				colour = wort_color(_ebc(BrewDay.COOLSHIP))
			"pitch":
				colour = YEAST
			"fill_cask":
				colour = wort_color(_batch_ebc(cellar.bucket_batch)) if cellar.bucket_batch != null else WATER
		var landing := to_global(land)
		landing.x = mouth.x
		landing.z = mouth.z
		(_streams.grain as BrewStream).pour(mouth, landing, station.gesture.flow(), 0.14 if grain else 0.06, Color(colour, 0.9), grain)
	elif work.gesture == "rock" and station.gesture.amount > 0.5:
		var outlet: Vector3 = _anchors["liquor_pipe_outlet" if work.id == "pump_liquor" else "wort_pump_outlet"]
		if work.id == "pump_liquor" and float(day.controls.pipe_cock) < 0.5:
			outlet = _anchors.liquor_spout
		var to := Vector3(outlet.x, _surface_height(BrewDay.COPPER) if day.contents(BrewDay.COPPER) != "" else 1.2, outlet.z)
		if outlet == _anchors.liquor_spout:
			to.y = 0.5
		(_streams.liquor_pipe as BrewStream).pour(to_global(outlet), to_global(to), station.gesture.amount, 0.04, Color(WATER, 0.8))

## Where a tipped thing is held over at work `work_id`, building frame; not
## finite for a work that tips nothing.
func _pour_over(work_id: String) -> Vector3:
	if POURS.has(work_id):
		return _anchors[POURS[work_id][0]]
	match work_id:
		"pitch":
			return _anchors["fermenting_tun_%d_brim" % station.number]
		"dip_yeast":
			return _home("yeast_crock") + Vector3.UP * 0.3
		"scoop":
			return _anchors.copper_hatch
		"fill_cask", "scald", "cherry_cask":
			return _cask_mouth(station.number)
	return Vector3.INF

## Where what a tipped thing pours lands, building frame; not finite for a
## work whose pour shows no stream (a bucket or a dipper filled).
func _pour_landing(work_id: String) -> Vector3:
	if work_id == "fill_bucket" or work_id == "dip_yeast" or work_id == "scoop":
		return Vector3.INF
	if POURS.has(work_id):
		var into: String = POURS[work_id][1]
		return _surface_point(into) if into != "" else _anchors[POURS[work_id][0]] - Vector3.UP * 0.2
	match work_id:
		"pitch":
			return _surface_point("fermenting_tun_1_wort") if station.number == 1 else _anchors.fermenting_tun_2_bottom
		"fill_cask", "scald", "cherry_cask":
			return _cask_mouth(station.number) - Vector3.UP * 0.1
	return Vector3.INF

## Where a lager cask is filled: over the upper rim of its head.
func _cask_mouth(number: int) -> Vector3:
	return (_anchors["lager_tap_%d_nozzle" % number] as Vector3) + CASK_MOUTH

## The cellar's taps: the plate's wort down the spout into a tun, a tun's
## tap into the bucket under it, a cask's tap into the keg under it; else
## onto the floor.
func _run_cellar_streams() -> void:
	if float(cellar.controls.coolship_gate) > 0.0 and day.coolship_l > 0.01:
		var tun := cellar.spout_tun()
		var nozzle: Vector3 = _anchors["spout_nozzle_%d" % tun]
		var into := _surface_point("fermenting_tun_%d_wort" % tun) if cellar.tun_l(tun) > 0.5 \
			else (_anchors["fermenting_tun_%d_bottom" % tun] as Vector3)
		_pour_stream("spout", nozzle, into.y, float(cellar.controls.coolship_gate), wort_color(_ebc(BrewDay.COOLSHIP)))
	for number in range(1, BrewCellar.TUNS + 1):
		var tap := float(cellar.controls["fermenter_tap_%d" % number])
		if tap <= 0.0 or cellar.tun_l(number) <= 0.01:
			continue
		var nozzle: Vector3 = _anchors["fermenter_tap_%d_nozzle" % number]
		var bottom := 0.0
		var under := "fermenter_%d_bucket" % number
		if cellar.bucket_at == under:
			bottom = (_anchors[under] as Vector3).y + 0.05 + 0.45 * cellar.bucket_l / BrewCellar.BUCKET_L
		_pour_stream("fermenter_tap_%d" % number, nozzle, bottom, tap, wort_color(_batch_ebc(cellar.tun_batch(number))))
	for number in range(1, BrewCellar.CASKS + 1):
		var cask: Dictionary = cellar.casks[number - 1]
		var open := float(cellar.controls["lager_tap_%d" % number])
		if station != null and station.number == number and station.work().id == "taste":
			open = station.gesture.amount
		if open <= 0.0 or float(cask.liters) <= 0.01:
			continue
		var nozzle: Vector3 = _anchors["lager_tap_%d_nozzle" % number]
		var keg := cellar.keg_under[number - 1]
		var bottom := _bung(keg).y if keg != "" else 0.0
		_pour_stream("lager_tap_%d" % number, nozzle, bottom, open, wort_color(_batch_ebc(cask.batch)))

## A stream from `from` (building frame) straight down to the height `to_y`;
## a lip above the nozzle takes it at the nozzle's foot.
func _pour_stream(key: String, from: Vector3, to_y: float, open: float, colour: Color) -> void:
	var to := Vector3(from.x, minf(to_y, from.y - 0.05), from.z)
	(_streams[key] as BrewStream).pour(to_global(from), to_global(to), open, 0.03, Color(colour, 0.85))

## Where a tap with no vessel of its own pours: into the hoist bucket under it, or onto the floor.
func _floor_under(control: String, from: Vector3) -> Vector3:
	if control == "hop_back_tap" and day.hooked and day.lift <= 0.01:
		return Vector3(from.x, _vector(_utensils.hoist_bucket.entry.at).y + 0.35, from.z)
	return Vector3(from.x, 0.0, from.z)

## How hard the copper boils, 0..1.
func _boil() -> float:
	if day.contents(BrewDay.COPPER) == "":
		return 0.0
	return clampf((day.temperature(BrewDay.COPPER) - 85.0) / 15.0, 0.0, 1.0) * clampf(0.3 + day.fire, 0.0, 1.0)

# ---- Sounds ---------------------------------------------------------------------

## The sounds the hand's work made this frame (BrewSounds): a stroke, a blow,
## a pass, a throw; a tap leaving its end, the hatch or a damper at one; the
## loop of a turning work or of a tipped thing that pours where no stream
## shows (a bucket filled). `before`: the gesture's count, amount and turns
## before the frame.
func _sound_work(work: Dictionary, before: Array, delta: float) -> void:
	var gesture := station.gesture
	var at := _work_point(work)
	var shot := BrewSounds.shot_of(str(work.id))
	if shot != "" and gesture.count > int(before[0]):
		var loud := maxf(gesture.force, 0.4) if gesture.kind == "strike" or gesture.kind == "throw" else 1.0
		if shot == "log":
			at = to_global(_anchors.kiln_stoke if station_id == "kiln" else _anchors.copper_stoke)
		_sounds.play(shot, at, loud)
	if work.gesture == "draw" and work.has("part"):
		var sound := BrewSounds.draw_sound(str(work.id), float(before[1]), gesture.amount)
		if sound != "":
			_sounds.play(sound, at)
	var loop := BrewSounds.loop_of(work)
	if loop == "":
		return
	var amount := absf(gesture.turns - float(before[2])) / maxf(delta, 0.001) / BrewSounds.FULL_TURNS
	if work.gesture == "tilt":
		if _pour_landing(str(work.id)).is_finite():
			return
		amount = gesture.flow()
	_sounds.hum("work", loop, at, amount)

## Where a work is heard: the part it turns, the thing in the hand, else what
## the station looks at. World space.
func _work_point(work: Dictionary) -> Vector3:
	if work.has("part") and _moving.has(work.part):
		return _moving_point(str(work.part))
	if holding():
		return (_utensils[carry.held].node as Node3D).global_position
	return to_global(_vector(_stations[station_id].look))

## The sounds of what runs on its own: each stream, the boil, the fires.
func _sound_running(delta: float) -> void:
	for key: String in _streams:
		var stream: BrewStream = _streams[key]
		if stream.flow > 0.0:
			_sounds.hum(key, "grain" if stream.grain else "pour", stream.from_point, stream.flow)
	_sounds.hum("boil", "boil", to_global(_anchors.copper_hatch), _boil())
	_sounds.hum("copper_fire", "fire", to_global(_anchors.copper_stoke), day.fire)
	_sounds.hum("kiln_fire", "fire", to_global(_anchors.kiln_stoke), maltings.fire())
	_sounds.settle(delta)

## The fire under the copper: its flames and its lamp.
func _burn() -> void:
	_fire.visible = day.fire > BrewDay.FIRE_OUT
	_fire.scale = Vector3.ONE * (0.4 + 0.8 * day.fire)
	_kiln_fire.visible = maltings.fire() > 0.02
	_kiln_fire.scale = Vector3.ONE * (0.4 + 0.8 * maltings.fire())
	if building != null:
		building.stoke("Copper firebox", clampf(day.fire * 1.4, 0.0, 1.4))
		building.stoke("Kiln fire", clampf(maltings.fire() * 1.4, 0.0, 1.4))

func _plume(at: Vector3, size: float) -> CPUParticles3D:
	var material := ShaderMaterial.new()
	material.shader = STEAM
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	var plume := CPUParticles3D.new()
	plume.position = at
	plume.mesh = quad
	plume.amount = 24
	plume.lifetime = 3.5
	plume.direction = Vector3.UP
	plume.spread = 12.0
	plume.initial_velocity_min = 0.2
	plume.initial_velocity_max = 0.45
	plume.gravity = Vector3(0.0, 0.08, 0.0)
	plume.damping_min = 0.05
	plume.damping_max = 0.1
	plume.angle_min = -180.0
	plume.angle_max = 180.0
	plume.angular_velocity_min = -20.0
	plume.angular_velocity_max = 20.0
	plume.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	plume.emission_sphere_radius = size * 0.3
	# Steam spreads as it rises and thins away.
	plume.scale_amount_min = 0.5
	plume.scale_amount_max = 0.8
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.0))
	plume.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.2, Color(1.0, 1.0, 1.0, 1.0))
	plume.color_ramp = fade
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.emitting = false
	add_child(plume)
	return plume

# ---- What an instrument shows ------------------------------------------------------

## The number of the instrument looked at, or of the vessel the held
## thermometer or dipstick is pointed into.
func _reading() -> String:
	if _camera == null or not _camera.current or (busy() and station == null):
		return ""
	var trade_text := _trade_reading()
	if trade_text != "" or not _near():
		return trade_text
	var malt_text := _malt_reading()
	if malt_text != "":
		return malt_text
	if carry.held == "thermometer" or carry.held == "dipstick":
		var best := REACH
		var found := ""
		for id: String in VESSELS + ["fermenting_tun_1_wort", "fermenting_tun_2_wort"]:
			var distance := _aimed(to_global(_surface_point(id)))
			if distance < best:
				best = distance
				found = id
		if found.begins_with("fermenting_tun_"):
			return _tun_reading(carry.held, int(found.get_slice("_", 2)))
		return day.reading(carry.held, found) if found != "" else ""
	var marks := {"hourglass": _moving_point("hourglass"), "balance": _moving_point("hop_balance_beam")}
	if carry.held != "thermometer" and _utensils.has("thermometer"):
		marks.thermometer = _grip("thermometer")
	if BrewDay.SACKS.has(carry.held) or BrewMaltings.SACKS.has(carry.held):
		marks.steelyard = _moving_point("steelyard")
	var best := REACH
	var shown := ""
	for mark: String in marks:
		var distance := _aimed(marks[mark])
		if distance < best:
			best = distance
			shown = mark
	var cellar_text := ""
	var cellar_marks := _cellar_marks()
	for point: Vector3 in cellar_marks:
		var distance := _aimed(point)
		if distance < best:
			best = distance
			cellar_text = str(cellar_marks[point])
	if cellar_text != "":
		return cellar_text
	if shown == "":
		return ""
	if shown == "steelyard" and BrewMaltings.SACKS.has(carry.held):
		return "Безмен: %.1f кг" % (maltings.load_kg(carry.held) + float(BrewCarry.WEIGHTS.sack))
	return day.reading(shown, carry.held if shown == "steelyard" else "")

## What the eye reads off the maltings looked at: the tub, the floor, the
## kiln, the quern ("" when none is looked at).
func _malt_reading() -> String:
	var best := REACH
	var shown := ""
	for place: String in ["steep", "floor", "kiln", "mill"]:
		var distance := _aimed(to_global(_vector(_stations[place].look)))
		if distance < best:
			best = distance
			shown = place
	return maltings.reading(shown, carry.held, day.fine_thermometer) if shown != "" else ""

## The thermometer or the dipstick in fermenting tun `number`.
func _tun_reading(instrument: String, number: int) -> String:
	var batch := cellar.tun_batch(number)
	if batch == null:
		return "Бродильный чан пуст"
	if instrument == "dipstick":
		return "Бродильный чан: %.0f л" % cellar.tun_l(number)
	var cooling := batch.stage == "cooled" or (batch.stage == "pitched" and batch.ferment_days == 0)
	return "Бродильный чан: %s" % BrewDay.degrees(batch.wort_temp if cooling else BrewCellar.TEMP, day.fine_thermometer)

## What the eye reads off the cellar's things looked at: world point -> words.
func _cellar_marks() -> Dictionary:
	var marks := {}
	for number in range(1, BrewCellar.TUNS + 1):
		marks[to_global(_vector(_stations["fermenter_%d" % number].look))] = _tun_words(number)
	for number in range(1, BrewCellar.CASKS + 1):
		marks[to_global(_vector(_stations["lager_%d" % number].look) + Vector3.UP * 0.35)] = _cask_words(number)
	for id: String in BrewCellar.KEGS:
		if id != carry.held and not _hidden(id):
			marks[_grip(id)] = _keg_words(id)
	marks[_grip("yeast_crock")] = "Горшок с дрожжами: %.1f л" % cellar.crock_l
	for id: String in BrewTrade.WOOD_CAP:
		if id != carry.held and _utensils.has(id):
			marks[_grip(id)] = "%s: %d шт." % ["Буковые поленья" if id == "beech_log" else "Еловые поленья", int(trade.wood[id])]
	return marks

func _tun_words(number: int) -> String:
	if not cellar.sound_tun(number):
		return "Бродильный чан рассохся: нужен бондарь"
	var batch := cellar.tun_batch(number)
	if batch == null:
		return "Бродильный чан пуст"
	var words := "Бродильный чан: %.0f л" % cellar.tun_l(number)
	match batch.stage:
		"cooled":
			return words + " сусла · ждёт дрожжей"
		"pitched":
			if batch.ferment_days == 0:
				return words + " · дрожжи в сусле"
			if batch.ferment >= 1.0:
				return words + " · брожение кончилось"
			return words + " · бродит, день %d%s" % [batch.ferment_days, " · шапка пены" if cellar.head(number) else ""]
	return words + " пива"

func _cask_words(number: int) -> String:
	if not cellar.sound_cask(number):
		return "Лагерная бочка рассохлась: нужен бондарь"
	var cask: Dictionary = cellar.casks[number - 1]
	var batch: BrewBatch = cask.batch
	if batch == null:
		return "Лагерная бочка пуста%s" % (" · ошпарена" if cellar.scalded(number) else "")
	return "Лагерная бочка: %.0f л · выдержка %d из %d дн. · %s" % [float(cask.liters), batch.age_days, batch.ready_days(),
		"под пробкой" if cask.bunged else "без пробки"]

func _keg_words(id: String) -> String:
	var keg: Dictionary = cellar.kegs[id]
	if float(keg.liters) < 0.5:
		return "Бочонок пуст"
	var words := "Бочонок: %.0f л · %s" % [float(keg.liters), str(book.name_beer(keg.beer).get("name", ""))]
	return words + (" · под пробкой" if keg.bunged else "")

## Whether the player is about the brewery at all, carrying something or not.
func _near() -> bool:
	return holding() or _player.global_position.distance_to(global_position) < NEAR

## How far a point is when the eye is on it, INF when it is not.
func _aimed(point: Vector3) -> float:
	var offset := point - _camera.global_position
	var distance := offset.length()
	if distance > REACH or distance < 0.01 or (-_camera.global_basis.z).dot(offset / distance) < AIM:
		return INF
	return distance

## A word by the crosshair for a while.
func say(text: String) -> void:
	if _label != null:
		_label.text = text
		_said = SAY_SECONDS

# ---- Save ---------------------------------------------------------------------------

## The brewery as plain data for ValleyLoop's save: the day, and where each
## utensil stands that is not at home ([x, y, z, yaw] in the building's frame).
func to_dict() -> Dictionary:
	var places := {}
	for id: String in _utensils:
		var node: Node3D = _utensils[id].node
		if node.get_parent() != self:
			continue
		if id != carry.held and node.position.distance_to(_home(id)) > 0.001 and not (id == "hoist_bucket" and day.hooked):
			places[id] = [node.position.x, node.position.y, node.position.z, node.rotation.y]
	return {"day": day.to_dict(), "utensils": places, "cellar": cellar.to_dict(day.batch), "maltings": maltings.to_dict(),
		"trade": trade.to_dict()}

## Reads back to_dict(); what is wrong in it is left as it stands.
func restore(data: Dictionary) -> void:
	var saved: Variant = data.get("day")
	if saved is Dictionary:
		day = BrewDay.from_dict(saved, day.capacity)
	var cellar_saved: Variant = data.get("cellar")
	if cellar_saved is Dictionary:
		cellar = BrewCellar.from_dict(cellar_saved, day.batch)
	var maltings_saved: Variant = data.get("maltings")
	if maltings_saved is Dictionary:
		maltings = BrewMaltings.from_dict(maltings_saved)
	var trade_saved: Variant = data.get("trade")
	if trade_saved is Dictionary:
		trade.restore(trade_saved)
	_restore_places(data.get("utensils"))
	# Kegs stand upright under the taps, the funnel in a bung hole; the keg on
	# the counter waits for the world.
	for number in range(1, BrewCellar.CASKS + 1):
		var keg := cellar.keg_under[number - 1]
		if keg != "":
			(_utensils[keg].node as Node3D).transform = _keg_at_tap(number)
	if cellar.funnel_on != "" and cellar.keg_under.has(cellar.funnel_on):
		(_utensils.funnel.node as Node3D).transform = Transform3D(Basis.IDENTITY, _bung(cellar.funnel_on))
	_seat_tap = cellar.tap != ""

func _restore_places(places: Variant) -> void:
	if not places is Dictionary:
		return
	for id: Variant in places:
		var place: Variant = places[id]
		if not _utensils.has(id) or not place is Array or place.size() != 4:
			continue
		var numbers: Array[float] = []
		for value: Variant in place:
			if (value is float or value is int) and is_finite(float(value)):
				numbers.append(float(value))
		if numbers.size() == 4 and Vector3(numbers[0], numbers[1], numbers[2]).length() < 50.0:
			(_utensils[id].node as Node3D).transform = Transform3D(Basis(Vector3.UP, numbers[3]),
				Vector3(numbers[0], numbers[1], numbers[2]))

static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
