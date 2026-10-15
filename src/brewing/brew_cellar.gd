class_name BrewCellar
extends RefCounted
## The brewery's cellar (docs/plans/brewing.md, section 4, from the cooling
## plate to the keg on the tavern's counter): the fermenting tuns, the yeast,
## the lager casks, the kegs and the keg Borr pours from. Litres and where they
## run are here; what the beer becomes is the batch's: this calls the steps of
## BrewBatch and counts none of its numbers again. The fermentation and the
## ageing go a day at a time (dawn), which the game clock gives (DayClock).
##
## Fermenting tuns, lager casks and taps are numbered from 1 as in
## brewery.json; casks are the lower tier's, the four with taps.

## °C of the cellar's air.
const TEMP := 10.0
## Litres a game minute through the plate's gate, a fermenting tun's tap and a
## lager cask's tap opened full; through a tipped dipper.
const GATE_FLOW := 30.0
const FERMENTER_TAP := 20.0
const LAGER_TAP := 15.0
const DIPPER_FLOW := 2.0
## Fermenting tuns and lager casks; when the brewery is handed over only the
## first START_SOUND_TUNS and START_SOUND_CASKS hold beer: the others are
## dried out and wait for the cooper (section 6, BrewTrade).
const TUNS := 2
const START_SOUND_TUNS := 1
const CASKS := 4
const START_SOUND_CASKS := 2
## Litres a lager cask, a keg, the cellar bucket, the dipper, the yeast crock hold.
const CASK_L := 450.0
const KEG_L := 40.0
const BUCKET_L := 20.0
const DIPPER_L := 1.0
const CROCK_L := 4.0
## Yeast in the crock when the brewery is handed over; what a head of yeast
## skimmed gives back to it.
const CROCK_START := 3.0
## Kg of cherries a full basket holds (the market's ware); kg a game minute of
## the basket tipped full.
const CHERRY_BASKET_KG := 25.0
const CHERRY_POUR := 10.0
const SKIM_YEAST := 0.5
## Passes of the skimmer that take a head off.
const SKIM_PASSES := 3
## A cask is scalded by SCALD_L of water at SCALD_TEMP °C or hotter.
const SCALD_L := 8.0
const SCALD_TEMP := 80.0
## Blows of the mallet that drive a bung home.
const BUNG_BLOWS := 2
## Without the funnel in its bung hole this part of a tap's stream misses a keg.
const NO_FUNNEL_MISS := 0.5
## Litres a mug takes; litres the tavern's guests drink an hour of the day.
const MUG_L := 0.5
const GUESTS_L := 1.5
## The kegs of the rack (brewery.json's utensils).
const KEGS: Array[String] = ["keg_1", "keg_2", "keg_3", "keg_4", "keg_5", "keg_6"]
## The hand-set controls and where they start: the plate's gate, the swivel
## spout (1 over tun 1, 0 over tun 2), the tuns' and the casks' taps.
const CONTROLS := {"coolship_gate": 0.0, "spout": 1.0, "fermenter_tap_1": 0.0, "fermenter_tap_2": 0.0,
	"lager_tap_1": 0.0, "lager_tap_2": 0.0, "lager_tap_3": 0.0, "lager_tap_4": 0.0}
## The moving part of brewery.json each control turns.
const PARTS := {"coolship_gate": "coolship_gate", "spout": "swivel_spout", "fermenter_tap_1": "fermenter_tap_1_key",
	"fermenter_tap_2": "fermenter_tap_2_key", "lager_tap_1": "lager_tap_1_key", "lager_tap_2": "lager_tap_2_key",
	"lager_tap_3": "lager_tap_3_key", "lager_tap_4": "lager_tap_4_key"}

var controls := CONTROLS.duplicate()
## How many tuns and casks, from the first, hold beer.
var sound_tuns := START_SOUND_TUNS
var sound_casks := START_SOUND_CASKS
## Each fermenting tun: {batch (null when the tun is empty), liters, skimmed
## (the head was skimmed since the last dawn), passes (of the skimmer so far)}.
var tuns: Array[Dictionary] = []
var crock_l := CROCK_START
## Kg of cherries in the basket.
var cherries_kg := 0.0
var dipper_l := 0.0
## The cellar bucket: litres of beer, the batch they are, the anchor it
## stands at ("" when it is carried or stands elsewhere).
var bucket_l := 0.0
var bucket_batch: BrewBatch
var bucket_at := ""
## Each lager cask: {batch (BrewBatch or null), liters, scald_l (hot water
## poured through it while empty), bunged, blows}.
var casks: Array[Dictionary] = []
## Each keg: {liters, beer (the batch's profile when it was filled), bunged, blows}.
var kegs := {}
## The keg standing under each cask's tap ("" for none), the keg the funnel
## stands in, the keg on the tavern's counter.
var keg_under: Array[String] = []
var funnel_on := ""
var tap := ""
## The keg the counter has just emptied, for the world to take back to the
## rack; the taste just poured at a cask ({} when none). Both are taken.
var emptied := ""
var tasted := {}

func _init() -> void:
	for _tun in TUNS:
		tuns.append(_empty_tun())
	for _cask in CASKS:
		casks.append(_empty_cask())
		keg_under.append("")
	for id: String in KEGS:
		kegs[id] = _empty_keg()

static func _empty_tun() -> Dictionary:
	return {"batch": null, "liters": 0.0, "skimmed": false, "passes": 0}

static func _empty_cask() -> Dictionary:
	return {"batch": null, "liters": 0.0, "scald_l": 0.0, "bunged": false, "blows": 0, "cherries": 0.0}

static func _empty_keg() -> Dictionary:
	return {"liters": 0.0, "beer": {}, "bunged": false, "blows": 0}

func set_control(id: String, amount: float) -> void:
	if controls.has(id):
		controls[id] = clampf(amount, 0.0, 1.0)

## The tun the swivel spout pours into.
func spout_tun() -> int:
	return 1 if float(controls.spout) >= 0.5 else 2

## Whether tun or cask `number` holds beer.
func sound_tun(number: int) -> bool:
	return number >= 1 and number <= sound_tuns

func sound_cask(number: int) -> bool:
	return number >= 1 and number <= sound_casks

## The batch in tun `number`, null when it is empty; its litres.
func tun_batch(number: int) -> BrewBatch:
	return tuns[number - 1].batch if number >= 1 and number <= TUNS else null

func tun_l(number: int) -> float:
	return float(tuns[number - 1].liters) if number >= 1 and number <= TUNS else 0.0

## The tun that holds `batch`, 0 for none.
func tun_of(batch: BrewBatch) -> int:
	for number in range(1, TUNS + 1):
		if batch != null and tun_batch(number) == batch:
			return number
	return 0

## The game clock moved on `minutes` from `hour`; the brewing day `day` holds
## the cooling plate the gate drains. A long span goes in pieces of an hour
## at most (BrewHouse), so that `hour` holds for it.
func advance(day: BrewDay, minutes: float, hour: float) -> void:
	_run_gate(day, minutes)
	for number in range(1, TUNS + 1):
		_run_fermenter_tap(number, minutes)
	for number in range(1, CASKS + 1):
		_run_lager_tap(number, minutes)
	for tun: Dictionary in tuns:
		var batch: BrewBatch = tun.batch
		if batch == null:
			continue
		# The brewing day cools the wort while it is still the plate's.
		if batch != day.batch or batch.stage == "pitched":
			batch.cool(minutes / 60.0, TEMP)
		if float(tun.liters) <= 0.5 and batch != day.batch:
			tun.merge(_empty_tun(), true)
	if tun_of(day.batch) > 0 and day.wort_left() <= 0.01:
		day.hand_over()
	if tap != "" and DayClock.is_day(hour):
		kegs[tap].liters = float(kegs[tap].liters) - GUESTS_L * minutes / 60.0
		_settle_tap()

## A new day in the cellar: a day of fermentation in each tun, a day of
## ageing in each bunged cask.
func dawn() -> void:
	for tun: Dictionary in tuns:
		var batch: BrewBatch = tun.batch
		if batch != null and batch.stage == "pitched":
			batch.ferment_day(TEMP, tun.skimmed)
		tun.skimmed = false
		tun.passes = 0
	for cask: Dictionary in casks:
		var batch: BrewBatch = cask.batch
		if batch != null and cask.bunged:
			batch.age_day()

## The wort of the plate runs through the gate down the spout: into a sound
## empty tun it becomes the cellar's batch; into a dried-out one, onto another
## batch, or into a second tun once the batch has one, it is lost.
func _run_gate(day: BrewDay, minutes: float) -> void:
	var liters := minf(float(controls.coolship_gate) * GATE_FLOW * minutes, day.coolship_l)
	if liters <= 0.0:
		return
	day.coolship_l -= liters
	var number := spout_tun()
	var held := tun_batch(number)
	var elsewhere := tun_of(day.batch)
	if not sound_tun(number) or (held != null and held != day.batch) or (elsewhere > 0 and elsewhere != number):
		day.batch.spill(liters)
		return
	tuns[number - 1].batch = day.batch
	tuns[number - 1].liters = tun_l(number) + liters

func _run_fermenter_tap(number: int, minutes: float) -> void:
	var tun := tuns[number - 1]
	var liters := minf(float(controls["fermenter_tap_%d" % number]) * FERMENTER_TAP * minutes, float(tun.liters))
	if liters <= 0.0:
		return
	tun.liters = float(tun.liters) - liters
	var batch: BrewBatch = tun.batch
	if bucket_at != "fermenter_%d_bucket" % number or (bucket_l > 0.01 and bucket_batch != batch):
		batch.spill(liters)
		return
	bucket_batch = batch
	var taken := minf(liters, BUCKET_L - bucket_l)
	bucket_l += taken
	batch.spill(liters - taken)

func _run_lager_tap(number: int, minutes: float) -> void:
	var cask := casks[number - 1]
	var liters := minf(float(controls["lager_tap_%d" % number]) * LAGER_TAP * minutes, float(cask.liters))
	if liters <= 0.0:
		return
	cask.liters = float(cask.liters) - liters
	var batch: BrewBatch = cask.batch
	var id := keg_under[number - 1]
	var into := 0.0
	if id != "" and not kegs[id].bunged:
		var keg: Dictionary = kegs[id]
		var aimed := liters * (1.0 if funnel_on == id else 1.0 - NO_FUNNEL_MISS)
		into = minf(aimed, KEG_L - float(keg.liters))
		keg.liters = float(keg.liters) + into
		keg.beer = batch.profile()
	batch.spill(liters - into)
	_settle_cask(number)

## A cask run dry is empty again: scalded no more, unbunged.
func _settle_cask(number: int) -> void:
	if float(casks[number - 1].liters) < 0.5:
		casks[number - 1] = _empty_cask()

## Yeast from the crock into the dipper at `flow` for `minutes`.
func dip_yeast(flow: float, minutes: float) -> void:
	var liters := minf(minf(flow * DIPPER_FLOW * minutes, DIPPER_L - dipper_l), crock_l)
	if liters > 0.0:
		crock_l -= liters
		dipper_l += liters

## The dipper tipped over tun `number` at `flow` for `minutes`: the yeast goes
## into its wort, or is wasted where there is none.
func pour_dipper(number: int, flow: float, minutes: float) -> void:
	var liters := minf(flow * DIPPER_FLOW * minutes, dipper_l)
	if liters <= 0.0:
		return
	dipper_l -= liters
	if tun_batch(number) != null and tun_l(number) > 1.0:
		tun_batch(number).pitch(liters)

## Whether a head of yeast stands on the beer fermenting in tun `number` to
## be skimmed.
func head(number := 1) -> bool:
	var batch := tun_batch(number)
	return batch != null and batch.stage == "pitched" and batch.ferment_days >= 1 and batch.ferment < 1.0 \
		and not tuns[number - 1].skimmed

## `passes` of the skimmer over tun `number`; a head taken off gives yeast
## back to the crock.
func skim(number: int, passes: int) -> void:
	if passes <= 0 or not head(number):
		return
	var tun := tuns[number - 1]
	tun.passes = int(tun.passes) + passes
	if int(tun.passes) >= SKIM_PASSES:
		tun.skimmed = true
		crock_l = minf(CROCK_L, crock_l + SKIM_YEAST)

## The cellar bucket tipped into lager cask `number` at `flow` for `minutes`.
## The first beer racks the batch into the cask; a cask holds one batch, and
## a batch goes into one cask. What it will not take is lost.
func fill_cask(number: int, flow: float, minutes: float) -> void:
	var liters := minf(flow * BrewDay.BUCKET_POUR * minutes, bucket_l)
	if liters <= 0.0 or not sound_cask(number):
		return
	bucket_l -= liters
	var batch := bucket_batch
	var cask := casks[number - 1]
	if cask.batch == null and batch.stage == "pitched":
		cask.batch = batch
		batch.rack(float(cask.scald_l) >= SCALD_L, INF, float(cask.cherries))
	if cask.batch != batch:
		batch.spill(liters)
		return
	var taken := minf(liters, CASK_L - float(cask.liters))
	cask.liters = float(cask.liters) + taken
	batch.spill(liters - taken)

## The cherry basket tipped into lager cask `number` at `flow` for `minutes`:
## cherries wait in the empty cask for the beer racked onto them; onto beer
## already racked they are lost.
func cherry_cask(number: int, flow: float, minutes: float) -> void:
	var kg := minf(flow * CHERRY_POUR * minutes, cherries_kg)
	if kg <= 0.0:
		return
	cherries_kg -= kg
	if sound_cask(number) and casks[number - 1].batch == null:
		casks[number - 1].cherries = float(casks[number - 1].cherries) + kg

## `liters` of water at `temp` °C poured through lager cask `number`; while it
## is empty, hot water scalds it.
func scald(number: int, liters: float, temp: float) -> void:
	if sound_cask(number) and float(casks[number - 1].liters) <= 0.0 and temp >= SCALD_TEMP:
		casks[number - 1].scald_l = float(casks[number - 1].scald_l) + liters

func scalded(number: int) -> bool:
	return float(casks[number - 1].scald_l) >= SCALD_L

## `blows` of the mallet on the bung of lager cask `number`, of keg `id`.
func strike_cask(number: int, blows: int) -> void:
	_strike(casks[number - 1], blows)

func strike_keg(id: String, blows: int) -> void:
	if kegs.has(id) and funnel_on != id:
		_strike(kegs[id], blows)

func _strike(vessel: Dictionary, blows: int) -> void:
	if blows <= 0 or float(vessel.liters) <= 0.0:
		return
	vessel.blows = int(vessel.blows) + blows
	vessel.bunged = int(vessel.blows) >= BUNG_BLOWS

## A taste of lager cask `number` drawn into the mug: the beer's profile now
## (green while it ages), {} when there is none. It waits in `tasted` too.
func taste(number: int) -> Dictionary:
	var cask := casks[number - 1]
	var batch: BrewBatch = cask.batch
	if batch == null or float(cask.liters) < MUG_L:
		return {}
	cask.liters = float(cask.liters) - MUG_L
	tasted = batch.profile()
	tasted["cask"] = number
	tasted["days_left"] = maxi(0, batch.ready_days() - batch.age_days)
	_settle_cask(number)
	return tasted

func take_taste() -> Dictionary:
	var taken := tasted
	tasted = {}
	return taken

## Keg `id` put where it stands: under the tap of cask `number` (0 for none).
func stand_keg(id: String, number: int) -> void:
	for index in CASKS:
		if keg_under[index] == id:
			keg_under[index] = ""
	if number >= 1 and number <= CASKS:
		keg_under[number - 1] = id
	if funnel_on == id and number == 0:
		funnel_on = ""

## Keg `id` set on the tavern's counter: "" when it is set, else why not:
## "busy" (another keg is there), "not_ready" (open or empty), "ruined".
func set_tap(id: String) -> String:
	if tap != "" and tap != id:
		return "busy"
	var keg: Dictionary = kegs[id]
	if not keg.bunged or float(keg.liters) < MUG_L:
		return "not_ready"
	if (keg.beer as Dictionary).get("ruined", false):
		return "ruined"
	tap = id
	return ""

## Keg `id` emptied and unbunged: it went away with its beer.
func empty_keg(id: String) -> void:
	if kegs.has(id):
		kegs[id] = _empty_keg()
		stand_keg(id, 0)
		take_tap(id)

func take_tap(id: String) -> void:
	if tap == id:
		tap = ""

## A mug drawn from the keg on the counter: its beer's profile; {} when no keg
## stands there, and Borr pours the old beer.
func pour_mug() -> Dictionary:
	if tap == "":
		return {}
	var keg: Dictionary = kegs[tap]
	keg.liters = float(keg.liters) - MUG_L
	var beer: Dictionary = keg.beer
	_settle_tap()
	return beer

## The keg on the counter run dry goes back to the rack empty.
func _settle_tap() -> void:
	if tap != "" and float(kegs[tap].liters) < MUG_L:
		kegs[tap] = _empty_keg()
		emptied = tap
		tap = ""

func take_emptied() -> String:
	var id := emptied
	emptied = ""
	return id

## Kg of what a cellar utensil holds.
func load_kg(utensil: String) -> float:
	if kegs.has(utensil):
		return float(kegs[utensil].liters)
	match utensil:
		"cellar_bucket":
			return bucket_l
		"dipper":
			return dipper_l
		"yeast_crock":
			return crock_l
		"cherry_basket":
			return cherries_kg
	return 0.0

## The batch last worked on in the cellar, for the brewer's book: the one in
## a tun, else in a cask; null when there is none.
func latest_batch() -> BrewBatch:
	for tun: Dictionary in tuns:
		if tun.batch != null:
			return tun.batch
	for cask: Dictionary in casks:
		if cask.batch != null:
			return cask.batch
	return null

# ---- Save -------------------------------------------------------------------

## The cellar as plain data for a save. A batch is written once and named by
## its place in `batches` (-1: the brewing day's `day_batch`, -2: none), so a
## batch shared by the tun, the bucket and a cask is one batch again when read.
func to_dict(day_batch: BrewBatch) -> Dictionary:
	var batches: Array[BrewBatch] = []
	var ref := func(batch: BrewBatch) -> int:
		if batch == null:
			return -2
		if batch == day_batch:
			return -1
		if not batches.has(batch):
			batches.append(batch)
		return batches.find(batch)
	var saved_casks: Array = []
	for cask: Dictionary in casks:
		saved_casks.append({"batch": ref.call(cask.batch), "liters": cask.liters, "scald_l": cask.scald_l,
			"bunged": cask.bunged, "blows": cask.blows, "cherries": cask.cherries})
	var saved_tuns: Array = []
	for tun: Dictionary in tuns:
		saved_tuns.append({"batch": ref.call(tun.batch), "liters": tun.liters, "skimmed": tun.skimmed, "passes": tun.passes})
	var data := {"controls": controls.duplicate(), "tuns": saved_tuns, "sound_tuns": sound_tuns, "sound_casks": sound_casks,
		"crock_l": crock_l, "dipper_l": dipper_l, "cherries_kg": cherries_kg,
		"bucket_l": bucket_l, "bucket": ref.call(bucket_batch), "bucket_at": bucket_at, "casks": saved_casks,
		"kegs": kegs.duplicate(true), "keg_under": keg_under.duplicate(), "funnel_on": funnel_on, "tap": tap}
	var written: Array = []
	for batch: BrewBatch in batches:
		written.append(batch.to_dict())
	data["batches"] = written
	return data

## A cellar read back from to_dict() through JSON; what is missing or wrong
## keeps the start's.
static func from_dict(data: Dictionary, day_batch: BrewBatch) -> BrewCellar:
	var cellar := BrewCellar.new()
	var batches: Array[BrewBatch] = []
	var written: Variant = data.get("batches")
	if written is Array:
		for item: Variant in written:
			batches.append(BrewBatch.from_dict(item) if item is Dictionary else BrewBatch.new())
	var ref := func(value: Variant) -> BrewBatch:
		var index := int(_number(value, -2.0, -2.0, 1e6))
		if index == -1:
			return day_batch
		return batches[index] if index >= 0 and index < batches.size() else null
	var saved_controls: Variant = data.get("controls")
	if saved_controls is Dictionary:
		for id: String in CONTROLS:
			cellar.controls[id] = _number(saved_controls.get(id), float(CONTROLS[id]), 0.0, 1.0)
	cellar.sound_tuns = int(_number(data.get("sound_tuns"), START_SOUND_TUNS, START_SOUND_TUNS, TUNS))
	cellar.sound_casks = int(_number(data.get("sound_casks"), START_SOUND_CASKS, START_SOUND_CASKS, CASKS))
	var saved_tuns: Variant = data.get("tuns")
	if saved_tuns is Array:
		for index in mini(TUNS, (saved_tuns as Array).size()):
			var item: Variant = saved_tuns[index]
			if not item is Dictionary:
				continue
			var batch: BrewBatch = ref.call(item.get("batch"))
			cellar.tuns[index] = {"batch": batch,
				"liters": _number(item.get("liters"), 0.0, 0.0, 2000.0) if batch != null else 0.0,
				"skimmed": item.get("skimmed") == true, "passes": int(_number(item.get("passes"), 0.0, 0.0, 100.0))}
	cellar.crock_l = _number(data.get("crock_l"), CROCK_START, 0.0, CROCK_L)
	cellar.cherries_kg = _number(data.get("cherries_kg"), 0.0, 0.0, CHERRY_BASKET_KG)
	cellar.dipper_l = _number(data.get("dipper_l"), 0.0, 0.0, DIPPER_L)
	cellar.bucket_batch = ref.call(data.get("bucket"))
	cellar.bucket_l = _number(data.get("bucket_l"), 0.0, 0.0, BUCKET_L) if cellar.bucket_batch != null else 0.0
	cellar.bucket_at = str(data.get("bucket_at", "")) if data.get("bucket_at") is String else ""
	var saved_casks: Variant = data.get("casks")
	if saved_casks is Array:
		for index in mini(CASKS, (saved_casks as Array).size()):
			var item: Variant = saved_casks[index]
			if not item is Dictionary:
				continue
			var batch: BrewBatch = ref.call(item.get("batch"))
			cellar.casks[index] = {"batch": batch, "liters": _number(item.get("liters"), 0.0, 0.0, CASK_L) if batch != null else 0.0,
				"scald_l": _number(item.get("scald_l"), 0.0, 0.0, 1e4), "bunged": item.get("bunged") == true,
				"blows": int(_number(item.get("blows"), 0.0, 0.0, 100.0)),
				"cherries": _number(item.get("cherries"), 0.0, 0.0, CHERRY_BASKET_KG * 4.0)}
	var saved_kegs: Variant = data.get("kegs")
	if saved_kegs is Dictionary:
		for id: String in KEGS:
			var item: Variant = saved_kegs.get(id)
			if not item is Dictionary:
				continue
			var beer := _beer(item.get("beer"))
			cellar.kegs[id] = {"liters": _number(item.get("liters"), 0.0, 0.0, KEG_L) if not beer.is_empty() else 0.0,
				"beer": beer, "bunged": item.get("bunged") == true, "blows": int(_number(item.get("blows"), 0.0, 0.0, 100.0))}
	var under: Variant = data.get("keg_under")
	if under is Array:
		for index in mini(CASKS, (under as Array).size()):
			cellar.keg_under[index] = _keg(under[index])
	cellar.funnel_on = _keg(data.get("funnel_on"))
	cellar.tap = _keg(data.get("tap"))
	if cellar.tap != "" and cellar.set_tap(cellar.tap) != "":
		cellar.tap = ""
	return cellar

## A keg's id read back, "" when it is none of KEGS.
static func _keg(value: Variant) -> String:
	return value if value is String and KEGS.has(value) else ""

static func _number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback

## A keg's beer read back: a profile with the keys the world and the book
## read, else {}.
static func _beer(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var beer: Dictionary = value
	if not beer.get("notes") is Array or not beer.get("flaws") is Array or not beer.get("ruined") is bool:
		return {}
	for key: String in ["strength", "gravity", "body", "sweetness", "bitterness", "aroma", "color", "clarity", "smoke",
			"foam", "quality"]:
		var number: Variant = beer.get(key)
		if not (number is float or number is int) or not is_finite(float(number)):
			return {}
	return beer
