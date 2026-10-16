class_name BrewDay
extends RefCounted
## The brewing day in the brewery's vessels (docs/plans/brewing.md, section 4,
## from bought malt to the cooling plate): litres and °C in each vessel, the
## fire under the copper, the taps, pumps and hand pours, and the clock in
## game minutes. What the brewing makes of it is the batch's: this calls the
## steps of BrewBatch as the liquid runs and counts none of its numbers again.
## Vessels are the ids of brewery.json's `surfaces`.

const COPPER := "copper_wort"
const MASH_TUN := "mash_tun_mash"
const UNDERBACK := "underback_wort"
const HOP_BACK := "hop_back_wort"
const COOLSHIP := "coolship_wort"
## What each vessel is called.
const TITLES := {COPPER: "Котёл", MASH_TUN: "Заторный чан", UNDERBACK: "Приёмный чан", HOP_BACK: "Хмелецедильный чан",
	COOLSHIP: "Холодильная тарелка"}
## Each vessel read empty: whole keys of the table, the word "empty" agrees
## with the title.
const EMPTY := {COPPER: "Котёл пуст", MASH_TUN: "Заторный чан пуст", UNDERBACK: "Приёмный чан пуст",
	HOP_BACK: "Хмелецедильный чан пуст", COOLSHIP: "Холодильная тарелка пуста"}
## What the sacks hold when full: [kind of MaltLot, kg]; grams in the hop basket.
const SACKS := {BrewIds.SACK_PALE_MALT: ["pale", 75.0], BrewIds.SACK_CARAMEL_MALT: ["caramel", 25.0],
	BrewIds.SACK_OATS: ["oats", 25.0], BrewIds.SACK_DARK: ["dark", 25.0], BrewIds.SACK_SMOKED: ["smoked", 25.0]}
const HOP_BASKET_G := 3000.0
## Malt from the mill shop comes crushed at this gap (MaltLot.mill).
const SHOP_GAP := 0.35
## Litres the water bucket and the hoist bucket hold; game minutes in which
## hot water in the bucket loses about two thirds of its heat over the air's.
const WATER_BUCKET_L := 12.0
const BUCKET_COOLING := 40.0
const HOIST_BUCKET_L := 50.0
## °C of the spring water in the trough, and of the air in the brewery.
const SPRING_TEMP := 9.0
const AIR_TEMP := 12.0
## Litres of room a kg of grain takes in the mash.
const GRAIN_BULK := 0.7
## What a full pour gives a game minute: kg of grain from a sack, litres from
## a bucket, grams of hops onto the scales.
const GRAIN_POUR := 30.0
const BUCKET_POUR := 40.0
const HOPS_WEIGH := 600.0
## Grams of hops a throw takes when none were weighed.
const HANDFUL := 60.0
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
## Game minutes the sand of the hourglass runs.
const HOURGLASS := 60.0
## Kg a full honey pot, juniper bundle and linden bunch hold.
const HONEY_POT_KG := 8.0
const JUNIPER_KG := 2.5
const LINDEN_KG := 0.5
## Kg a game minute of the honey pot tipped full; of juniper laid in the tun
## at a full tilt; kg of linden blossom a throw.
const HONEY_POUR := 4.0
const JUNIPER_LAY := 2.0
const LINDEN_THROW := 0.25
## A fire below this is out: honey and linden then keep their aroma.
const FIRE_OUT := 0.05
## °C between the marks of the brewery's thermometer and of the precise one
## from the market; grams of the smallest weight of the scales' old set and
## of the full one (BrewTrade).
const THERMO_STEP := 2.0
const FINE_THERMO_STEP := 0.5
const WEIGHT_STEP := 100.0
const FINE_WEIGHT_STEP := 10.0
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
		sacks[id] = float(SACKS[id][1])

## Litres each vessel of brewery.json's `surfaces` holds to the brim.
static func capacities(table: Dictionary) -> Dictionary:
	var result := {}
	for entry: Dictionary in table.get("surfaces", []):
		if not entry.has("brim"):
			continue
		var depth := float(entry.brim) - float(entry.bottom)
		var area := 0.0
		if entry.has("radius"):
			area = PI * pow(float(entry.radius), 2.0)
		else:
			var rect: Array = entry.rect
			area = absf((float(rect[1][0]) - float(rect[0][0])) * (float(rect[1][1]) - float(rect[0][1])))
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
	var draught := lerpf(SHUT_DRAUGHT, 1.0, float(controls.damper))
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
	var cock := minf(float(controls.liquor_cock) * LIQUOR_COCK * minutes, 0.0 if copper_wort else copper_l)
	if cock > 0.0:
		copper_l -= cock
		_into_tun(cock, copper_temp)
	if batch.stage == BrewIds.STAGE_MASH:
		var tap := float(controls.mash_tap)
		var runs := minf(tap * MASH_TAP * minutes, free_wort())
		if tap > 0.0:
			tap_peak = maxf(tap_peak, tap)
		if runs > 0.0:
			run_l += runs
			underback_l += runs
			_overflow("underback")
		if run_l > 0.0 and free_wort() <= 0.01:
			_lauter()
	var knock := minf(float(controls.copper_tap) * COPPER_TAP * minutes, copper_l)
	if knock > 0.0:
		copper_l -= knock
		if copper_wort:
			_knock_out()
			hop_back_l += knock
			_overflow("hop_back")
	var drawn := minf(float(controls.hop_back_tap) * HOP_BACK_TAP * minutes, hop_back_l)
	if drawn > 0.0:
		hop_back_l -= drawn
		if hooked and lift <= 0.01:
			bucket_l += drawn
			_overflow("bucket")
		else:
			_spill(drawn)

## Water into the mash tun: before the grain it waits there, in the mash it
## holds the heat, on the run-off it rinses the grain, after it runs away.
func _into_tun(liters: float, temp: float) -> void:
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

func _spill(liters: float) -> void:
	pending_spill += liters
	_settle()

func _overflow(vessel: String) -> void:
	match vessel:
		"underback":
			var over := underback_l - float(capacity.get(UNDERBACK, INF))
			if over > 0.0:
				underback_l -= over
				_spill(over)
		"hop_back":
			var over := hop_back_l - float(capacity.get(HOP_BACK, INF))
			if over > 0.0:
				hop_back_l -= over
				_spill(over)
		"bucket":
			var over := bucket_l - HOIST_BUCKET_L
			if over > 0.0:
				bucket_l -= over
				_spill(over)
		"coolship":
			var over := coolship_l - float(capacity.get(COOLSHIP, INF))
			if over > 0.0:
				coolship_l -= over
				_spill(over)

## A tap or cock, the damper or the hatch set to `amount` (0..1).
func set_control(id: String, amount: float) -> void:
	if controls.has(id):
		controls[id] = clampf(amount, 0.0, 1.0)

## `strokes` of the liquor pump: spring water into the copper, or back into
## the trough with the pipe's cock shut.
func pump_liquor(strokes: int) -> void:
	if strokes <= 0 or float(controls.pipe_cock) < 0.5:
		return
	_into_copper(minf(strokes * LIQUOR_STROKE, float(capacity.get(COPPER, INF)) - copper_l), SPRING_TEMP)

func _into_copper(liters: float, temp: float) -> void:
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

## Grain poured from `sack` at `flow` (0..1) for `minutes`, into the mash tun
## when `into_tun`, else onto the floor. Returns the kg poured.
func pour_grain(sack: String, flow: float, minutes: float, into_tun: bool) -> float:
	if not SACKS.has(sack):
		return 0.0
	var kg := minf(flow * GRAIN_POUR * minutes, float(sacks[sack]))
	if kg <= 0.0:
		return 0.0
	sacks[sack] = float(sacks[sack]) - kg
	if not into_tun:
		return kg
	var lot := MaltLot.bought(str(SACKS[sack][0]), kg)
	lot.mill(SHOP_GAP)
	var lots: Array[MaltLot] = [lot]
	pour_lots(lots)
	return kg

## Juniper branches laid from the bundle at `flow` for `minutes` on the bottom
## of the mash tun; on a mash already in, they are lost. Returns the kg.
func line_tun(flow: float, minutes: float) -> float:
	var kg := minf(flow * JUNIPER_LAY * minutes, juniper_kg)
	juniper_kg -= kg
	if kg > 0.0 and batch.stage == BrewIds.STAGE_NEW:
		batch.line_tun(kg)
	return kg

## Whether the wort in the copper can take honey or linden through the open
## hatch; with the fire out the boil is over (BrewBatch.draw_fire) and they
## keep their aroma while the wort is hot (BrewBatch.steeps).
func _into_wort() -> bool:
	if float(controls.hatch) < 0.5 or not copper_wort or (batch.stage != BrewIds.STAGE_BOIL and batch.stage != BrewIds.STAGE_WORT and not batch.steeps()):
		return false
	if batch.stage == BrewIds.STAGE_WORT:
		batch.boil(0.0, 0.0, false)
	if fire < FIRE_OUT:
		batch.draw_fire()
	return true

## The honey pot tipped into the copper at `flow` for `minutes`. Onto a shut
## hatch or into water it is lost.
func pour_honey(flow: float, minutes: float) -> void:
	var kg := minf(flow * HONEY_POUR * minutes, honey_kg)
	if kg <= 0.0:
		return
	honey_kg -= kg
	if _into_wort():
		batch.add_honey(kg)

## A handful of linden blossom thrown into the copper.
func throw_linden() -> void:
	var kg := minf(LINDEN_THROW, linden_kg)
	if kg <= 0.0:
		return
	linden_kg -= kg
	if _into_wort():
		batch.add_linden(kg)

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

## The water bucket dipped in the trough at `flow` for `minutes`.
func fill_bucket(flow: float, minutes: float) -> void:
	_into_bucket(minf(WATER_BUCKET_L - water_bucket_l, flow * BUCKET_POUR * minutes), SPRING_TEMP)

## The water bucket dipped through the open hatch into the copper's water.
## Wort is not taken: the bucket is for water.
func scoop_copper(flow: float, minutes: float) -> void:
	if float(controls.hatch) < 0.5 or copper_wort:
		return
	var liters := minf(minf(WATER_BUCKET_L - water_bucket_l, flow * BUCKET_POUR * minutes), copper_l)
	copper_l -= liters
	_into_bucket(liters, copper_temp)

func _into_bucket(liters: float, temp: float) -> void:
	if liters <= 0.0:
		return
	water_bucket_temp = (water_bucket_l * water_bucket_temp + liters * temp) / (water_bucket_l + liters)
	water_bucket_l += liters

## The water bucket tipped at `flow` for `minutes` into `vessel` (MASH_TUN,
## COPPER, or "" for elsewhere: the floor, a barrel scalded). Returns the litres.
func pour_bucket(vessel: String, flow: float, minutes: float) -> float:
	var liters := minf(flow * BUCKET_POUR * minutes, water_bucket_l)
	if liters <= 0.0:
		return 0.0
	water_bucket_l -= liters
	if vessel == MASH_TUN:
		_into_tun(liters, water_bucket_temp)
	elif vessel == COPPER:
		_into_copper(liters, water_bucket_temp)
	return liters

## The hoist bucket tipped at `flow` for `minutes`: onto the cooling plate
## when `onto_plate`, else onto the floor.
func pour_hoist_bucket(flow: float, minutes: float, onto_plate: bool) -> void:
	var liters := minf(flow * BUCKET_POUR * minutes, bucket_l)
	if liters <= 0.0:
		return
	bucket_l -= liters
	if onto_plate:
		coolship_l += liters
		_overflow("coolship")
	else:
		_spill(liters)

## The paddle `turns` round the mash tun.
func stir_mash(turns: int) -> void:
	if turns != 0:
		batch.stir(absi(turns))

## The paddle round the copper.
func stir_copper() -> void:
	stirred_at = minute

## The hop basket tipped over the scales at `flow` for `minutes`.
func weigh_hops(flow: float, minutes: float) -> void:
	var grams := minf(flow * HOPS_WEIGH * minutes, hops_g)
	hops_g -= grams
	weighed_g += grams

## Hops thrown into the copper: what is on the scales, else a handful from
## the basket. Through a shut hatch they fall on the lid. Returns the grams.
func throw_hops() -> float:
	var grams := weighed_g
	if grams <= 0.0:
		grams = minf(HANDFUL, hops_g)
		hops_g -= grams
	weighed_g = 0.0
	if float(controls.hatch) < 0.5 or grams <= 0.0:
		return 0.0
	batch.add_hops(grams)
	return grams

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

## Game minutes of sand still to run; 0 when it has run out or was never turned.
func sand_left() -> float:
	return 0.0 if hourglass_at < 0.0 else maxf(0.0, HOURGLASS - (minute - hourglass_at))

## What an instrument shows, for the line by the crosshair: the thermometer
## in `vessel` ("" for the air), the dipstick in `vessel`, the hourglass, the
## hop scales, the steelyard with the sack `vessel` on its hook. Translated.
func reading(instrument: String, vessel := "") -> String:
	match instrument:
		"thermometer":
			if vessel == "":
				return tr("Градусник: в пивоварне %s") % degrees(AIR_TEMP, fine_thermometer)
			if contents(vessel) == "":
				return tr(str(EMPTY[vessel]))
			return "%s: %s" % [tr(str(TITLES[vessel])), degrees(temperature(vessel), fine_thermometer)]
		"dipstick":
			return tr("%s: %.0f л") % [tr(str(TITLES[vessel])), liters(vessel)]
		"hourglass":
			if hourglass_at < 0.0:
				return tr("Песочные часы на %.0f мин") % HOURGLASS
			if sand_left() <= 0.0:
				return tr("Песок пересыпался")
			return tr("Песочные часы: осталось %.0f мин") % ceilf(sand_left())
		"balance":
			return tr("Весы: %.0f г хмеля") % snappedf(weighed_g, FINE_WEIGHT_STEP if full_weights else WEIGHT_STEP)
		"steelyard":
			return tr("Безмен: %.1f кг") % (load_kg(vessel) + float(BrewCarry.WEIGHTS.sack))
	return ""

## °C as a thermometer reads it: to its nearest mark, the precise one with
## its half degrees.
static func degrees(temp: float, fine: bool) -> String:
	if fine:
		return "%.1f°" % snappedf(temp, FINE_THERMO_STEP)
	return "%.0f°" % snappedf(temp, THERMO_STEP)

## Litres in a vessel; the mash tun counts the grain's room too.
func liters(vessel: String) -> float:
	match vessel:
		COPPER:
			return copper_l
		MASH_TUN:
			if batch.stage == BrewIds.STAGE_NEW:
				return tun_water_l
			if batch.stage == BrewIds.STAGE_MASH:
				return batch.mash_l + sparge_l - run_l + batch.grain_kg * GRAIN_BULK
			return batch.grain_kg * (GRAIN_BULK + BrewBatch.GRAIN_KEEPS)
		UNDERBACK:
			return underback_l
		HOP_BACK:
			return hop_back_l
		COOLSHIP:
			return coolship_l
	return 0.0

## How full a vessel is, 0..1.
func fill(vessel: String) -> float:
	var full := float(capacity.get(vessel, 0.0))
	return clampf(liters(vessel) / full, 0.0, 1.0) if full > 0.0 else 0.0

## °C of what a vessel holds.
func temperature(vessel: String) -> float:
	var wort := batch.wort_temp if batch.fire_out else batch.mash_temp
	match vessel:
		COPPER:
			return batch.wort_temp if copper_wort and batch.fire_out else copper_temp
		MASH_TUN:
			return tun_temp if batch.stage == BrewIds.STAGE_NEW else batch.mash_temp
		UNDERBACK:
			return wort
		HOP_BACK, COOLSHIP:
			return batch.wort_temp
	return AIR_TEMP

## What a vessel holds: "water", "mash", "grain" (spent), "wort" or "".
func contents(vessel: String) -> String:
	if liters(vessel) <= 0.01:
		return ""
	match vessel:
		COPPER:
			return "wort" if copper_wort else "water"
		MASH_TUN:
			return str({BrewIds.STAGE_NEW: "water", BrewIds.STAGE_MASH: "mash"}.get(batch.stage, "grain"))
	return "wort"

## Kg of what a carried thing holds.
func load_kg(utensil: String) -> float:
	if SACKS.has(utensil):
		return float(sacks[utensil])
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
		day.batch = BrewBatch.from_dict(saved)
	for key: String in SAVED:
		if not data.has(key):
			continue
		var value: Variant = data[key]
		match typeof(day.get(key)):
			TYPE_FLOAT:
				if (value is float or value is int) and is_finite(float(value)):
					day.set(key, maxf(float(value), -1e6))
			TYPE_BOOL:
				if value is bool:
					day.set(key, value)
			TYPE_DICTIONARY:
				if value is Dictionary:
					var given: Dictionary = value
					var into: Dictionary = day.get(key)
					for name: Variant in into:
						var number: Variant = given.get(name)
						if (number is float or number is int) and is_finite(float(number)):
							into[name] = float(number)
	return day
