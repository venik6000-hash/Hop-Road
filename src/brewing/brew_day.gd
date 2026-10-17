class_name BrewDay
extends RefCounted
## The brewing day in the brewery's vessels (docs/plans/brewing.md, section 4,
## from bought malt to the cooling plate): litres and °C in each vessel, the
## fire under the copper, the taps and pumps, the stocks of the utensils, and
## the clock in game minutes. What the brewing makes of it is the batch's:
## this calls the steps of BrewBatch as the liquid runs and counts none of its
## numbers again. What the hand pours from a utensil is BrewPouring's; what
## the instruments read is BrewGauges'. Vessels are the ids of brewery.json's
## `surfaces`.

const COPPER := "copper_wort"
const MASH_TUN := "mash_tun_mash"
const UNDERBACK := "underback_wort"
const HOP_BACK := "hop_back_wort"
const COOLSHIP := "coolship_wort"
## What the sacks hold when full: [kind of MaltLot, kg]; grams in the hop basket.
const SACKS := {BrewIds.SACK_PALE_MALT: [BrewIds.MALT_PALE, 75.0], BrewIds.SACK_CARAMEL_MALT: [BrewIds.MALT_CARAMEL, 25.0],
	BrewIds.SACK_OATS: [BrewIds.MALT_OATS, 25.0], BrewIds.SACK_DARK: [BrewIds.MALT_DARK, 25.0],
	BrewIds.SACK_SMOKED: [BrewIds.MALT_SMOKED, 25.0]}
const HOP_BASKET_G := 3000.0
## Litres the water bucket and the hoist bucket hold; game minutes in which
## hot water in the bucket loses about two thirds of its heat over the air's.
const WATER_BUCKET_L := 12.0
const BUCKET_COOLING := 40.0
const HOIST_BUCKET_L := 50.0
## °C of the spring water in the trough, and of the air in the brewery.
const SPRING_TEMP := 9.0
const AIR_TEMP := 12.0
## Litres a game minute through a tap or cock opened full.
const LIQUOR_COCK := 40.0
const MASH_TAP := 25.0
const COPPER_TAP := 40.0
const HOP_BACK_TAP := 30.0
## Litres a stroke of a pump lifts.
const LIQUOR_STROKE := 15.0
const WORT_STROKE := 10.0
## Fire: kg a log is, the wood that keeps a full fire, the kg an open damper
## burns a game minute, the draught a shut damper leaves.
const LOG_KG := 4.0
const FULL_FUEL := 20.0
const BURN := 0.25
const SHUT_DRAUGHT := 0.35
## °C a game minute full fire gives 400 l in the copper. It loses heat to the
## air so that a fire of BrewBatch.BOILING just holds the boil, whatever it holds.
const HEAT := 2.0
const COPPER_LOSS := BrewBatch.BOILING * HEAT / (100.0 - AIR_TEMP)
const BOIL := 100.0
## The paddle in the copper keeps it stirred this many minutes.
const STIR_MINUTES := 1.0
## Metres the windlass lifts the bucket a turn; the height of the lift.
const LIFT_TURN := 0.5
const LIFT := 3.05
## Kg a full honey pot, juniper bundle and linden bunch hold.
const HONEY_POT_KG := 8.0
const JUNIPER_KG := 2.5
const LINDEN_KG := 0.5
## A fire below this is out: honey and linden then keep their aroma.
const FIRE_OUT := 0.05
## The hand-set controls and where they start: taps, cocks, the damper, the hatch.
const CONTROLS := {"liquor_cock": 0.0, "mash_tap": 0.0, "copper_tap": 0.0, "hop_back_tap": 0.0, "pipe_cock": 1.0,
	"damper": 1.0, "hatch": 0.0}

## The variables a save keeps besides the batch. `capacity` comes from the
## brewery's table and is not kept.
## A key is the name of its variable. tests/test_brew_saves.gd fails when a
## variable is added or renamed without this list; a renamed one needs a step
## in SaveService.MIGRATIONS to carry old saves over.
const SAVED: Array[String] = ["minute", "controls", "copper_l", "copper_temp", "copper_wort", "tun_water_l", "tun_temp",
	"run_l", "tap_peak", "sparge_l", "sparge_heat", "underback_l", "hop_back_l", "coolship_l", "bucket_l", "lift", "hooked",
	"water_bucket_l", "water_bucket_temp", "sacks", "hops_g", "weighed_g", "fuel", "fire", "stirred_at", "hourglass_at",
	"hourglass_up", "fine_thermometer", "full_weights", "honey_kg", "juniper_kg", "linden_kg", "pending_spill",
	"pending_water"]

var batch := BrewBatch.new()
## Litres each vessel holds when full (capacities).
var capacity := {}
var minute := 0.0
var controls := CONTROLS.duplicate()
## The copper: litres, °C, and whether it holds water or wort.
var copper_l := 0.0
var copper_temp := AIR_TEMP
var copper_wort := false
## Water in the mash tun before the grain, litres and °C.
var tun_water_l := 0.0
var tun_temp := AIR_TEMP
## Run-off: litres run from the mash, the widest the tap opened, the sparge
## water poured on since it first opened and its heat (litres × °C).
var run_l := 0.0
var tap_peak := 0.0
var sparge_l := 0.0
var sparge_heat := 0.0
var underback_l := 0.0
var hop_back_l := 0.0
var coolship_l := 0.0
## The hoist bucket: litres in it, its height on the rope, whether it hangs
## on the hook (else a hand carries it or it stands elsewhere).
var bucket_l := 0.0
var lift := 0.0
var hooked := true
var water_bucket_l := 0.0
var water_bucket_temp := SPRING_TEMP
## Kg in each sack (SACKS), grams in the hop basket and on the scales.
var sacks := {}
var hops_g := HOP_BASKET_G
var weighed_g := 0.0
var fuel := 0.0
var fire := 0.0
var stirred_at := -INF
## Game minute the hourglass was turned, -1 never; which end is up.
var hourglass_at := -1.0
var hourglass_up := false
## The precise thermometer and the full set of weights are bought.
var fine_thermometer := false
var full_weights := false
## Kg of honey in its pot, of juniper in the bundle, of linden blossom in the
## bunch (the herbalist's wares).
var honey_kg := 0.0
var juniper_kg := 0.0
var linden_kg := 0.0
## What the batch must still be told when it can take it: wort spilt before
## the run-off was done, water left in the copper under the wort.
var pending_spill := 0.0
var pending_water := 0.0

var _carry := 0.0

func _init() -> void:
	for id: String in SACKS:
		sacks[id] = Values.real(SACKS[id][1])

## Litres each vessel of brewery.json's `surfaces` holds to the brim.
static func capacities(table: Dictionary) -> Dictionary:
	var result := {}
	for entry: Dictionary in table.get("surfaces", []):
		if not entry.has("brim"):
			continue
		var depth := Values.real(entry.brim) - Values.real(entry.bottom)
		var area := 0.0
		if entry.has("radius"):
			area = PI * pow(Values.real(entry.radius), 2.0)
		else:
			var rect: Array = entry.rect
			area = absf((Values.real(rect[1][0]) - Values.real(rect[0][0])) * (Values.real(rect[1][1]) - Values.real(rect[0][1])))
		result[entry.id] = area * depth * 1000.0
	return result

## The game clock moved on `minutes`. Taps run all the time; the fire, the
## heat, the mash's rest, the boil and the cooling go a whole minute at a time.
func advance(minutes: float) -> void:
	_run(minutes)
	_carry += minutes
	while _carry >= 1.0:
		_carry -= 1.0
		_tick()

func _tick() -> void:
	minute += 1.0
	var draught := lerpf(SHUT_DRAUGHT, 1.0, Values.real(controls.damper))
	fire = minf(1.0, fuel / FULL_FUEL) * draught
	fuel = maxf(0.0, fuel - BURN * draught * signf(fuel))
	if copper_l > 1.0:
		copper_temp += (fire * HEAT - COPPER_LOSS * (copper_temp - AIR_TEMP)) * 400.0 / maxf(copper_l, 100.0)
		copper_temp = minf(copper_temp, BOIL)
	else:
		copper_temp = lerpf(copper_temp, AIR_TEMP, 0.05)
	if batch.stage == BrewIds.STAGE_NEW:
		tun_temp -= BrewBatch.TUN_COOLING / 60.0
	elif batch.stage == BrewIds.STAGE_MASH:
		batch.rest(1.0)
	if copper_wort and copper_temp >= BOIL - 0.01 and (batch.stage == BrewIds.STAGE_WORT or batch.stage == BrewIds.STAGE_BOIL):
		var before := batch.volume_l
		batch.boil(1.0, snappedf(fire, 0.1), minute - stirred_at <= STIR_MINUTES)
		copper_l = maxf(0.0, copper_l - (before - batch.volume_l))
	if batch.fire_out and (batch.stage == BrewIds.STAGE_BOIL or batch.stage == BrewIds.STAGE_COOLED):
		batch.cool(1.0 / 60.0, AIR_TEMP)
	water_bucket_temp = AIR_TEMP + (water_bucket_temp - AIR_TEMP) * exp(-1.0 / BUCKET_COOLING)

## The taps over `minutes`.
func _run(minutes: float) -> void:
	var cock := minf(Values.real(controls.liquor_cock) * LIQUOR_COCK * minutes, 0.0 if copper_wort else copper_l)
	if cock > 0.0:
		copper_l -= cock
		into_tun(cock, copper_temp)
	if batch.stage == BrewIds.STAGE_MASH:
		var tap := Values.real(controls.mash_tap)
		var runs := minf(tap * MASH_TAP * minutes, free_wort())
		if tap > 0.0:
			tap_peak = maxf(tap_peak, tap)
		if runs > 0.0:
			run_l += runs
			underback_l += runs
			overflow("underback")
		if run_l > 0.0 and free_wort() <= 0.01:
			_lauter()
	var knock := minf(Values.real(controls.copper_tap) * COPPER_TAP * minutes, copper_l)
	if knock > 0.0:
		copper_l -= knock
		if copper_wort:
			_knock_out()
			hop_back_l += knock
			overflow("hop_back")
	var drawn := minf(Values.real(controls.hop_back_tap) * HOP_BACK_TAP * minutes, hop_back_l)
	if drawn > 0.0:
		hop_back_l -= drawn
		if hooked and lift <= 0.01:
			bucket_l += drawn
			overflow("bucket")
		else:
			spill(drawn)

## Water into the mash tun: before the grain it waits there, in the mash it
## holds the heat, on the run-off it rinses the grain, after it runs away.
func into_tun(liters: float, temp: float) -> void:
	match batch.stage:
		BrewIds.STAGE_NEW:
			tun_temp = (tun_water_l * tun_temp + liters * temp) / maxf(tun_water_l + liters, 0.001)
			tun_water_l += liters
		BrewIds.STAGE_MASH:
			if tap_peak > 0.0:
				sparge_l += liters
				sparge_heat += liters * temp
			else:
				batch.pour(liters, temp)

## Litres still to run from the mash: what the grain does not keep, held back
## as the batch's lauter holds it when the grain is flour.
func free_wort() -> float:
	if batch.stage != BrewIds.STAGE_MASH:
		return 0.0
	var free := batch.mash_l + sparge_l - batch.grain_kg * BrewBatch.GRAIN_KEEPS
	if batch.flour:
		free *= BrewBatch.STUCK_WORT
	return maxf(0.0, free - run_l)

func _lauter() -> void:
	batch.lauter(tap_peak, sparge_l, sparge_heat / sparge_l if sparge_l > 0.0 else 0.0)
	_settle()

## Tells the batch what waited for its wort.
func _settle() -> void:
	if batch.stage == BrewIds.STAGE_WORT or batch.stage == BrewIds.STAGE_BOIL or batch.stage == BrewIds.STAGE_COOLED:
		batch.spill(pending_spill)
		batch.water_down(pending_water)
		pending_spill = 0.0
		pending_water = 0.0

## The first wort out of the copper ends its boil.
func _knock_out() -> void:
	if batch.stage == BrewIds.STAGE_WORT:
		batch.boil(0.0, 0.0, false)
	batch.draw_fire()

## Wort lost on the floor; the batch is told once it can take it.
func spill(liters: float) -> void:
	pending_spill += liters
	_settle()

## What `vessel` ("underback", "hop_back", "bucket" for the hoist bucket,
## "coolship") holds over its brim runs onto the floor.
func overflow(vessel: String) -> void:
	match vessel:
		"underback":
			var over := underback_l - Values.real(capacity.get(UNDERBACK, INF))
			if over > 0.0:
				underback_l -= over
				spill(over)
		"hop_back":
			var over := hop_back_l - Values.real(capacity.get(HOP_BACK, INF))
			if over > 0.0:
				hop_back_l -= over
				spill(over)
		"bucket":
			var over := bucket_l - HOIST_BUCKET_L
			if over > 0.0:
				bucket_l -= over
				spill(over)
		"coolship":
			var over := coolship_l - Values.real(capacity.get(COOLSHIP, INF))
			if over > 0.0:
				coolship_l -= over
				spill(over)

## A tap or cock, the damper or the hatch set to `amount` (0..1).
func set_control(id: String, amount: float) -> void:
	if controls.has(id):
		controls[id] = clampf(amount, 0.0, 1.0)

## `strokes` of the liquor pump: spring water into the copper, or back into
## the trough with the pipe's cock shut.
func pump_liquor(strokes: int) -> void:
	if strokes <= 0 or Values.real(controls.pipe_cock) < 0.5:
		return
	into_copper(minf(strokes * LIQUOR_STROKE, Values.real(capacity.get(COPPER, INF)) - copper_l), SPRING_TEMP)

## Water into the copper; under the wort it thins it.
func into_copper(liters: float, temp: float) -> void:
	if liters <= 0.0:
		return
	copper_temp = (copper_l * copper_temp + liters * temp) / (copper_l + liters)
	copper_l += liters
	if copper_wort:
		pending_water += liters
		_settle()

## `strokes` of the wort pump: the underback into the copper. Water left in
## the copper thins the wort.
func pump_wort(strokes: int) -> void:
	var liters := minf(strokes * WORT_STROKE, underback_l)
	if liters <= 0.0:
		return
	underback_l -= liters
	if not copper_wort and copper_l > 0.0:
		pending_water += copper_l
	copper_wort = true
	copper_temp = (copper_l * copper_temp + liters * batch.mash_temp) / (copper_l + liters)
	copper_l += liters
	_settle()

## A log into the firebox.
func stoke() -> void:
	fuel = minf(fuel + LOG_KG, FULL_FUEL * 1.5)

## Lots of grain into the mash tun: the first mash the batch in, the next
## are stirred into the mash. Grain that was never milled gives nothing.
func pour_lots(lots: Array[MaltLot]) -> void:
	if lots.is_empty():
		return
	if batch.stage == BrewIds.STAGE_NEW:
		batch.mash_in(lots, tun_water_l, tun_temp)
		tun_water_l = 0.0
	else:
		batch.add_grain(lots)

## The paddle `turns` round the mash tun.
func stir_mash(turns: int) -> void:
	if turns != 0:
		batch.stir(absi(turns))

## The paddle round the copper.
func stir_copper() -> void:
	stirred_at = minute

## The windlass turned `turns` (signed, up is plus): the bucket on its hook
## goes up or down.
func wind(turns: float) -> void:
	if hooked:
		lift = clampf(lift + turns * LIFT_TURN, 0.0, LIFT)

## The hoist bucket taken off its hook, or hung on it at the floor or at the top.
func hang_bucket(on: bool, at_top := false) -> void:
	hooked = on
	if on:
		lift = LIFT if at_top else 0.0

func turn_hourglass() -> void:
	hourglass_at = minute
	hourglass_up = not hourglass_up

## Kg of what a carried thing holds.
func load_kg(utensil: String) -> float:
	if SACKS.has(utensil):
		return Values.real(sacks[utensil])
	match utensil:
		"water_bucket":
			return water_bucket_l
		"hoist_bucket":
			return bucket_l
		"hop_basket":
			return (hops_g + weighed_g) / 1000.0
		"honey_pot":
			return honey_kg
		"juniper_bundle":
			return juniper_kg
		"linden_bunch":
			return linden_kg
	return 0.0

## Litres of the batch's wort still in the brewery's vessels and buckets.
func wort_left() -> float:
	return underback_l + hop_back_l + bucket_l + coolship_l + (copper_l if copper_wort else 0.0)

## The wort has left the cooling plate for the cellar: the brewery is free
## for a new batch. What is left of the old wort in the other vessels runs away.
func hand_over() -> void:
	batch = BrewBatch.new()
	if copper_wort:
		copper_l = 0.0
		copper_temp = AIR_TEMP
	copper_wort = false
	for vessel: String in ["run_l", "tap_peak", "sparge_l", "sparge_heat", "underback_l", "hop_back_l", "coolship_l",
			"bucket_l", "pending_spill", "pending_water"]:
		set(vessel, 0.0)
	tun_water_l = 0.0
	tun_temp = AIR_TEMP

## The day as plain data for a save: the batch and the variables of SAVED.
func to_dict() -> Dictionary:
	var data := {"batch": batch.to_dict()}
	for key: String in SAVED:
		data[key] = get(key)
	data.stirred_at = maxf(stirred_at, -1e6)
	return data

## A day read back from to_dict() through JSON; what is missing or wrong keeps
## the start's.
static func from_dict(data: Dictionary, vessel_capacity: Dictionary) -> BrewDay:
	var day := BrewDay.new()
	day.capacity = vessel_capacity
	var saved: Variant = data.get("batch")
	if saved is Dictionary:
		day.batch = BrewBatch.from_dict(Values.table(saved))
	for key: String in SAVED:
		if not data.has(key):
			continue
		var value: Variant = data[key]
		match typeof(day.get(key)):
			TYPE_FLOAT:
				if (value is float or value is int) and is_finite(Values.real(value)):
					day.set(key, maxf(Values.real(value), -1e6))
			TYPE_BOOL:
				if value is bool:
					day.set(key, value)
			TYPE_DICTIONARY:
				if value is Dictionary:
					var given: Dictionary = value
					var into: Dictionary = day.get(key)
					for name: Variant in into:
						var number: Variant = given.get(name)
						if (number is float or number is int) and is_finite(Values.real(number)):
							into[name] = Values.real(number)
	return day
