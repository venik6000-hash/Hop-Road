class_name BrewPouring
extends RefCounted
## What the hand pours from a utensil of the brewing day (BrewDay): grain from
## a sack, juniper from its bundle, honey from the pot, linden blossom, water
## from the bucket, wort from the hoist bucket, hops onto the scales and into
## the copper. The stocks and the vessels are the day's; this takes from the
## one and gives to the other.

## Malt from the mill shop comes crushed at this gap (MaltLot.mill).
const SHOP_GAP := 0.35
## What a full pour gives a game minute: kg of grain from a sack, litres from
## a bucket, grams of hops onto the scales.
const GRAIN_POUR := 30.0
const BUCKET_POUR := 40.0
const HOPS_WEIGH := 600.0
## Grams of hops a throw takes when none were weighed.
const HANDFUL := 60.0
## Kg a game minute of the honey pot tipped full; of juniper laid in the tun
## at a full tilt; kg of linden blossom a throw.
const HONEY_POUR := 4.0
const JUNIPER_LAY := 2.0
const LINDEN_THROW := 0.25

## Grain poured from `sack` at `flow` (0..1) for `minutes`, into the mash tun
## when `into_tun`, else onto the floor. Returns the kg poured.
static func pour_grain(day: BrewDay, sack: String, flow: float, minutes: float, into_tun: bool) -> float:
	if not BrewDay.SACKS.has(sack):
		return 0.0
	var kg := minf(flow * GRAIN_POUR * minutes, Values.real(day.sacks[sack]))
	if kg <= 0.0:
		return 0.0
	day.sacks[sack] = Values.real(day.sacks[sack]) - kg
	if not into_tun:
		return kg
	var lot := MaltLot.bought(str(BrewDay.SACKS[sack][0]), kg)
	lot.mill(SHOP_GAP)
	var lots: Array[MaltLot] = [lot]
	day.pour_lots(lots)
	return kg

## Juniper branches laid from the bundle at `flow` for `minutes` on the bottom
## of the mash tun; on a mash already in, they are lost. Returns the kg.
static func line_tun(day: BrewDay, flow: float, minutes: float) -> float:
	var kg := minf(flow * JUNIPER_LAY * minutes, day.juniper_kg)
	day.juniper_kg -= kg
	if kg > 0.0 and day.batch.stage == BrewIds.STAGE_NEW:
		day.batch.line_tun(kg)
	return kg

## Whether the wort in the copper can take honey or linden through the open
## hatch; with the fire out the boil is over (BrewBatch.draw_fire) and they
## keep their aroma while the wort is hot (BrewBatch.steeps).
static func _into_wort(day: BrewDay) -> bool:
	var batch := day.batch
	if Values.real(day.controls.hatch) < 0.5 or not day.copper_wort \
			or (batch.stage != BrewIds.STAGE_BOIL and batch.stage != BrewIds.STAGE_WORT and not batch.steeps()):
		return false
	if batch.stage == BrewIds.STAGE_WORT:
		batch.boil(0.0, 0.0, false)
	if day.fire < BrewDay.FIRE_OUT:
		batch.draw_fire()
	return true

## The honey pot tipped into the copper at `flow` for `minutes`. Onto a shut
## hatch or into water it is lost.
static func pour_honey(day: BrewDay, flow: float, minutes: float) -> void:
	var kg := minf(flow * HONEY_POUR * minutes, day.honey_kg)
	if kg <= 0.0:
		return
	day.honey_kg -= kg
	if _into_wort(day):
		day.batch.add_honey(kg)

## A handful of linden blossom thrown into the copper.
static func throw_linden(day: BrewDay) -> void:
	var kg := minf(LINDEN_THROW, day.linden_kg)
	if kg <= 0.0:
		return
	day.linden_kg -= kg
	if _into_wort(day):
		day.batch.add_linden(kg)

## The water bucket dipped in the trough at `flow` for `minutes`.
static func fill_bucket(day: BrewDay, flow: float, minutes: float) -> void:
	_into_bucket(day, minf(BrewDay.WATER_BUCKET_L - day.water_bucket_l, flow * BUCKET_POUR * minutes), BrewDay.SPRING_TEMP)

## The water bucket dipped through the open hatch into the copper's water.
## Wort is not taken: the bucket is for water.
static func scoop_copper(day: BrewDay, flow: float, minutes: float) -> void:
	if Values.real(day.controls.hatch) < 0.5 or day.copper_wort:
		return
	var liters := minf(minf(BrewDay.WATER_BUCKET_L - day.water_bucket_l, flow * BUCKET_POUR * minutes), day.copper_l)
	day.copper_l -= liters
	_into_bucket(day, liters, day.copper_temp)

static func _into_bucket(day: BrewDay, liters: float, temp: float) -> void:
	if liters <= 0.0:
		return
	day.water_bucket_temp = (day.water_bucket_l * day.water_bucket_temp + liters * temp) / (day.water_bucket_l + liters)
	day.water_bucket_l += liters

## The water bucket tipped at `flow` for `minutes` into `vessel` (BrewDay's
## MASH_TUN, COPPER, or "" for elsewhere: the floor, a barrel scalded).
## Returns the litres.
static func pour_bucket(day: BrewDay, vessel: String, flow: float, minutes: float) -> float:
	var liters := minf(flow * BUCKET_POUR * minutes, day.water_bucket_l)
	if liters <= 0.0:
		return 0.0
	day.water_bucket_l -= liters
	if vessel == BrewDay.MASH_TUN:
		day.into_tun(liters, day.water_bucket_temp)
	elif vessel == BrewDay.COPPER:
		day.into_copper(liters, day.water_bucket_temp)
	return liters

## The hoist bucket tipped at `flow` for `minutes`: onto the cooling plate
## when `onto_plate`, else onto the floor.
static func pour_hoist_bucket(day: BrewDay, flow: float, minutes: float, onto_plate: bool) -> void:
	var liters := minf(flow * BUCKET_POUR * minutes, day.bucket_l)
	if liters <= 0.0:
		return
	day.bucket_l -= liters
	if onto_plate:
		day.coolship_l += liters
		day.overflow("coolship")
	else:
		day.spill(liters)

## The hop basket tipped over the scales at `flow` for `minutes`.
static func weigh_hops(day: BrewDay, flow: float, minutes: float) -> void:
	var grams := minf(flow * HOPS_WEIGH * minutes, day.hops_g)
	day.hops_g -= grams
	day.weighed_g += grams

## Hops thrown into the copper: what is on the scales, else a handful from
## the basket. Through a shut hatch they fall on the lid. Returns the grams.
static func throw_hops(day: BrewDay) -> float:
	var grams := day.weighed_g
	if grams <= 0.0:
		grams = minf(HANDFUL, day.hops_g)
		day.hops_g -= grams
	day.weighed_g = 0.0
	if Values.real(day.controls.hatch) < 0.5 or grams <= 0.0:
		return 0.0
	day.batch.add_hops(grams)
	return grams
