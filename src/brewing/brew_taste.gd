class_name BrewTaste
extends RefCounted
## What a batch (BrewBatch) tastes like now (docs/plans/brewing.md, section 4):
## strength, body, bitterness, colour, the notes heard in it and its flaws.
## It reads the batch and changes nothing.

## Turns of the paddle oats need for a creamy body.
const OATS_STIRS := 40
## Minutes of strong boil that caramelize the wort.
const LONG_BOIL := 100.0
## Hop alpha acid, the utilization of a long boil and its speed (Tinseth),
## and the minutes before the end from which hops give aroma.
const HOP_ALPHA := 0.04
const HOP_USE := 0.275
const HOP_SPEED := 0.04
const LATE_HOPS := 15.0
## Signature amounts: what makes a note heard in the beer.
const OATS_NOTE := 0.2
const CARAMEL_NOTE := 1.0
const SMOKE_NOTE := 0.15
const HOPS_NOTE := 0.5
const JUNIPER_NOTE := 0.004
const HONEY_NOTE := 0.015
const LINDEN_NOTE := 0.001
const CHERRY_NOTE := 0.05

## Strength of a wort of `extract` kg in `liters`, degrees Plato.
static func plato(extract: float, liters: float) -> float:
	return 0.0 if liters <= 0.0 else 100.0 * extract / (liters + extract)

## IBU of the batch's hops after its boil so far.
static func bitterness(batch: BrewBatch) -> float:
	var total := 0.0
	for addition: Dictionary in batch.hops:
		var grams: float = addition.grams
		var at: float = addition.at
		var boiled := maxf(0.0, batch.boil_minutes - at)
		total += grams * HOP_ALPHA * 1000.0 * HOP_USE * (1.0 - exp(-HOP_SPEED * boiled)) / maxf(batch.volume_l, 1.0)
	return total

## Hops grams a litre added in the last LATE_HOPS minutes or after the fire.
static func hop_aroma(batch: BrewBatch) -> float:
	var grams := 0.0
	for addition: Dictionary in batch.hops:
		var at: float = addition.at
		if batch.boil_minutes - at <= LATE_HOPS:
			var weight: float = addition.grams
			grams += weight
	return grams / maxf(batch.volume_l, 1.0)

## What the batch tastes like now: {strength (% ABV), gravity (°P), body,
## sweetness, bitterness (IBU), aroma (late hops g/l), color (EBC), clarity,
## smoke, foam (0..1), notes, flaws, ruined, quality (0..1)}.
static func profile(batch: BrewBatch) -> Dictionary:
	var extract := batch.malt_extract + batch.sugar_extract
	var gravity := plato(extract, batch.volume_l)
	var fermentable := 0.0 if batch.conversion <= 0.0 else batch.fermentable_sum / batch.conversion
	var eaten := 0.0 if extract <= 0.0 else (batch.malt_extract * fermentable + batch.sugar_extract) * batch.ferment / extract
	var rest_gravity := gravity * (1.0 - eaten)
	var oats_body := batch.oats_share * 4.0 * minf(1.0, float(batch.stir_turns) / OATS_STIRS)
	var ibu := bitterness(batch)
	var caramel := batch.caramel_share * 5.0 + (0.5 if batch.strong_minutes >= LONG_BOIL else 0.0)
	var mcu := batch.color_points / maxf(batch.volume_l, 1.0) * 7.0 + (5.0 if batch.strong_minutes >= LONG_BOIL else 0.0)
	var taste: Array[String] = batch.flaws.duplicate()
	if batch.stage == BrewIds.STAGE_BARREL and batch.age_days < batch.ready_days():
		taste.append(BrewIds.FLAW_GREEN)
	var notes: Array[String] = []
	var per_l := 1.0 / maxf(batch.volume_l, 1.0)
	if hop_aroma(batch) >= HOPS_NOTE:
		notes.append(BrewIds.NOTE_HOPS)
	if batch.oats_share >= OATS_NOTE and batch.stir_turns >= OATS_STIRS:
		notes.append(BrewIds.NOTE_OATS)
	if caramel >= CARAMEL_NOTE:
		notes.append(BrewIds.NOTE_CARAMEL)
	if batch.smoke >= SMOKE_NOTE:
		notes.append(BrewIds.NOTE_SMOKE)
	if batch.juniper_kg * per_l >= JUNIPER_NOTE:
		notes.append(BrewIds.NOTE_JUNIPER)
	if batch.honey_kg * per_l >= HONEY_NOTE:
		notes.append(BrewIds.NOTE_HONEY)
	if batch.linden_kg * per_l >= LINDEN_NOTE:
		notes.append(BrewIds.NOTE_LINDEN)
	if batch.cherries_kg * per_l >= CHERRY_NOTE:
		notes.append(BrewIds.NOTE_CHERRY)
	var ruined := false
	for id: StringName in BrewIds.RUINS:
		ruined = ruined or taste.has(id)
	var clarity := clampf(0.4 + 0.06 * batch.age_days, 0.0, 1.0) - batch.haze - (0.2 if batch.flour else 0.0) - 0.3 * batch.oats_share
	return {
		"strength": gravity * eaten * 0.5,
		"gravity": gravity,
		"body": rest_gravity + oats_body,
		"sweetness": rest_gravity + batch.caramel_share * 8.0,
		"bitterness": ibu,
		"aroma": hop_aroma(batch),
		"color": 300.0 * (1.0 - exp(-mcu / 300.0)),
		"clarity": clampf(clarity, 0.0, 1.0),
		"smoke": batch.smoke,
		"foam": clampf(0.55 + 0.6 * batch.oats_share + 0.5 * batch.caramel_share + (0.1 if ibu > 20.0 else 0.0), 0.0, 1.0),
		"notes": notes,
		"flaws": taste,
		"ruined": ruined,
		"quality": 0.0 if ruined else maxf(0.0, 1.0 - 0.15 * taste.size()),
	}
