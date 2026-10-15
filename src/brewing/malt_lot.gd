class_name MaltLot
extends RefCounted
## A lot of grain on its way from a sack to the mash (docs/plans/brewing.md,
## section 4): barley is steeped, grown on the floor, dried in the kiln and
## milled; bought malt only goes through the mill, and a part of it may be
## roasted dark in the kiln. Each mistake is a flaw id (BrewBatch.FLAWS) that
## goes with the grain into the batch.

## What a kind of grain gives: colour (EBC), extract per kg when well grown,
## smoke 0..1. Raw barley gives a part of its extract only (UNGROWN_EXTRACT).
const KINDS := {
	"barley": {"color": 4.0, "extract": 0.78, "smoke": 0.0},
	"pale": {"color": 6.0, "extract": 0.78, "smoke": 0.0},
	"caramel": {"color": 120.0, "extract": 0.72, "smoke": 0.0},
	"dark": {"color": 600.0, "extract": 0.65, "smoke": 0.0},
	"smoked": {"color": 8.0, "extract": 0.76, "smoke": 1.0},
	"oats": {"color": 4.0, "extract": 0.70, "smoke": 0.0},
}
## The part of its extract a grain that never sprouted gives.
const UNGROWN_EXTRACT := 0.3
## Litres of water a kg of barley needs in the steeping tub to wake whole.
const STEEP_WATER := 1.5
## Growth a day on the floor adds; three days grow the grain whole.
const GROWTH_A_DAY := 0.35
## Days on the floor after which the shoots eat the grain.
const FLOOR_DAYS := 4
## Times a day the heap must be turned, and days unturned that mould it.
const TURNS_A_DAY := 2
const MOULD_DAYS := 2
## What the kiln takes from green malt: water and shoots.
const KILN_LOSS := 0.2
## Kiln heat, °C: green malt dries from WARM on, twice as fast from
## DRY_HEAT up; it stays damp when more than DAMP of its water is left. From
## DARK_HEAT, held DARK_HOURS, it roasts dark; above BURN_HEAT it burns.
const WARM := 40.0
const DRY_HEAT := 50.0
const DRY_HOURS := 8.0
const DAMP := 0.15
const DARK_HEAT := 160.0
const DARK_HOURS := 1.0
const BURN_HEAT := 220.0
## Green malt held at these °C while still wetter than WET stews; STEW_MINUTES
## of it make caramel.
const STEW_LOW := 64.0
const STEW_HIGH := 72.0
const WET := 0.6
const STEW_MINUTES := 60.0
## Smoke an hour under a closed damper; smoke from which malt counts smoked.
const SMOKE_AN_HOUR := 0.3
const SMOKED := 0.5
## Mill gaps closer than this make one grist when two are put together.
const SAME_GAP := 0.05
## Mill gap 0..1: below FLOUR the grain turns to flour (the wort will not run
## off); above WHOLE the grain is barely cracked and gives less.
const FLOUR := 0.15
const WHOLE := 0.5
const COARSE_YIELD := 0.6
const COARSE := 0.85

## "barley", "steeped", "green", or a kind of KINDS that can be milled.
var stage := "barley"
var kind := "barley"
var kg := 0.0
var color := 4.0
var smoke := 0.0
## How much of the lot woke in the tub and how far it grew, 0..1.
var woken := 0.0
var growth := 0.0
var floor_days := 0
var unturned_days := 0
## In the kiln: the part of its water left (1 green, 0 dry), minutes stewed and
## roasted, the hottest °C it saw.
var moisture := 1.0
var stew_minutes := 0.0
var roast_minutes := 0.0
var peak_heat := 0.0
## The mill gap the lot went through, -1 before the mill; the part of its
## extract the crush lets out.
var gap := -1.0
var crush_yield := 0.0
var flaws: Array[String] = []

## A sack of barley as it comes from the mill shop.
static func barley(of_kg: float) -> MaltLot:
	var lot := MaltLot.new()
	lot.kg = of_kg
	return lot

## Bought malt or oats of `of_kind`, ready for the mill.
static func bought(of_kind: String, of_kg: float) -> MaltLot:
	var lot := MaltLot.new()
	lot.stage = of_kind
	lot.kind = of_kind
	lot.kg = of_kg
	lot.color = KINDS[of_kind].color
	lot.smoke = KINDS[of_kind].smoke
	lot.woken = 1.0
	lot.growth = 1.0
	lot.moisture = 0.0
	return lot

func _flaw(id: String) -> void:
	if not flaws.has(id):
		flaws.append(id)

## Steeps the barley in `water_l`: the part covered wakes.
func steep(water_l: float) -> void:
	if stage != "barley":
		return
	woken = clampf(water_l / (kg * STEEP_WATER), 0.0, 1.0)
	if woken < 0.95:
		_flaw("sleepy_grain")
	stage = "steeped"

## A day on the floor with the heap turned `turns` times.
func floor_day(turns: int) -> void:
	if stage != "steeped" and stage != "green":
		return
	stage = "green"
	floor_days += 1
	growth = minf(1.0, growth + GROWTH_A_DAY)
	unturned_days = unturned_days + 1 if turns < TURNS_A_DAY else 0
	if unturned_days >= MOULD_DAYS:
		_flaw("mould")
	if floor_days > FLOOR_DAYS:
		_flaw("overgrown")

## How well the lot grew: what of its starch the mash can turn to sugar.
func modified() -> float:
	var grown := woken * growth
	if flaws.has("overgrown"):
		grown *= 0.85
	return grown

## Dries green malt, or roasts pale malt, at `heat` °C for `hours`, all at
## once (kiln_minutes, then kiln_done). `stew` is the °C the wet malt was held
## at first (-1 for none); `wood` is "oak", "beech", ...; a closed damper sends
## the smoke through the grain.
func kiln(heat: float, hours: float, wood: String, damper_closed: bool, stew := -1.0) -> void:
	if not on_kiln():
		return
	var through := 1.0 if damper_closed else 0.0
	if stew >= 0.0:
		kiln_minutes(STEW_MINUTES, stew, wood, through)
	kiln_minutes(hours * 60.0, heat, wood, through)
	kiln_done()

## Whether the lot can go on the kiln: green malt to dry, pale malt to roast.
func on_kiln() -> bool:
	return stage == "green" or stage == "pale"

## `minutes` on the kiln at `heat` °C burning `wood`; `smoke_through` (0..1) is
## how much of the smoke goes through the grain (a shut damper: 1); `raked`
## malt dries even, unraked at half the pace.
func kiln_minutes(minutes: float, heat: float, wood: String, smoke_through: float, raked := true) -> void:
	if not on_kiln() or minutes <= 0.0:
		return
	peak_heat = maxf(peak_heat, heat)
	if stage == "green":
		if moisture > WET and heat >= STEW_LOW and heat <= STEW_HIGH:
			stew_minutes += minutes
		var pace := clampf((heat - WARM) / (DRY_HEAT - WARM) * 0.5, 0.0, 0.5) + clampf((heat - DRY_HEAT) / 30.0 * 0.5, 0.0, 1.5)
		moisture = maxf(0.0, moisture - pace / DRY_HOURS * minutes / 60.0 * (1.0 if raked else 0.5))
	if heat >= DARK_HEAT:
		roast_minutes += minutes
	if smoke_through > 0.0 and heat > WARM:
		smoke = minf(1.0, smoke + minutes / 60.0 * SMOKE_AN_HOUR * smoke_through)
		if wood != "beech" and smoke_through >= 0.5:
			_flaw("acrid_smoke")

## The malt taken off the kiln: what its heat, its stewing and its smoke made
## of it.
func kiln_done() -> void:
	if not on_kiln():
		return
	if stage == "green":
		kg *= 1.0 - KILN_LOSS
		if moisture > DAMP:
			_flaw("damp_malt")
		kind = "caramel" if stew_minutes >= STEW_MINUTES else "pale"
	if roast_minutes >= DARK_HOURS * 60.0:
		kind = "dark"
	if peak_heat > BURN_HEAT:
		_flaw("burnt")
	color = KINDS[kind].color * (2.0 if flaws.has("burnt") else 1.0)
	if kind == "pale" and smoke >= SMOKED and not flaws.has("acrid_smoke"):
		kind = "smoked"
	stage = kind

## Mills the lot with the stones `mill_gap` apart, 0 (flour) to 1 (whole).
func mill(mill_gap: float) -> void:
	if not KINDS.has(stage) or stage == "barley" or milled():
		return
	gap = clampf(mill_gap, 0.0, 1.0)
	if gap < FLOUR:
		_flaw("flour")
	crush_yield = 1.0 if gap <= WHOLE else lerpf(1.0, COARSE_YIELD, (gap - WHOLE) / (1.0 - WHOLE))
	if crush_yield < COARSE:
		_flaw("coarse_grind")

## Kg of extract the lot can give a mash that turns all its starch.
func extract() -> float:
	if gap < 0.0:
		return 0.0
	var base: float = KINDS[kind].extract
	return kg * base * lerpf(UNGROWN_EXTRACT, 1.0, modified()) * crush_yield

func milled() -> bool:
	return gap >= 0.0

## `of_kg` of the lot taken off as a lot of its own, as it is; null when there
## is nothing to take.
func split(of_kg: float) -> MaltLot:
	var taken := minf(of_kg, kg)
	if taken <= 0.0:
		return null
	var part := MaltLot.from_dict(to_dict())
	part.kg = taken
	kg -= taken
	return part

## Whether `other` can be put together with this lot: grain at the same
## stage, and a grist of the same kind milled at nearly the same gap.
func mixes_with(other: MaltLot) -> bool:
	if other.stage != stage or other.kind != kind or other.milled() != milled():
		return false
	return not milled() or absf(other.gap - gap) < SAME_GAP

## `other` put into this lot: its numbers weighed by kg, its flaws joined.
func merge(other: MaltLot) -> void:
	var total := kg + other.kg
	if total <= 0.0:
		return
	var share := other.kg / total
	for key: String in ["color", "smoke", "woken", "growth", "moisture", "stew_minutes", "roast_minutes", "gap", "crush_yield"]:
		set(key, lerpf(float(get(key)), float(other.get(key)), share))
	floor_days = maxi(floor_days, other.floor_days)
	unturned_days = maxi(unturned_days, other.unturned_days)
	peak_heat = maxf(peak_heat, other.peak_heat)
	for id: String in other.flaws:
		_flaw(id)
	kg = total

## The lot as plain data for a save.
func to_dict() -> Dictionary:
	return {"stage": stage, "kind": kind, "kg": kg, "color": color, "smoke": smoke, "woken": woken, "growth": growth,
		"floor_days": floor_days, "unturned_days": unturned_days, "moisture": moisture, "stew_minutes": stew_minutes,
		"roast_minutes": roast_minutes, "peak_heat": peak_heat, "gap": gap, "crush_yield": crush_yield,
		"flaws": flaws.duplicate()}

## A lot read back from to_dict() through JSON; what is missing or wrong keeps
## a raw barley's.
static func from_dict(data: Dictionary) -> MaltLot:
	var lot := MaltLot.new()
	var of_kind: Variant = data.get("kind")
	if of_kind is String and KINDS.has(of_kind):
		lot.kind = of_kind
	var of_stage: Variant = data.get("stage")
	if of_stage is String and (KINDS.has(of_stage) or of_stage == "steeped" or of_stage == "green"):
		lot.stage = of_stage
	for key: String in ["kg", "color", "smoke", "woken", "growth", "moisture", "stew_minutes", "roast_minutes", "peak_heat",
			"gap", "crush_yield"]:
		var value: Variant = data.get(key)
		if (value is float or value is int) and is_finite(float(value)):
			lot.set(key, float(value))
	for key: String in ["floor_days", "unturned_days"]:
		var days: Variant = data.get(key)
		if (days is float or days is int) and is_finite(float(days)):
			lot.set(key, int(days))
	lot.kg = maxf(lot.kg, 0.0)
	var listed: Variant = data.get("flaws")
	if listed is Array:
		for id: Variant in listed:
			if id is String and BrewBatch.FLAWS.has(id):
				lot._flaw(id)
	return lot
