class_name BrewCellar
extends RefCounted
## The brewery's cellar (docs/plans/brewing.md, section 4, from the cooling
## plate to the keg on the tavern's counter): the fermenting tuns, the yeast,
## the lager casks, and the kegs with the keg Borr pours from (BrewKegRack).
## Litres and where they run are here; what the beer becomes is the batch's:
## this calls the steps of BrewBatch and counts none of its numbers again. The
## fermentation and the ageing go a day at a time (dawn), which the game clock
## gives (DayClock).
##
## Fermenting tuns, lager casks and taps are numbered from 1 as in
## brewery.json; casks are the lower tier's, the four with taps.

## °C of the cellar's air.
const TEMP := 10.0
## Litres a game minute through the plate's gate, a fermenting tun's tap and a
## lager cask's tap opened full.
const GATE_FLOW := 30.0
const FERMENTER_TAP := 20.0
const LAGER_TAP := 15.0
## Fermenting tuns and lager casks; when the brewery is handed over only the
## first START_SOUND_TUNS and START_SOUND_CASKS hold beer: the others are
## dried out and wait for the cooper (section 6, BrewTrade).
const TUNS := 2
const START_SOUND_TUNS := 1
const CASKS := 4
const START_SOUND_CASKS := 2
## Litres a lager cask, the cellar bucket, the dipper, the yeast crock hold.
const CASK_L := 450.0
const BUCKET_L := 20.0
const DIPPER_L := 1.0
const CROCK_L := 4.0
## Yeast in the crock when the brewery is handed over.
const CROCK_START := 3.0
## Kg of cherries a full basket holds (the market's ware); kg a game minute of
## the basket tipped full.
const CHERRY_BASKET_KG := 25.0
const CHERRY_POUR := 10.0
## A cask is scalded by SCALD_L of water at SCALD_TEMP °C or hotter.
const SCALD_L := 8.0
const SCALD_TEMP := 80.0
## Blows of the mallet that drive a bung home.
const BUNG_BLOWS := 2
## Litres a mug takes.
const MUG_L := 0.5
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
## The kegs, where each stands, and the one on the tavern's counter.
var rack := BrewKegRack.new()
## The taste just poured at a cask ({} when none), for the world to take.
var tasted := {}

func _init() -> void:
	for _tun in TUNS:
		tuns.append(_empty_tun())
	for _cask in CASKS:
		casks.append(_empty_cask())

static func _empty_tun() -> Dictionary:
	return {"batch": null, "liters": 0.0, "skimmed": false, "passes": 0}

static func _empty_cask() -> Dictionary:
	return {"batch": null, "liters": 0.0, "scald_l": 0.0, "bunged": false, "blows": 0, "cherries": 0.0}

func set_control(id: String, amount: float) -> void:
	if controls.has(id):
		controls[id] = clampf(amount, 0.0, 1.0)

## The tun the swivel spout pours into.
func spout_tun() -> int:
	return 1 if Values.real(controls.spout) >= 0.5 else 2

## Whether tun or cask `number` holds beer.
func sound_tun(number: int) -> bool:
	return number >= 1 and number <= sound_tuns

func sound_cask(number: int) -> bool:
	return number >= 1 and number <= sound_casks

## The batch in tun `number`, null when it is empty; its litres.
func tun_batch(number: int) -> BrewBatch:
	return tuns[number - 1].batch if number >= 1 and number <= TUNS else null

func tun_l(number: int) -> float:
	return Values.real(tuns[number - 1].liters) if number >= 1 and number <= TUNS else 0.0

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
		if batch != day.batch or batch.stage == BrewIds.STAGE_PITCHED:
			batch.cool(minutes / 60.0, TEMP)
		if Values.real(tun.liters) <= 0.5 and batch != day.batch:
			tun.merge(_empty_tun(), true)
	if tun_of(day.batch) > 0 and day.wort_left() <= 0.01:
		day.hand_over()
	if DayClock.is_day(hour):
		rack.serve_guests(minutes)

## A new day in the cellar: a day of fermentation in each tun, a day of
## ageing in each bunged cask.
func dawn() -> void:
	for tun: Dictionary in tuns:
		var batch: BrewBatch = tun.batch
		if batch != null and batch.stage == BrewIds.STAGE_PITCHED:
			batch.ferment_day(TEMP, Values.flag(tun.skimmed))
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
	var liters := minf(Values.real(controls.coolship_gate) * GATE_FLOW * minutes, day.coolship_l)
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
	var liters := minf(Values.real(controls["fermenter_tap_%d" % number]) * FERMENTER_TAP * minutes, Values.real(tun.liters))
	if liters <= 0.0:
		return
	tun.liters = Values.real(tun.liters) - liters
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
	var liters := minf(Values.real(controls["lager_tap_%d" % number]) * LAGER_TAP * minutes, Values.real(cask.liters))
	if liters <= 0.0:
		return
	cask.liters = Values.real(cask.liters) - liters
	var batch: BrewBatch = cask.batch
	batch.spill(liters - rack.catch_stream(number, liters, batch))
	_settle_cask(number)

## A cask run dry is empty again: scalded no more, unbunged.
func _settle_cask(number: int) -> void:
	if Values.real(casks[number - 1].liters) < 0.5:
		casks[number - 1] = _empty_cask()

## The cellar bucket tipped into lager cask `number` at `flow` for `minutes`.
## The first beer racks the batch into the cask; a cask holds one batch, and
## a batch goes into one cask. What it will not take is lost.
func fill_cask(number: int, flow: float, minutes: float) -> void:
	var liters := minf(flow * BrewPouring.BUCKET_POUR * minutes, bucket_l)
	if liters <= 0.0 or not sound_cask(number):
		return
	bucket_l -= liters
	var batch := bucket_batch
	var cask := casks[number - 1]
	if cask.batch == null and batch.stage == BrewIds.STAGE_PITCHED:
		cask.batch = batch
		batch.rack(Values.real(cask.scald_l) >= SCALD_L, INF, Values.real(cask.cherries))
	if cask.batch != batch:
		batch.spill(liters)
		return
	var taken := minf(liters, CASK_L - Values.real(cask.liters))
	cask.liters = Values.real(cask.liters) + taken
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
		casks[number - 1].cherries = Values.real(casks[number - 1].cherries) + kg

## `liters` of water at `temp` °C poured through lager cask `number`; while it
## is empty, hot water scalds it.
func scald(number: int, liters: float, temp: float) -> void:
	if sound_cask(number) and Values.real(casks[number - 1].liters) <= 0.0 and temp >= SCALD_TEMP:
		casks[number - 1].scald_l = Values.real(casks[number - 1].scald_l) + liters

func scalded(number: int) -> bool:
	return Values.real(casks[number - 1].scald_l) >= SCALD_L

## `blows` of the mallet on the bung of lager cask `number`, of keg `id`.
func strike_cask(number: int, blows: int) -> void:
	_strike(casks[number - 1], blows)

func strike_keg(id: String, blows: int) -> void:
	if rack.kegs.has(id) and rack.funnel_on != id:
		_strike(Values.table(rack.kegs[id]), blows)

func _strike(vessel: Dictionary, blows: int) -> void:
	if blows <= 0 or Values.real(vessel.liters) <= 0.0:
		return
	vessel.blows = Values.whole(vessel.blows) + blows
	vessel.bunged = Values.whole(vessel.blows) >= BUNG_BLOWS

## A taste of lager cask `number` drawn into the mug: the beer's profile now
## (green while it ages), {} when there is none. It waits in `tasted` too.
func taste(number: int) -> Dictionary:
	var cask := casks[number - 1]
	var batch: BrewBatch = cask.batch
	if batch == null or Values.real(cask.liters) < MUG_L:
		return {}
	cask.liters = Values.real(cask.liters) - MUG_L
	tasted = BrewTaste.profile(batch)
	tasted["cask"] = number
	tasted["days_left"] = maxi(0, batch.ready_days() - batch.age_days)
	_settle_cask(number)
	return tasted

func take_taste() -> Dictionary:
	var taken := tasted
	tasted = {}
	return taken

## Kg of what a cellar utensil holds.
func load_kg(utensil: String) -> float:
	if rack.kegs.has(utensil):
		return Values.real(rack.kegs[utensil].liters)
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
		"kegs": rack.kegs.duplicate(true), "keg_under": rack.keg_under.duplicate(), "funnel_on": rack.funnel_on,
		"tap": rack.tap}
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
			batches.append(BrewBatch.from_dict(Values.table(item)) if item is Dictionary else BrewBatch.new())
	var ref := func(value: Variant) -> BrewBatch:
		var index := int(Values.number(value, -2.0, -2.0, 1e6))
		if index == -1:
			return day_batch
		return batches[index] if index >= 0 and index < batches.size() else null
	var saved_controls: Variant = data.get("controls")
	if saved_controls is Dictionary:
		var control_values: Dictionary = saved_controls
		for id: String in CONTROLS:
			cellar.controls[id] = Values.number(control_values.get(id), Values.real(CONTROLS[id]), 0.0, 1.0)
	cellar.sound_tuns = int(Values.number(data.get("sound_tuns"), START_SOUND_TUNS, START_SOUND_TUNS, TUNS))
	cellar.sound_casks = int(Values.number(data.get("sound_casks"), START_SOUND_CASKS, START_SOUND_CASKS, CASKS))
	var saved_tuns: Variant = data.get("tuns")
	if saved_tuns is Array:
		var tun_list: Array = saved_tuns
		for index in mini(TUNS, tun_list.size()):
			var item: Variant = tun_list[index]
			if not item is Dictionary:
				continue
			var tun: Dictionary = item
			var batch: BrewBatch = ref.call(tun.get("batch"))
			cellar.tuns[index] = {"batch": batch,
				"liters": Values.number(tun.get("liters"), 0.0, 0.0, 2000.0) if batch != null else 0.0,
				"skimmed": tun.get("skimmed") == true, "passes": int(Values.number(tun.get("passes"), 0.0, 0.0, 100.0))}
	cellar.crock_l = Values.number(data.get("crock_l"), CROCK_START, 0.0, CROCK_L)
	cellar.cherries_kg = Values.number(data.get("cherries_kg"), 0.0, 0.0, CHERRY_BASKET_KG)
	cellar.dipper_l = Values.number(data.get("dipper_l"), 0.0, 0.0, DIPPER_L)
	cellar.bucket_batch = ref.call(data.get("bucket"))
	cellar.bucket_l = Values.number(data.get("bucket_l"), 0.0, 0.0, BUCKET_L) if cellar.bucket_batch != null else 0.0
	cellar.bucket_at = str(data.get("bucket_at", "")) if data.get("bucket_at") is String else ""
	var saved_casks: Variant = data.get("casks")
	if saved_casks is Array:
		var cask_list: Array = saved_casks
		for index in mini(CASKS, cask_list.size()):
			var item: Variant = cask_list[index]
			if not item is Dictionary:
				continue
			var cask: Dictionary = item
			var batch: BrewBatch = ref.call(cask.get("batch"))
			cellar.casks[index] = {"batch": batch, "liters": Values.number(cask.get("liters"), 0.0, 0.0, CASK_L) if batch != null else 0.0,
				"scald_l": Values.number(cask.get("scald_l"), 0.0, 0.0, 1e4), "bunged": cask.get("bunged") == true,
				"blows": int(Values.number(cask.get("blows"), 0.0, 0.0, 100.0)),
				"cherries": Values.number(cask.get("cherries"), 0.0, 0.0, CHERRY_BASKET_KG * 4.0)}
	var saved_kegs: Variant = data.get("kegs")
	if saved_kegs is Dictionary:
		var keg_rows: Dictionary = saved_kegs
		for id: String in BrewKegRack.KEGS:
			var item: Variant = keg_rows.get(id)
			if not item is Dictionary:
				continue
			var keg: Dictionary = item
			var beer := _beer(keg.get("beer"))
			var liters := Values.number(keg.get("liters"), 0.0, 0.0, BrewKegRack.KEG_L) if not beer.is_empty() else 0.0
			cellar.rack.kegs[id] = {"liters": liters, "beer": beer, "bunged": keg.get("bunged") == true,
				"blows": int(Values.number(keg.get("blows"), 0.0, 0.0, 100.0))}
	var under: Variant = data.get("keg_under")
	if under is Array:
		for index in mini(CASKS, Values.list(under).size()):
			cellar.rack.keg_under[index] = _keg(under[index])
	cellar.rack.funnel_on = _keg(data.get("funnel_on"))
	cellar.rack.tap = _keg(data.get("tap"))
	if cellar.rack.tap != "" and cellar.rack.set_tap(cellar.rack.tap) != "":
		cellar.rack.tap = ""
	return cellar

## A keg's id read back, "" when it is none of BrewKegRack.KEGS.
static func _keg(value: Variant) -> String:
	return value if value is String and BrewKegRack.KEGS.has(value) else ""

## A keg's beer read back: a profile with the keys the world and the book
## read, else {}.
static func _beer(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var beer: Dictionary = value
	if not beer.get("notes") is Array or not beer.get("flaws") is Array or not beer.get("ruined") is bool:
		return {}
	for key: String in BrewIds.PROFILE_KEYS:
		var number: Variant = beer.get(key)
		if not (number is float or number is int) or not is_finite(Values.real(number)):
			return {}
	return beer
