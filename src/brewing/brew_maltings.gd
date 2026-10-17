class_name BrewMaltings
extends RefCounted
## The brewery's maltings (docs/plans/brewing.md, section 4, from a sack of
## barley to a sack of grist): the steeping tub, the growing floor, the kiln
## and its fire, the quern and the meal bin. Kg and where they go are here;
## what the grain becomes is the lot's: this calls the steps of MaltLot and
## counts none of its numbers again. The steeping and the floor go a day at a
## time (dawn), which the game clock gives (DayClock); the kiln by the minute.
##
## The three barley sacks carry the grain on from the tub: kilned malt into
## the quern, grist from the meal bin to the mash tun. A sack holds lots of
## one kind of work: raw barley, kilned malt, or grist.

## Kg a barley sack holds when the brewery is handed over, and at most.
const SACK_KG := 30.0
const SACK_HOLDS := 40.0
## Kg of barley the steeping tub takes, litres of water with it; litres a game
## minute through the drain opened full.
const STEEP_KG := 120.0
const STEEP_L := 250.0
const DRAIN := 20.0
## Kg a pass of the shovel moves; passes that turn the heap once.
const SHOVEL_KG := 8.0
const TURN_PASSES := 4
## Kg the kiln floor takes; game minutes a raking keeps the malt even.
const KILN_KG := 100.0
const RAKED_MINUTES := 120.0
## The kiln's fire: kg of wood that make a full fire (one log a quarter of
## it), kg an open draught burns a game minute, °C a full fire gives over the
## air, game minutes the kiln takes to go most of the way to its heat.
const FULL_FUEL := 16.0
const BURN := 0.004
const KILN_HEAT := 230.0
const KILN_LAG := 10.0
## Kg a quern turn grinds; kg the hopper and the meal bin hold.
const QUERN_KG := 2.5
const HOPPER_KG := 40.0
const BIN_KG := 150.0
## Kg a game minute of a full pour from a sack; of a sack filled by the scoop.
const POUR := 30.0
const SCOOP := 20.0
## Game minutes a step of the kiln goes at most.
const STEP := 5.0
## The hand-set controls and where they start: the tub's plug (1 open), the
## kiln's damper (1 open), the quern's wedge (the gap, MaltLot.mill).
const CONTROLS := {"steep_plug": 0.0, "kiln_damper": 1.0, "quern_wedge": 0.35}
## The moving part of brewery.json each control turns.
const PARTS := {"steep_plug": "steep_plug", "kiln_damper": "kiln_damper", "quern_wedge": "quern_wedge"}

var controls := CONTROLS.duplicate()
## Sack id -> the lots in it.
var sacks := {}
## The tub: its barley and water; null when it holds no grain.
var steep: MaltLot
var steep_water_l := 0.0
## The heap on the floor and the shovel passes over it since the last dawn.
var couch: MaltLot
var couch_passes := 0
## The malt on the kiln floor; the fire's wood, kg of it beech; the kiln's °C;
## the game minute it was raked last; the game minutes counted.
var kiln: MaltLot
var fuel := 0.0
var beech_fuel := 0.0
var kiln_temp := BrewDay.AIR_TEMP
var raked_at := -INF
var minute := 0.0
## Kilned malt in the quern's hopper; grists in the meal bin; the runner's angle.
var hopper: MaltLot
var bin: Array[MaltLot] = []
var quern_angle := 0.0

func _init() -> void:
	for id: String in BrewIds.BARLEY_SACKS:
		var lots: Array[MaltLot] = [MaltLot.barley(SACK_KG)]
		sacks[id] = lots

func set_control(id: String, amount: float) -> void:
	if controls.has(id):
		controls[id] = clampf(amount, 0.0, 1.0)

## How hard the kiln's fire draws: a shut damper keeps a third of the draught.
func draught() -> float:
	return lerpf(BrewDay.SHUT_DRAUGHT, 1.0, Values.real(controls.kiln_damper))

## How strong the kiln's fire burns, 0..1.
func fire() -> float:
	return clampf(fuel / FULL_FUEL, 0.0, 1.0) * draught()

## The wood the kiln burns now: "beech" when beech is most of it.
func wood() -> String:
	return "beech" if fuel > 0.0 and beech_fuel >= 0.5 * fuel else "oak"

## The game clock moved on `minutes`: the tub drains, the kiln burns and its
## malt dries, STEP minutes at a time.
func advance(minutes: float) -> void:
	var left := minutes
	while left > 0.0:
		var step := minf(left, STEP)
		_tick(step)
		left -= step

func _tick(step: float) -> void:
	minute += step
	steep_water_l = maxf(0.0, steep_water_l - Values.real(controls.steep_plug) * DRAIN * step)
	var share := beech_fuel / fuel if fuel > 0.0 else 0.0
	var burnt := minf(fuel, BURN * draught() * step)
	fuel -= burnt
	beech_fuel = fuel * share
	var target := BrewDay.AIR_TEMP + fire() * KILN_HEAT
	kiln_temp = target + (kiln_temp - target) * exp(-step / KILN_LAG)
	if kiln != null:
		# A shut damper sends the smoke through the grain.
		var through := 1.0 - Values.real(controls.kiln_damper) if fuel > 0.0 else 0.0
		kiln.kiln_minutes(step, kiln_temp, wood(), through, minute - raked_at <= RAKED_MINUTES)

## A new day: barley soaked overnight wakes; the heap grows a day by the times
## it was turned.
func dawn() -> void:
	if steep != null and steep.stage == "barley" and steep_water_l > 0.0:
		steep.steep(steep_water_l)
	if couch != null:
		couch.floor_day(couch_passes / TURN_PASSES)
	couch_passes = 0

## Kg in sack `id`.
func sack_kg(id: String) -> float:
	var total := 0.0
	var lots: Array[MaltLot] = sacks.get(id, [] as Array[MaltLot])
	for lot: MaltLot in lots:
		total += lot.kg
	return total

## What a sack holds: "barley", "malt", "grist" or "" when empty.
func sack_holds(id: String) -> String:
	var lots: Array[MaltLot] = sacks.get(id, [] as Array[MaltLot])
	if lots.is_empty():
		return ""
	return _holds(lots[0])

static func _holds(lot: MaltLot) -> String:
	if lot.stage == "barley":
		return "barley"
	return "grist" if lot.milled() else "malt"

## `of_kg` taken out of sack `id`, from its first lot on: the lots taken.
func _take(id: String, of_kg: float) -> Array[MaltLot]:
	var taken: Array[MaltLot] = []
	var lots: Array[MaltLot] = sacks.get(id, [] as Array[MaltLot])
	var left := of_kg
	while left > 0.0 and not lots.is_empty():
		var part := lots[0].split(left)
		if lots[0].kg <= 0.001:
			lots.remove_at(0)
		if part == null:
			continue
		left -= part.kg
		taken.append(part)
	return taken

## `lot` put into sack `id`; false when the sack holds another kind of work.
func _into_sack(id: String, lot: MaltLot) -> bool:
	var lots: Array[MaltLot] = sacks[id]
	if not lots.is_empty() and _holds(lots[0]) != _holds(lot):
		return false
	for each: MaltLot in lots:
		if each.mixes_with(lot):
			each.merge(lot)
			return true
	lots.append(lot)
	return true

## Room left in sack `id`, kg.
func _room(id: String) -> float:
	return maxf(0.0, SACK_HOLDS - sack_kg(id))

## Barley poured from sack `id` at `flow` for `minutes` into the tub. Grain
## that is not barley, or barley onto grain already steeped, is wasted on the
## floor. Returns the kg poured.
func pour_steep(id: String, flow: float, minutes: float) -> float:
	var room := STEEP_KG - (steep.kg if steep != null else 0.0)
	var taken := _take(id, minf(flow * POUR * minutes, room))
	var poured := 0.0
	for lot: MaltLot in taken:
		poured += lot.kg
		if lot.stage != "barley" or (steep != null and steep.stage != "barley"):
			continue
		if steep == null:
			steep = lot
		else:
			steep.merge(lot)
	return poured

## `liters` of water into the tub; what it will not take runs over.
func water_steep(liters: float) -> void:
	steep_water_l = minf(STEEP_L, steep_water_l + liters)

## Shovel passes in the drained tub: steeped grain thrown onto the floor.
func shovel_out(passes: int) -> void:
	if steep == null or steep.stage != "steeped" or steep_water_l > 1.0 or passes <= 0:
		return
	if couch != null and not couch.mixes_with(steep):
		return
	var part := steep.split(SHOVEL_KG * passes)
	couch = part if couch == null else _merged(couch, part)
	if steep.kg <= 0.001:
		steep = null

static func _merged(into: MaltLot, lot: MaltLot) -> MaltLot:
	into.merge(lot)
	return into

## Shovel passes over the heap on the floor: turning it.
func turn_couch(passes: int) -> void:
	if couch != null and passes > 0:
		couch_passes += passes

## Shovel passes at the kiln: green malt from the floor onto the kiln floor.
## It takes malt that has grown a day at least, and only onto green malt.
func load_kiln(passes: int) -> void:
	if couch == null or couch.floor_days < 1 or passes <= 0:
		return
	if kiln != null and (kiln.stage != "green" or not kiln.mixes_with(couch)):
		return
	var room := KILN_KG - (kiln.kg if kiln != null else 0.0)
	var part := couch.split(minf(SHOVEL_KG * passes, room))
	if part == null:
		return
	kiln = part if kiln == null else _merged(kiln, part)
	if couch.kg <= 0.001:
		couch = null

## A log into the kiln's fire.
func stoke(log_id: String) -> void:
	fuel = minf(fuel + BrewDay.LOG_KG, FULL_FUEL * 1.5)
	if log_id == "beech_log":
		beech_fuel = minf(beech_fuel + BrewDay.LOG_KG, fuel)

## Rake passes over the kiln's malt.
func rake(passes: int) -> void:
	if kiln != null and passes > 0:
		raked_at = minute

## Sack `id` filled from the kiln at `flow` for `minutes`: the malt taken off
## is done (MaltLot.kiln_done), as far as it got.
func sack_kiln(id: String, flow: float, minutes: float) -> void:
	if kiln == null:
		return
	var part := kiln.split(minf(flow * SCOOP * minutes, _room(id)))
	if part == null:
		return
	part.kiln_done()
	if not _into_sack(id, part):
		kiln.merge(part)
	if kiln.kg <= 0.001:
		kiln = null

## Kilned malt poured from sack `id` into the quern's hopper. Barley, green
## malt or grist goes onto the floor.
func pour_hopper(id: String, flow: float, minutes: float) -> void:
	if sack_holds(id) != "malt":
		return
	var room := HOPPER_KG - (hopper.kg if hopper != null else 0.0)
	for lot: MaltLot in _take(id, minf(flow * POUR * minutes, room)):
		if hopper == null:
			hopper = lot
		elif hopper.mixes_with(lot):
			hopper.merge(lot)

## The quern's gap (MaltLot.mill), as its wedge sets it.
func gap() -> float:
	return Values.real(controls.quern_wedge)

## The runner turned `turns`: the hopper's malt ground at the wedge's gap into
## the meal bin.
func grind(turns: float) -> void:
	quern_angle += turns * TAU
	var done := absf(turns)
	if hopper == null or done <= 0.0:
		return
	var part := hopper.split(minf(done * QUERN_KG, maxf(0.0, BIN_KG - bin_kg())))
	if hopper.kg <= 0.001:
		hopper = null
	if part == null:
		return
	part.mill(gap())
	for lot: MaltLot in bin:
		if lot.mixes_with(part):
			lot.merge(part)
			return
	bin.append(part)

func bin_kg() -> float:
	var total := 0.0
	for lot: MaltLot in bin:
		total += lot.kg
	return total

## Sack `id` filled with grist from the meal bin at `flow` for `minutes`.
func sack_bin(id: String, flow: float, minutes: float) -> void:
	var left := minf(flow * SCOOP * minutes, _room(id))
	while left > 0.001 and not bin.is_empty():
		var part := bin[0].split(left)
		if bin[0].kg <= 0.001:
			bin.remove_at(0)
		if part == null:
			continue
		if not _into_sack(id, part):
			bin.insert(0, part)
			return
		left -= part.kg

## `of_kg` of what sack `id` holds, poured into the mash tun (BrewDay.pour_lots).
func take_grist(id: String, of_kg: float) -> Array[MaltLot]:
	return _take(id, of_kg)

## Kg of what a maltings utensil holds.
func load_kg(utensil: String) -> float:
	return sack_kg(utensil) if sacks.has(utensil) else 0.0

## What the eye reads at a place of the maltings (`steep`, `floor`, `kiln`,
## `mill`) with `held` in the hand (the thermometer shows the kiln's heat, the
## dipstick the tub's water, the precise one when `fine`). Translated.
func reading(place: String, held := "", fine := false) -> String:
	match place:
		"steep":
			if held == "dipstick":
				return tr("Замочный чан: %.0f л воды") % steep_water_l
			if steep == null:
				return tr("Замочный чан пуст, воды %.0f л") % steep_water_l if steep_water_l > 0.5 else tr("Замочный чан пуст")
			var state := "замочен" if steep.stage == "steeped" else "сухой"
			var water := "под водой" if steep_water_l >= steep.kg * MaltLot.STEEP_WATER else ("воды мало" if steep_water_l > 0.5 else "без воды")
			return tr("Замочный чан: %.0f кг ячменя, %s, %s") % [steep.kg, tr(state), tr(water)]
		"floor":
			if couch == null:
				return tr("Ток пуст")
			var warm := "тёплая" if couch.unturned_days > 0 or (couch_passes < TURN_PASSES and couch.floor_days > 0) else "прохладная"
			return tr("Ток: %.0f кг, ростки %.0f мм, куча %s") % [couch.kg, couch.growth * 8.0, tr(warm)]
		"kiln":
			var heat := tr("Сушилка: %s") % BrewGauges.degrees(kiln_temp, fine) if held == "thermometer" else tr("Сушилка")
			if kiln == null:
				return tr("%s, пусто") % heat
			var dryness := "сырой" if kiln.moisture > MaltLot.WET else ("сыроват" if kiln.moisture > MaltLot.DAMP else "сухой")
			return tr("%s, %.0f кг солода, %s, %s") % [heat, kiln.kg, tr(dryness), tr(_shade(kiln))]
		"mill":
			var hopper_kg := hopper.kg if hopper != null else 0.0
			return tr("Жёрнов: зазор %.0f %%, в ковше %.0f кг, в ларе %.0f кг") % [gap() * 100.0, hopper_kg, bin_kg()]
	return ""

## The shade of malt on the kiln, by eye.
static func _shade(lot: MaltLot) -> String:
	if lot.peak_heat > MaltLot.BURN_HEAT:
		return "чёрный, гарью пахнет"
	if lot.roast_minutes >= MaltLot.DARK_HOURS * 60.0:
		return "тёмный"
	if lot.roast_minutes > 0.0:
		return "темнеет"
	if lot.stew_minutes >= MaltLot.STEW_MINUTES:
		return "янтарный, сладко пахнет"
	return "дымный" if lot.smoke >= MaltLot.SMOKED else "светлый"

# ---- Save -------------------------------------------------------------------

func to_dict() -> Dictionary:
	var saved_sacks := {}
	for id: String in BrewIds.BARLEY_SACKS:
		var lots: Array = []
		for lot: MaltLot in sacks[id]:
			lots.append(lot.to_dict())
		saved_sacks[id] = lots
	var saved_bin: Array = []
	for lot: MaltLot in bin:
		saved_bin.append(lot.to_dict())
	return {"controls": controls.duplicate(), "sacks": saved_sacks, "steep": _lot_dict(steep), "steep_water_l": steep_water_l,
		"couch": _lot_dict(couch), "couch_passes": couch_passes, "kiln": _lot_dict(kiln), "fuel": fuel,
		"beech_fuel": beech_fuel, "kiln_temp": kiln_temp, "raked_at": maxf(raked_at, -1e6), "minute": minute,
		"hopper": _lot_dict(hopper), "bin": saved_bin, "quern_angle": quern_angle}

static func _lot_dict(lot: MaltLot) -> Variant:
	return lot.to_dict() if lot != null else null

static func _lot(value: Variant) -> MaltLot:
	return MaltLot.from_dict(Values.table(value)) if value is Dictionary else null

## The maltings read back from to_dict() through JSON; what is missing or
## wrong keeps the start's.
static func from_dict(data: Dictionary) -> BrewMaltings:
	var maltings := BrewMaltings.new()
	var saved_controls: Variant = data.get("controls")
	if saved_controls is Dictionary:
		var control_values: Dictionary = saved_controls
		for id: String in CONTROLS:
			maltings.controls[id] = Values.number(control_values.get(id), Values.real(CONTROLS[id]), 0.0, 1.0)
	var saved_sacks: Variant = data.get("sacks")
	if saved_sacks is Dictionary:
		var sack_rows: Dictionary = saved_sacks
		for id: String in BrewIds.BARLEY_SACKS:
			var saved: Variant = sack_rows.get(id)
			if not saved is Array:
				continue
			var lots: Array[MaltLot] = []
			for item: Variant in saved:
				if item is Dictionary:
					lots.append(MaltLot.from_dict(Values.table(item)))
			maltings.sacks[id] = lots
	maltings.steep = _lot(data.get("steep"))
	maltings.steep_water_l = Values.number(data.get("steep_water_l"), 0.0, 0.0, STEEP_L)
	maltings.couch = _lot(data.get("couch"))
	maltings.couch_passes = int(Values.number(data.get("couch_passes"), 0.0, 0.0, 1000.0))
	maltings.kiln = _lot(data.get("kiln"))
	maltings.fuel = Values.number(data.get("fuel"), 0.0, 0.0, FULL_FUEL * 1.5)
	maltings.beech_fuel = Values.number(data.get("beech_fuel"), 0.0, 0.0, maltings.fuel)
	maltings.kiln_temp = Values.number(data.get("kiln_temp"), BrewDay.AIR_TEMP, -40.0, 400.0)
	maltings.minute = Values.number(data.get("minute"), 0.0, 0.0, 1e9)
	maltings.raked_at = Values.number(data.get("raked_at"), -1e6, -1e6, maltings.minute)
	maltings.hopper = _lot(data.get("hopper"))
	var saved_bin: Variant = data.get("bin")
	if saved_bin is Array:
		for item: Variant in saved_bin:
			if item is Dictionary:
				maltings.bin.append(MaltLot.from_dict(Values.table(item)))
	maltings.quern_angle = Values.number(data.get("quern_angle"), 0.0, -1e9, 1e9)
	return maltings
