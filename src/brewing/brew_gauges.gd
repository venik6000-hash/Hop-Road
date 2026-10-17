class_name BrewGauges
extends RefCounted
## What the brewing day's vessels and instruments show (BrewDay): litres, °C
## and contents of a vessel, how full it is, and the line by the crosshair
## that the thermometer, the dipstick, the hourglass, the hop scales and the
## steelyard read. It reads the day and changes nothing.

## What each vessel is called.
const TITLES := {BrewDay.COPPER: "Котёл", BrewDay.MASH_TUN: "Заторный чан", BrewDay.UNDERBACK: "Приёмный чан",
	BrewDay.HOP_BACK: "Хмелецедильный чан", BrewDay.COOLSHIP: "Холодильная тарелка"}
## Each vessel read empty: whole keys of the table, the word "empty" agrees
## with the title.
const EMPTY := {BrewDay.COPPER: "Котёл пуст", BrewDay.MASH_TUN: "Заторный чан пуст", BrewDay.UNDERBACK: "Приёмный чан пуст",
	BrewDay.HOP_BACK: "Хмелецедильный чан пуст", BrewDay.COOLSHIP: "Холодильная тарелка пуста"}
## Litres of room a kg of grain takes in the mash.
const GRAIN_BULK := 0.7
## Game minutes the sand of the hourglass runs.
const HOURGLASS := 60.0
## °C between the marks of the brewery's thermometer and of the precise one
## from the market; grams of the smallest weight of the scales' old set and
## of the full one (BrewTrade).
const THERMO_STEP := 2.0
const FINE_THERMO_STEP := 0.5
const WEIGHT_STEP := 100.0
const FINE_WEIGHT_STEP := 10.0

## Game minutes of sand still to run; 0 when it has run out or was never turned.
static func sand_left(day: BrewDay) -> float:
	return 0.0 if day.hourglass_at < 0.0 else maxf(0.0, HOURGLASS - (day.minute - day.hourglass_at))

## What an instrument shows, for the line by the crosshair: the thermometer
## in `vessel` ("" for the air), the dipstick in `vessel`, the hourglass, the
## hop scales, the steelyard with the sack `vessel` on its hook. Translated.
static func reading(day: BrewDay, instrument: String, vessel := "") -> String:
	match instrument:
		"thermometer":
			if vessel == "":
				return TranslationServer.translate("Градусник: в пивоварне %s") % degrees(BrewDay.AIR_TEMP, day.fine_thermometer)
			if contents(day, vessel) == "":
				return TranslationServer.translate(str(EMPTY[vessel]))
			return "%s: %s" % [TranslationServer.translate(str(TITLES[vessel])),
				degrees(temperature(day, vessel), day.fine_thermometer)]
		"dipstick":
			return TranslationServer.translate("%s: %.0f л") % [TranslationServer.translate(str(TITLES[vessel])),
				liters(day, vessel)]
		"hourglass":
			if day.hourglass_at < 0.0:
				return TranslationServer.translate("Песочные часы на %.0f мин") % HOURGLASS
			if sand_left(day) <= 0.0:
				return TranslationServer.translate("Песок пересыпался")
			return TranslationServer.translate("Песочные часы: осталось %.0f мин") % ceilf(sand_left(day))
		"balance":
			var step := FINE_WEIGHT_STEP if day.full_weights else WEIGHT_STEP
			return TranslationServer.translate("Весы: %.0f г хмеля") % snappedf(day.weighed_g, step)
		"steelyard":
			return TranslationServer.translate("Безмен: %.1f кг") % (day.load_kg(vessel) + float(BrewCarry.WEIGHTS.sack))
	return ""

## °C as a thermometer reads it: to its nearest mark, the precise one with
## its half degrees.
static func degrees(temp: float, fine: bool) -> String:
	if fine:
		return "%.1f°" % snappedf(temp, FINE_THERMO_STEP)
	return "%.0f°" % snappedf(temp, THERMO_STEP)

## Litres in a vessel; the mash tun counts the grain's room too.
static func liters(day: BrewDay, vessel: String) -> float:
	var batch := day.batch
	match vessel:
		BrewDay.COPPER:
			return day.copper_l
		BrewDay.MASH_TUN:
			if batch.stage == BrewIds.STAGE_NEW:
				return day.tun_water_l
			if batch.stage == BrewIds.STAGE_MASH:
				return batch.mash_l + day.sparge_l - day.run_l + batch.grain_kg * GRAIN_BULK
			return batch.grain_kg * (GRAIN_BULK + BrewBatch.GRAIN_KEEPS)
		BrewDay.UNDERBACK:
			return day.underback_l
		BrewDay.HOP_BACK:
			return day.hop_back_l
		BrewDay.COOLSHIP:
			return day.coolship_l
	return 0.0

## How full a vessel is, 0..1.
static func fill(day: BrewDay, vessel: String) -> float:
	var full := Values.real(day.capacity.get(vessel, 0.0))
	return clampf(liters(day, vessel) / full, 0.0, 1.0) if full > 0.0 else 0.0

## °C of what a vessel holds.
static func temperature(day: BrewDay, vessel: String) -> float:
	var batch := day.batch
	var wort := batch.wort_temp if batch.fire_out else batch.mash_temp
	match vessel:
		BrewDay.COPPER:
			return batch.wort_temp if day.copper_wort and batch.fire_out else day.copper_temp
		BrewDay.MASH_TUN:
			return day.tun_temp if batch.stage == BrewIds.STAGE_NEW else batch.mash_temp
		BrewDay.UNDERBACK:
			return wort
		BrewDay.HOP_BACK, BrewDay.COOLSHIP:
			return batch.wort_temp
	return BrewDay.AIR_TEMP

## What a vessel holds: "water", "mash", "grain" (spent), "wort" or "".
static func contents(day: BrewDay, vessel: String) -> String:
	if liters(day, vessel) <= 0.01:
		return ""
	match vessel:
		BrewDay.COPPER:
			return "wort" if day.copper_wort else "water"
		BrewDay.MASH_TUN:
			return str({BrewIds.STAGE_NEW: "water", BrewIds.STAGE_MASH: "mash"}.get(day.batch.stage, "grain"))
	return "wort"
