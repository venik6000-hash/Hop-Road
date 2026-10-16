class_name BrewStation
extends RefCounted
## A station of the brewery (brewery.json's `stations`) in station mode: what
## the hand does there (a work), by the thing it holds, and what each move of
## the work's gesture does to the brewing day (BrewDay) and the cellar
## (BrewCellar).
##
## A work is {id, title, gesture (BrewGesture.KINDS), held (the utensils it
## needs in the hand; none: an empty hand), part (the moving part of
## brewery.json it turns, if any), weight, along}. A numbered station
## (`fermenter_1`, `lager_3`) takes the works of its kind (NUMBERED), with its
## number in the part's name; a dried-out tun or cask has none.

const WORKS := {
	"liquor": [
		{"id": "pump_liquor", "title": "качать воду в котёл", "gesture": "rock", "part": "liquor_pump_handle", "weight": 1.5},
		{"id": "pipe_cock", "title": "кран трубы к котлу", "gesture": "draw", "part": "liquor_pipe_cock_key"},
		{"id": "fill_bucket", "title": "зачерпнуть воды", "gesture": "tilt", "held": ["water_bucket"]},
	],
	"copper": [
		{"id": "hatch", "title": "люк котла", "gesture": "draw", "part": "copper_hatch", "along": [0.0, 1.0]},
		{"id": "stir_copper", "title": "мешать в котле", "gesture": "circle", "held": ["mash_paddle"], "weight": 1.5},
		{"id": "throw_hops", "title": "бросить хмель в люк", "gesture": "throw", "held": ["hop_basket"]},
		{"id": "bucket_copper", "title": "вылить ведро в люк", "gesture": "tilt", "held": ["water_bucket"]},
		{"id": "scoop", "title": "зачерпнуть кипятку", "gesture": "tilt", "held": ["water_bucket"]},
		{"id": "pour_honey", "title": "влить мёд в люк", "gesture": "tilt", "held": ["honey_pot"]},
		{"id": "throw_linden", "title": "бросить липовый цвет в люк", "gesture": "throw", "held": ["linden_bunch"]},
	],
	"firebox": [
		{"id": "stoke", "title": "подбросить полено", "gesture": "throw", "held": ["log", "beech_log"], "weight": 1.5},
		{"id": "damper", "title": "заслонка котла", "gesture": "draw", "part": "copper_damper", "along": [0.0, 1.0]},
	],
	"mash_tun": [
		{"id": "liquor_cock", "title": "кран горячей воды", "gesture": "draw", "part": "liquor_cock_key"},
		{"id": "grain", "title": "засыпать солод", "gesture": "tilt", "held": BrewIds.GRIST_SACKS, "weight": 2.0},
		{"id": "stir_mash", "title": "мешать затор", "gesture": "circle", "held": ["mash_paddle"], "weight": 2.0},
		{"id": "bucket_mash", "title": "долить ключевой воды", "gesture": "tilt", "held": ["water_bucket"]},
		{"id": "line_tun", "title": "выстелить дно можжевельником", "gesture": "tilt", "held": ["juniper_bundle"]},
	],
	"underback": [
		{"id": "mash_tap", "title": "кран заторного чана", "gesture": "draw", "part": "mash_tap_key"},
	],
	"wort_pump": [
		{"id": "pump_wort", "title": "качать сусло в котёл", "gesture": "rock", "part": "wort_pump_lever", "weight": 1.5},
	],
	"hop_back": [
		{"id": "copper_tap", "title": "кран котла", "gesture": "draw", "part": "copper_tap_key"},
	],
	"hop_back_tap": [
		{"id": "hop_back_tap", "title": "кран хмелецедильного чана", "gesture": "draw", "part": "hop_back_tap_key"},
	],
	"windlass": [
		{"id": "wind", "title": "крутить ворот", "gesture": "circle", "part": "windlass", "weight": 2.0},
	],
	"coolship": [
		{"id": "pour_coolship", "title": "вылить бадью на тарелку", "gesture": "tilt", "held": ["hoist_bucket"], "weight": 2.0},
		{"id": "coolship_gate", "title": "затвор тарелки", "gesture": "draw", "part": "coolship_gate"},
	],
	"spout": [
		{"id": "spout", "title": "повернуть носик", "gesture": "draw", "part": "swivel_spout"},
	],
	"yeast_shelf": [
		{"id": "dip_yeast", "title": "зачерпнуть дрожжей", "gesture": "tilt", "held": ["dipper"]},
	],
	"fermenter": [
		{"id": "fermenter_tap", "title": "кран бродильного чана", "gesture": "draw", "part": "fermenter_tap_%d_key"},
		{"id": "pitch", "title": "влить дрожжи", "gesture": "tilt", "held": ["dipper"]},
		{"id": "skim", "title": "снять пену", "gesture": "stripe", "held": ["skimmer"]},
	],
	"lager": [
		{"id": "lager_tap", "title": "кран лагерной бочки", "gesture": "draw", "part": "lager_tap_%d_key"},
		{"id": "taste", "title": "налить пробу в кружку", "gesture": "draw", "part": "lager_tap_%d_key"},
		{"id": "fill_cask", "title": "вылить ведро в бочку", "gesture": "tilt", "held": ["cellar_bucket"], "weight": 1.5},
		{"id": "scald", "title": "ошпарить бочку кипятком", "gesture": "tilt", "held": ["water_bucket"]},
		{"id": "cherry_cask", "title": "засыпать вишню в бочку", "gesture": "tilt", "held": ["cherry_basket"], "weight": 1.5},
		{"id": "bung_cask", "title": "забить пробку в бочку", "gesture": "strike", "held": ["mallet"]},
		{"id": "bung_keg", "title": "забить пробку в бочонок", "gesture": "strike", "held": ["mallet"]},
	],
	"desk": [
		{"id": "weigh_hops", "title": "отвесить хмель на весы", "gesture": "tilt", "held": ["hop_basket"]},
	],
	"steep": [
		{"id": "steep_barley", "title": "засыпать ячмень", "gesture": "tilt", "held": BrewIds.BARLEY_SACKS, "weight": 2.0},
		{"id": "steep_water", "title": "вылить ведро в чан", "gesture": "tilt", "held": ["water_bucket"]},
		{"id": "steep_plug", "title": "пробка слива", "gesture": "draw", "part": "steep_plug", "along": [0.0, 1.0]},
		{"id": "shovel_out", "title": "выгрести зерно на ток", "gesture": "stripe", "held": ["malt_shovel"], "weight": 1.5},
	],
	"floor": [
		{"id": "turn_couch", "title": "ворошить кучу", "gesture": "stripe", "held": ["malt_shovel"], "weight": 1.5},
	],
	"kiln": [
		{"id": "load_kiln", "title": "перекинуть солод на сушилку", "gesture": "stripe", "held": ["malt_shovel"], "weight": 1.5},
		{"id": "kiln_stoke", "title": "подбросить полено", "gesture": "throw", "held": ["log", "beech_log"], "weight": 1.5},
		{"id": "kiln_damper", "title": "заслонка сушилки", "gesture": "draw", "part": "kiln_damper", "along": [0.0, 1.0]},
		{"id": "rake", "title": "ворошить солод граблями", "gesture": "stripe", "held": ["kiln_rake"]},
		{"id": "sack_kiln", "title": "насыпать солод в мешок", "gesture": "tilt", "held": BrewIds.BARLEY_SACKS},
	],
	"mill": [
		{"id": "grind", "title": "крутить жёрнов", "gesture": "circle", "part": "quern_runner", "weight": 2.0},
		{"id": "quern_wedge", "title": "клин жёрнова", "gesture": "draw", "part": "quern_wedge"},
		{"id": "pour_hopper", "title": "засыпать солод в жёрнов", "gesture": "tilt", "held": BrewIds.BARLEY_SACKS, "weight": 2.0},
		{"id": "sack_bin", "title": "набрать помол в мешок", "gesture": "tilt", "held": BrewIds.BARLEY_SACKS},
	],
}
## Works whose gesture sets a control of BrewDay of the same id.
const CONTROLS: Array[String] = ["liquor_cock", "mash_tap", "copper_tap", "hop_back_tap", "pipe_cock", "damper", "hatch"]
## Works whose gesture sets a control of BrewCellar: of the same id, or of the
## id with the station's number.
const CELLAR_CONTROLS: Array[String] = ["coolship_gate", "spout", "fermenter_tap", "lager_tap"]
## Works whose gesture sets a control of BrewMaltings of the same id.
const MALT_CONTROLS: Array[String] = ["steep_plug", "kiln_damper", "quern_wedge"]
## Kinds of numbered stations, and how far a tap of a taste is drawn before
## the mug is filled.
const NUMBERED: Array[String] = ["fermenter", "lager"]
const TASTE_OPEN := 0.5

var id := ""
## The number of a numbered station, 0 for the others.
var number := 0
var cellar: BrewCellar
var maltings: BrewMaltings
var held := ""
var works: Array[Dictionary] = []
var index := 0
var gesture: BrewGesture

var _counted := 0
var _turns := 0.0
var _tasted := false

## The number of a numbered station (`lager_3` → 3), 0 for another.
static func number_of(station: String) -> int:
	var tail := station.get_slice("_", station.get_slice_count("_") - 1)
	if NUMBERED.has(station.trim_suffix("_" + tail)) and tail.is_valid_int():
		return int(tail)
	return 0

## The works of a station for what the hand holds ("" for nothing); a tun
## or cask of `cellar_now` that is dried out has none (without a cellar, as
## the brewery is handed over).
static func works_for(station: String, holding: String, cellar_now: BrewCellar = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := number_of(station)
	var kind := station
	if count > 0:
		kind = station.trim_suffix("_%d" % count)
		var sound := count <= (BrewCellar.START_SOUND_TUNS if kind == "fermenter" else BrewCellar.START_SOUND_CASKS)
		if cellar_now != null:
			sound = cellar_now.sound_tun(count) if kind == "fermenter" else cellar_now.sound_cask(count)
		if not sound:
			return result
	for work: Dictionary in WORKS.get(kind, []):
		var needs: Array = work.get("held", [])
		if needs.has(holding) or (needs.is_empty() and holding == ""):
			var made := work.duplicate()
			if count > 0 and made.has("part"):
				made.part = str(made.part) % count
			result.append(made)
	return result

## Station mode at `station` with `holding` in the hand; null when the hand
## can do nothing there.
static func open(station: String, holding: String, day: BrewDay, cellar_now: BrewCellar = null,
		maltings_now: BrewMaltings = null) -> BrewStation:
	var found := works_for(station, holding, cellar_now)
	if found.is_empty():
		return null
	var mode := BrewStation.new()
	mode.id = station
	mode.number = number_of(station)
	mode.held = holding
	mode.works = found
	mode.cellar = cellar_now
	mode.maltings = maltings_now
	mode._begin(day)
	return mode

func work() -> Dictionary:
	return works[index]

## The next work of the station (the mouse wheel).
func next(day: BrewDay, step := 1) -> void:
	index = posmod(index + step, works.size())
	_begin(day)

func _begin(day: BrewDay) -> void:
	var current := work()
	gesture = BrewGesture.make(str(current.gesture), float(current.get("weight", 1.0)))
	var along: Array = current.get("along", [1.0, 0.0])
	gesture.along = Vector2(along[0], along[1])
	if CONTROLS.has(str(current.id)):
		gesture.amount = float(day.controls[current.id])
	elif CELLAR_CONTROLS.has(str(current.id)) and cellar != null:
		gesture.amount = float(cellar.controls[control()])
	elif MALT_CONTROLS.has(str(current.id)) and maltings != null:
		gesture.amount = float(maltings.controls[current.id])
	_counted = 0
	_turns = 0.0
	_tasted = false

## The cellar's control the work sets: its id, with the station's number for a tap.
func control() -> String:
	var work_id := str(work().id)
	return "%s_%d" % [work_id, number] if work_id.ends_with("_tap") else work_id

## The mouse moved `motion` pixels in `delta` real seconds, in which the game
## clock went `minutes`. Returns true when what the hand held has left it
## (a log thrown into the fire).
func update(day: BrewDay, motion: Vector2, delta: float, minutes: float) -> bool:
	gesture.feed(motion, delta)
	var work_id := str(work().id)
	var made := gesture.count - _counted
	_counted = gesture.count
	if CONTROLS.has(work_id):
		day.set_control(work_id, gesture.amount)
		return false
	if cellar != null and _cellar_work(day, work_id, made, minutes):
		return false
	if maltings != null:
		var malt_done := _malt_work(day, work_id, made, minutes)
		if malt_done >= 0:
			return malt_done == 1
	match work_id:
		"pump_liquor":
			day.pump_liquor(made)
		"pump_wort":
			day.pump_wort(made)
		"fill_bucket":
			day.fill_bucket(gesture.flow(), minutes)
		"bucket_copper":
			day.pour_bucket(BrewDay.COPPER, gesture.flow(), minutes)
		"bucket_mash":
			day.pour_bucket(BrewDay.MASH_TUN, gesture.flow(), minutes)
		"grain":
			if BrewIds.BARLEY_SACKS.has(held) and maltings != null:
				day.pour_lots(maltings.take_grist(held, gesture.flow() * BrewDay.GRAIN_POUR * minutes))
			else:
				day.pour_grain(held, gesture.flow(), minutes, true)
		"stir_mash":
			day.stir_mash(gesture.take_turns())
		"stir_copper":
			if gesture.take_turns() != 0:
				day.stir_copper()
		"throw_hops":
			for _throw in made:
				day.throw_hops()
		"stoke":
			if made > 0:
				day.stoke()
				return true
		"wind":
			day.wind(gesture.turns - _turns)
			_turns = gesture.turns
		"pour_coolship":
			day.pour_hoist_bucket(gesture.flow(), minutes, true)
		"weigh_hops":
			day.weigh_hops(gesture.flow(), minutes)
		"scoop":
			day.scoop_copper(gesture.flow(), minutes)
		"line_tun":
			day.line_tun(gesture.flow(), minutes)
		"pour_honey":
			day.pour_honey(gesture.flow(), minutes)
		"throw_linden":
			for _throw in made:
				day.throw_linden()
	return false

## The works of the cellar; false when `work_id` is none of them.
func _cellar_work(day: BrewDay, work_id: String, made: int, minutes: float) -> bool:
	if CELLAR_CONTROLS.has(work_id):
		cellar.set_control(control(), gesture.amount)
		return true
	match work_id:
		"taste":
			if gesture.amount >= TASTE_OPEN and not _tasted:
				_tasted = true
				cellar.taste(number)
		"dip_yeast":
			cellar.dip_yeast(gesture.flow(), minutes)
		"pitch":
			cellar.pour_dipper(number, gesture.flow(), minutes)
		"skim":
			cellar.skim(number, made)
		"fill_cask":
			cellar.fill_cask(number, gesture.flow(), minutes)
		"cherry_cask":
			cellar.cherry_cask(number, gesture.flow(), minutes)
		"scald":
			cellar.scald(number, day.pour_bucket("", gesture.flow(), minutes), day.water_bucket_temp)
		"bung_cask":
			cellar.strike_cask(number, made)
		"bung_keg":
			cellar.strike_keg(cellar.keg_under[number - 1], made)
		_:
			return false
	return true

## The works of the maltings: -1 when `work_id` is none of them, 1 when what
## the hand held has left it (a log thrown into the kiln), else 0.
func _malt_work(day: BrewDay, work_id: String, made: int, minutes: float) -> int:
	if MALT_CONTROLS.has(work_id):
		maltings.set_control(work_id, gesture.amount)
		return 0
	match work_id:
		"steep_barley":
			maltings.pour_steep(held, gesture.flow(), minutes)
		"steep_water":
			maltings.water_steep(day.pour_bucket("", gesture.flow(), minutes))
		"shovel_out":
			maltings.shovel_out(made)
		"turn_couch":
			maltings.turn_couch(made)
		"load_kiln":
			maltings.load_kiln(made)
		"kiln_stoke":
			if made > 0:
				maltings.stoke(held)
				return 1
		"rake":
			maltings.rake(made)
		"sack_kiln":
			maltings.sack_kiln(held, gesture.flow(), minutes)
		"grind":
			var turned := gesture.turns - _turns
			_turns = gesture.turns
			maltings.grind(turned)
		"pour_hopper":
			maltings.pour_hopper(held, gesture.flow(), minutes)
		"sack_bin":
			maltings.sack_bin(held, gesture.flow(), minutes)
		_:
			return -1
	return 0

## How far the work's moving part stands (BuildingMachinery.set_pose): open
## for a tap, down for a pump handle, the angle of the windlass.
func pose(day: BrewDay) -> float:
	if str(work().id) == "wind":
		return day.lift / BrewDay.LIFT_TURN * TAU
	if str(work().id) == "grind" and maltings != null:
		return maltings.quern_angle
	return gesture.amount
