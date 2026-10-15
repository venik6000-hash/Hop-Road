class_name BrewBatch
extends RefCounted
## One batch from the mash to the lager barrel (docs/plans/brewing.md,
## section 4), and what it tastes like (profile). Each step is a call in the
## order of the brewing day; a step out of order does nothing. A mistake adds
## a flaw id, the cause is in assets/brewing/flaws.json. `journal` keeps each step
## with its numbers for the brewer's book.

## Every flaw a batch can have; those of RUINS spoil it.
const FLAWS: Array[String] = ["sleepy_grain", "mould", "overgrown", "damp_malt", "burnt", "acrid_smoke",
	"flour", "coarse_grind", "thin", "watery", "clumps", "murky", "boilover", "scorched", "sour_wort",
	"dead_yeast", "warm_ferment", "muddy_head", "sour_barrel", "green"]
const RUINS: Array[String] = ["dead_yeast", "sour_barrel"]

## Heat the grain holds against water's 1, and its °C when it goes in.
const GRAIN_HEAT := 0.4
const GRAIN_TEMP := 12.0
## °C a wooden tun loses an hour.
const TUN_COOLING := 4.0
## °C at which the mash enzymes die.
const ENZYMES_DIE := 78.0
## Conversion speed an unstirred minute at a mash °C, as [°C, rate] points.
const CONVERSION := [[50.0, 0.002], [60.0, 0.02], [65.0, 0.05], [70.0, 0.07], [75.0, 0.05], [ENZYMES_DIE, 0.0]]
## The part of the sugar yeast can eat that a mash °C makes.
const FERMENTABLE := [[55.0, 0.85], [63.0, 0.84], [66.0, 0.80], [68.0, 0.72], [70.0, 0.66], [74.0, 0.60]]
## Below this conversion the wort is thin; clumps above CLUMPS stay.
const CONVERTED := 0.85
const CLUMPS := 0.3
## A stir turn leaves this part of the clumps; oats stick and halve the turn.
const STIR_LEAVES := 0.8
## Turns of the paddle oats need for a creamy body.
const OATS_STIRS := 40
## Litres of wort a kg of spent grain keeps; sparge litres a kg to rinse it;
## sparge °C below which the rinse is weak.
const GRAIN_KEEPS := 1.0
const RINSE := 2.0
const HOT_SPARGE := 70.0
## A tap opened wider than this stirs up the bed.
const RUSHED_TAP := 0.7
## What flour lets through a stuck bed: extract and wort.
const STUCK_EXTRACT := 0.6
const STUCK_WORT := 0.7
## Boil: the fire that keeps a rolling boil, a strong fire, the part of the
## wort an hour of full fire boils off.
const BOILING := 0.3
const STRONG := 0.75
const EVAPORATION := 0.1
## A fire at FOAM in the first FOAM_MINUTES of the boil, unstirred, boils over;
## SCORCH unstirred minutes of strong fire burn the bottom.
const FOAM := 0.85
const FOAM_MINUTES := 15.0
const SCORCH := 30.0
## Minutes of strong boil that caramelize the wort.
const LONG_BOIL := 100.0
## Hop alpha acid, the utilization of a long boil and its speed (Tinseth),
## and the minutes before the end from which hops give aroma.
const HOP_ALPHA := 0.04
const HOP_USE := 0.275
const HOP_SPEED := 0.04
const LATE_HOPS := 15.0
## Extract a kg of honey or cherries gives.
const HONEY_EXTRACT := 0.8
const CHERRY_EXTRACT := 0.1
## Cooling: hours the plate takes to bring 400 l a step of e closer to the air;
## the °C where wort sours, and the hours there that sour it.
const COOL_HOURS := 1.5
const SOUR_LOW := 20.0
const SOUR_HIGH := 50.0
const SOUR_HOURS := 3.0
## Honey and linden blossom steep in the wort after the fire down to this °C.
const STEEP_TEMP := 75.0
## Yeast dies above YEAST_DIES °C; litres of yeast for 100 l of wort.
const YEAST_DIES := 35.0
const YEAST_PER_100 := 0.5
## A day of fermentation at the cellar °C, as [°C, part of the work] points;
## a cellar above WARM °C gives a hot taste.
const FERMENT_DAY := [[6.0, 0.12], [10.0, 0.22], [14.0, 0.3], [20.0, 0.4]]
const WARM := 20.0
## The day by which the yeast head must have been skimmed.
const SKIM_BY := 2
## Days in the lager barrel before it is ready; with cherries.
const AGE_DAYS := 7
const CHERRY_AGE_DAYS := 14
## Signature amounts: what makes a note heard in the beer.
const OATS_NOTE := 0.2
const CARAMEL_NOTE := 1.0
const SMOKE_NOTE := 0.15
const HOPS_NOTE := 0.5
const JUNIPER_NOTE := 0.004
const HONEY_NOTE := 0.015
const LINDEN_NOTE := 0.001
const CHERRY_NOTE := 0.05

## The stages of a batch in their order.
const STAGES: Array[String] = ["new", "mash", "wort", "boil", "cooled", "pitched", "barrel"]
## Steps whose runs the journal keeps as one line: these numbers are summed,
## the others are the last step's. A boil at another fire starts a new line.
const RUNS := {"rest": ["minutes"], "boil": ["minutes"], "cool": ["hours"], "grain": ["kg"], "pour": ["liters"],
	"spill": ["liters"], "water_down": ["liters"], "pitch": ["yeast_l"]}

## One of STAGES.
var stage := "new"
var journal: Array[Dictionary] = []
var flaws: Array[String] = []

var juniper_kg := 0.0
var grain_kg := 0.0
var oats_kg := 0.0
var caramel_kg := 0.0
var smoke_points := 0.0
var oats_share := 0.0
var caramel_share := 0.0
var color_points := 0.0
var smoke := 0.0
var flour := false
## Extract the grain holds, kg.
var grain_extract := 0.0

var mash_l := 0.0
var mash_temp := 0.0
var conversion := 0.0
## Conversion weighted by the fermentability of the °C it happened at.
var fermentable_sum := 0.0
var clumps := 1.0
var stir_turns := 0
var enzymes_dead := false

## Wort: litres, kg of malt extract and of honey and cherry sugar, haze 0..1.
var volume_l := 0.0
var malt_extract := 0.0
var sugar_extract := 0.0
var haze := 0.0

var boil_minutes := 0.0
var strong_minutes := 0.0
var unstirred_strong := 0.0
## Hop additions: {grams, at} where `at` is the boil minute they went in.
var hops: Array[Dictionary] = []
var fire_out := false
var honey_kg := 0.0
var linden_kg := 0.0

var wort_temp := 100.0
var sour_hours := 0.0

## Litres of live yeast pitched, and the part of what the wort needs they are.
var yeast_l := 0.0
var yeast_rate := 0.0
var ferment := 0.0
var ferment_days := 0
var skimmed := false

var cherries_kg := 0.0
var age_days := 0
## Litres of beer lost after the yeast went in.
var lost_l := 0.0

func _flaw(id: String) -> void:
	if not flaws.has(id):
		flaws.append(id)

func _note(step: String, numbers: Dictionary) -> void:
	var entry := {"step": step}
	entry.merge(numbers)
	if RUNS.has(step) and not journal.is_empty():
		var last: Dictionary = journal[journal.size() - 1]
		if last.step == step and last.get("fire") == entry.get("fire"):
			for key: String in RUNS[step]:
				entry[key] = float(last[key]) + float(entry[key])
			journal[journal.size() - 1] = entry
			return
	journal.append(entry)

## Value of [x, y] points at x, held flat past the ends.
static func curve(points: Array, x: float) -> float:
	var first: Array = points[0]
	if x <= float(first[0]):
		return float(first[1])
	for index in range(1, points.size()):
		var low: Array = points[index - 1]
		var high: Array = points[index]
		if x <= float(high[0]):
			return lerpf(float(low[1]), float(high[1]), (x - float(low[0])) / (float(high[0]) - float(low[0])))
	var last: Array = points[points.size() - 1]
	return float(last[1])

## Lays juniper branches on the bottom of the mash tun.
func line_tun(kg: float) -> void:
	if stage == "new":
		juniper_kg += kg
		_note("line_tun", {"kg": kg})

## Puts the milled lots into `water_l` of water at `water_temp` °C.
func mash_in(lots: Array[MaltLot], water_l: float, water_temp: float) -> void:
	if stage != "new" or lots.is_empty():
		return
	_take_grain(lots)
	mash_l = 0.0
	mash_temp = GRAIN_TEMP
	stage = "mash"
	_pour(water_l, water_temp)
	_note("mash_in", {"grain_kg": grain_kg, "water_l": water_l, "water_temp": water_temp, "mash_temp": mash_temp})

## More milled grain into the mash: it comes in cold, at GRAIN_TEMP.
func add_grain(lots: Array[MaltLot]) -> void:
	if stage != "mash" or lots.is_empty():
		return
	var mass := grain_kg * GRAIN_HEAT + mash_l
	var before := grain_kg
	_take_grain(lots)
	var added := (grain_kg - before) * GRAIN_HEAT
	mash_temp = (mass * mash_temp + added * GRAIN_TEMP) / maxf(mass + added, 0.001)
	# Grain poured on with nothing done between but the rest is still the
	# mashing in.
	for index in range(journal.size() - 1, -1, -1):
		var entry: Dictionary = journal[index]
		if entry.step == "mash_in":
			entry.grain_kg = grain_kg
			entry.mash_temp = mash_temp
			return
		if entry.step != "rest":
			break
	_note("grain", {"kg": grain_kg - before, "mash_temp": mash_temp})

func _take_grain(lots: Array[MaltLot]) -> void:
	for lot: MaltLot in lots:
		grain_kg += lot.kg
		grain_extract += lot.extract()
		color_points += lot.kg * lot.color
		smoke_points += lot.kg * lot.smoke
		oats_kg += lot.kg if lot.kind == "oats" else 0.0
		caramel_kg += lot.kg if lot.kind == "caramel" else 0.0
		flour = flour or lot.flaws.has("flour")
		for id: String in lot.flaws:
			if id != "flour":
				_flaw(id)
	if grain_kg > 0.0:
		oats_share = oats_kg / grain_kg
		caramel_share = caramel_kg / grain_kg
		smoke = smoke_points / grain_kg

func _pour(liters: float, temp: float) -> void:
	var mass := grain_kg * GRAIN_HEAT + mash_l
	mash_temp = (mass * mash_temp + liters * temp) / (mass + liters)
	mash_l += liters
	if mash_temp >= ENZYMES_DIE:
		enzymes_dead = true

## Pours boiling or spring water into the mash to hold its heat.
func pour(liters: float, temp: float) -> void:
	if stage == "mash":
		_pour(liters, temp)
		_note("pour", {"liters": liters, "temp": temp, "mash_temp": mash_temp})

## Turns the paddle round the tun `turns` times.
func stir(turns: int) -> void:
	if stage != "mash":
		return
	clumps *= pow(STIR_LEAVES, turns * (1.0 - 0.5 * oats_share))
	stir_turns += turns

## The mash rests `minutes`, cooling in the wooden tun.
func rest(minutes: float) -> void:
	if stage != "mash":
		return
	for _minute in int(round(minutes)):
		var rate := 0.0 if enzymes_dead else curve(CONVERSION, mash_temp) * (1.0 - 0.5 * clumps)
		var gained := (1.0 - conversion) * rate
		conversion += gained
		fermentable_sum += gained * curve(FERMENTABLE, mash_temp)
		mash_temp -= TUN_COOLING / 60.0
	_note("rest", {"minutes": minutes, "mash_temp": mash_temp, "conversion": conversion})

## Runs the wort off through the tap opened to `tap` (0..1) and rinses the
## grain with `sparge_l` of water at `sparge_temp` °C.
func lauter(tap: float, sparge_l: float, sparge_temp: float) -> void:
	if stage != "mash":
		return
	if conversion < CONVERTED:
		_flaw("watery" if enzymes_dead else "thin")
	if clumps > CLUMPS:
		_flaw("clumps")
	var sugar := grain_extract * conversion * (1.0 - 0.5 * clumps)
	var kept := grain_kg * GRAIN_KEEPS
	var first := clampf((mash_l - kept) / mash_l, 0.0, 1.0)
	var rinse := 1.0 - exp(-sparge_l / (grain_kg * RINSE))
	if sparge_temp < HOT_SPARGE:
		rinse *= 0.8
	malt_extract = sugar * (first + (1.0 - first) * rinse)
	volume_l = maxf(0.0, mash_l + sparge_l - kept)
	if flour:
		_flaw("flour")
		malt_extract *= STUCK_EXTRACT
		volume_l *= STUCK_WORT
	if tap > RUSHED_TAP:
		_flaw("murky")
		haze += 0.3
	stage = "wort"
	_note("lauter", {"tap": tap, "sparge_l": sparge_l, "volume_l": volume_l, "extract_kg": malt_extract})

## The kettle over `fire` (0..1) for `minutes`, the paddle going or not.
func boil(minutes: float, fire: float, stirring: bool) -> void:
	if stage == "wort":
		stage = "boil"
	if stage != "boil" or fire_out:
		return
	if fire >= FOAM and boil_minutes < FOAM_MINUTES and not stirring:
		_flaw("boilover")
		volume_l *= 0.95
	if fire >= BOILING:
		boil_minutes += minutes
	if fire >= STRONG:
		strong_minutes += minutes
		if not stirring:
			unstirred_strong += minutes
			if unstirred_strong > SCORCH:
				_flaw("scorched")
	volume_l *= 1.0 - EVAPORATION * fire * minutes / 60.0
	_note("boil", {"minutes": minutes, "fire": fire, "volume_l": volume_l})

## Wort or beer lost on the floor: a tun, a bucket or a keg run over, a
## bucket spilt, a tap left open over nothing.
## Lost beer leaves what is left as it was: only the wort's litres count down.
func spill(liters: float) -> void:
	if liters <= 0.0:
		return
	if stage == "wort" or stage == "boil" or stage == "cooled":
		volume_l = maxf(0.0, volume_l - liters)
	elif stage == "pitched" or stage == "barrel":
		lost_l += liters
	else:
		return
	_note("spill", {"liters": liters, "beer": stage == "pitched" or stage == "barrel"})

## Water left in the kettle thins the wort run onto it.
func water_down(liters: float) -> void:
	if liters > 0.0 and (stage == "wort" or stage == "boil"):
		volume_l += liters
		_note("water_down", {"liters": liters})

## Hops from the scales into the kettle.
func add_hops(grams: float) -> void:
	if stage == "boil" or stage == "wort":
		hops.append({"grams": grams, "at": boil_minutes})
		_note("hops", {"grams": grams, "at": boil_minutes})

## Takes the fire from under the kettle: the boil is over.
func draw_fire() -> void:
	if stage == "boil":
		fire_out = true
		_note("draw_fire", {"boil_minutes": boil_minutes})

## Honey into the kettle; its aroma lives only when the fire is drawn. After
## the fire it goes into the wort while the wort is hot enough to steep it.
func add_honey(kg: float) -> void:
	if stage != "boil" and not steeps():
		return
	sugar_extract += kg * HONEY_EXTRACT
	if fire_out:
		honey_kg += kg
	_note("honey", {"kg": kg, "fire_out": fire_out})

func add_linden(kg: float) -> void:
	if (stage == "boil" and fire_out) or steeps():
		linden_kg += kg
		_note("linden", {"kg": kg})

## The fire is drawn and the wort is still hot enough to steep honey and
## blossom in it.
func steeps() -> bool:
	return fire_out and stage == "cooled" and wort_temp >= STEEP_TEMP

## The wort on the cooling plate or in the fermenting tun `hours` in air at
## `air_temp` °C. It goes on cooling with each call until the first day of
## fermentation.
func cool(hours: float, air_temp: float) -> void:
	if stage != "boil" and stage != "cooled" and not (stage == "pitched" and ferment_days == 0):
		return
	fire_out = true
	var span := COOL_HOURS * maxf(volume_l, 1.0) / 400.0
	var spent := 0.0
	while spent < hours:
		var step := minf(0.1, hours - spent)
		wort_temp = air_temp + (wort_temp - air_temp) * exp(-step / span)
		if wort_temp > SOUR_LOW and wort_temp < SOUR_HIGH:
			sour_hours += step
		spent += step
	if sour_hours > SOUR_HOURS:
		_flaw("sour_wort")
	if stage != "pitched":
		stage = "cooled"
	_note("cool", {"hours": hours, "air_temp": air_temp, "wort_temp": wort_temp})

## Yeast into the wort in the fermenting tun, a dipper at a time until the
## first day of fermentation. Yeast poured into wort above YEAST_DIES °C dies.
func pitch(liters: float) -> void:
	if stage != "cooled" and not (stage == "pitched" and ferment_days == 0):
		return
	if wort_temp <= YEAST_DIES:
		yeast_l += liters
	yeast_rate = clampf(yeast_l / (YEAST_PER_100 * maxf(volume_l, 1.0) / 100.0), 0.0, 1.0)
	stage = "pitched"
	_note("pitch", {"yeast_l": liters, "wort_temp": wort_temp, "died": wort_temp > YEAST_DIES})

## A day of fermentation in the cellar at `cellar_temp` °C; `skim` takes the
## yeast head off.
func ferment_day(cellar_temp: float, skim: bool) -> void:
	if stage != "pitched":
		return
	if yeast_rate <= 0.0:
		_flaw("dead_yeast")
	ferment_days += 1
	skimmed = skimmed or skim
	ferment = minf(1.0, ferment + curve(FERMENT_DAY, cellar_temp) * (0.5 + 0.5 * yeast_rate) * signf(yeast_rate))
	if cellar_temp > WARM and ferment < 1.0:
		_flaw("warm_ferment")
	if ferment_days >= SKIM_BY and not skimmed:
		_flaw("muddy_head")
	_note("ferment_day", {"cellar_temp": cellar_temp, "skim": skim, "ferment": ferment})

## Runs the beer into the lager barrel of `capacity_l`, scalded or not, with
## `cherries_kg` of cherries in it.
func rack(scalded: bool, capacity_l: float, cherries: float) -> void:
	if stage != "pitched":
		return
	if not scalded:
		_flaw("sour_barrel")
	var spilled := maxf(0.0, volume_l - capacity_l)
	volume_l -= spilled
	cherries_kg = cherries
	sugar_extract += cherries * CHERRY_EXTRACT
	stage = "barrel"
	_note("rack", {"scalded": scalded, "spilled_l": spilled, "cherries_kg": cherries})

func age_day() -> void:
	if stage == "barrel":
		age_days += 1

func ready_days() -> int:
	return CHERRY_AGE_DAYS if cherries_kg > 0.0 else AGE_DAYS

## Strength of a wort of `extract` kg in `liters`, degrees Plato.
static func plato(extract: float, liters: float) -> float:
	return 0.0 if liters <= 0.0 else 100.0 * extract / (liters + extract)

## IBU of the hops after `minutes` total of boil.
func bitterness() -> float:
	var total := 0.0
	for addition: Dictionary in hops:
		var grams: float = addition.grams
		var at: float = addition.at
		var boiled := maxf(0.0, boil_minutes - at)
		total += grams * HOP_ALPHA * 1000.0 * HOP_USE * (1.0 - exp(-HOP_SPEED * boiled)) / maxf(volume_l, 1.0)
	return total

func _added_late(at: float) -> bool:
	return boil_minutes - at <= LATE_HOPS

## Hops grams a litre added in the last LATE_HOPS minutes or after the fire.
func hop_aroma() -> float:
	var grams := 0.0
	for addition: Dictionary in hops:
		var at: float = addition.at
		if _added_late(at):
			var weight: float = addition.grams
			grams += weight
	return grams / maxf(volume_l, 1.0)

## What the batch tastes like now: {strength (% ABV), gravity (°P), body,
## sweetness, bitterness (IBU), aroma (late hops g/l), color (EBC), clarity,
## smoke, foam (0..1), notes, flaws, ruined, quality (0..1)}.
func profile() -> Dictionary:
	var extract := malt_extract + sugar_extract
	var gravity := plato(extract, volume_l)
	var fermentable := 0.0 if conversion <= 0.0 else fermentable_sum / conversion
	var eaten := 0.0 if extract <= 0.0 else (malt_extract * fermentable + sugar_extract) * ferment / extract
	var rest_gravity := gravity * (1.0 - eaten)
	var oats_body := oats_share * 4.0 * minf(1.0, float(stir_turns) / OATS_STIRS)
	var ibu := bitterness()
	var caramel := caramel_share * 5.0 + (0.5 if strong_minutes >= LONG_BOIL else 0.0)
	var mcu := color_points / maxf(volume_l, 1.0) * 7.0 + (5.0 if strong_minutes >= LONG_BOIL else 0.0)
	var taste: Array[String] = flaws.duplicate()
	if stage == "barrel" and age_days < ready_days():
		taste.append("green")
	var notes: Array[String] = []
	var per_l := 1.0 / maxf(volume_l, 1.0)
	if hop_aroma() >= HOPS_NOTE:
		notes.append("hops")
	if oats_share >= OATS_NOTE and stir_turns >= OATS_STIRS:
		notes.append("oats")
	if caramel >= CARAMEL_NOTE:
		notes.append("caramel")
	if smoke >= SMOKE_NOTE:
		notes.append("smoke")
	if juniper_kg * per_l >= JUNIPER_NOTE:
		notes.append("juniper")
	if honey_kg * per_l >= HONEY_NOTE:
		notes.append("honey")
	if linden_kg * per_l >= LINDEN_NOTE:
		notes.append("linden")
	if cherries_kg * per_l >= CHERRY_NOTE:
		notes.append("cherry")
	var ruined := false
	for id: String in RUINS:
		ruined = ruined or taste.has(id)
	var clarity := clampf(0.4 + 0.06 * age_days, 0.0, 1.0) - haze - (0.2 if flour else 0.0) - 0.3 * oats_share
	return {
		"strength": gravity * eaten * 0.5,
		"gravity": gravity,
		"body": rest_gravity + oats_body,
		"sweetness": rest_gravity + caramel_share * 8.0,
		"bitterness": ibu,
		"aroma": hop_aroma(),
		"color": 300.0 * (1.0 - exp(-mcu / 300.0)),
		"clarity": clampf(clarity, 0.0, 1.0),
		"smoke": smoke,
		"foam": clampf(0.55 + 0.6 * oats_share + 0.5 * caramel_share + (0.1 if ibu > 20.0 else 0.0), 0.0, 1.0),
		"notes": notes,
		"flaws": taste,
		"ruined": ruined,
		"quality": 0.0 if ruined else maxf(0.0, 1.0 - 0.15 * taste.size()),
	}

## The batch as plain data for a save (every variable of the script).
func to_dict() -> Dictionary:
	var data := {}
	for property: Dictionary in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			data[property.name] = get(property.name)
	return data

## A batch read back from to_dict(), through JSON. A value that is missing or
## of another kind keeps the start's; an unknown stage reads as "new".
static func from_dict(data: Dictionary) -> BrewBatch:
	var batch := BrewBatch.new()
	for property: Dictionary in batch.get_property_list():
		var key: String = property.name
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or not data.has(key):
			continue
		var value: Variant = data[key]
		var number := (value is float or value is int) and is_finite(float(value))
		var current: Variant = batch.get(key)
		match typeof(current):
			TYPE_FLOAT:
				if number:
					batch.set(key, float(value))
			TYPE_INT:
				if number:
					batch.set(key, int(value))
			TYPE_BOOL, TYPE_STRING:
				if typeof(value) == typeof(current):
					batch.set(key, value)
			TYPE_ARRAY:
				if value is Array:
					var kind := (current as Array).get_typed_builtin()
					(current as Array).assign((value as Array).filter(func(item: Variant) -> bool: return typeof(item) == kind))
	if not STAGES.has(batch.stage):
		batch.stage = "new"
	return batch
