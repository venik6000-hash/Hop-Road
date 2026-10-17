class_name BrewYeast
extends RefCounted
## The yeast's way in the cellar (BrewCellar): from the crock into the dipper,
## from the dipper into the wort of a fermenting tun, and the head of yeast
## skimmed off the beer back into the crock. The crock, the dipper and the
## tuns are the cellar's.

## Litres a game minute through a tipped dipper.
const DIPPER_FLOW := 2.0
## What a head of yeast skimmed gives back to the crock, litres.
const SKIM_YEAST := 0.5
## Passes of the skimmer that take a head off.
const SKIM_PASSES := 3

## Yeast from the crock into the dipper at `flow` for `minutes`.
static func dip_yeast(cellar: BrewCellar, flow: float, minutes: float) -> void:
	var liters := minf(minf(flow * DIPPER_FLOW * minutes, BrewCellar.DIPPER_L - cellar.dipper_l), cellar.crock_l)
	if liters > 0.0:
		cellar.crock_l -= liters
		cellar.dipper_l += liters

## The dipper tipped over tun `number` at `flow` for `minutes`: the yeast goes
## into its wort, or is wasted where there is none.
static func pour_dipper(cellar: BrewCellar, number: int, flow: float, minutes: float) -> void:
	var liters := minf(flow * DIPPER_FLOW * minutes, cellar.dipper_l)
	if liters <= 0.0:
		return
	cellar.dipper_l -= liters
	if cellar.tun_batch(number) != null and cellar.tun_l(number) > 1.0:
		cellar.tun_batch(number).pitch(liters)

## Whether a head of yeast stands on the beer fermenting in tun `number` to
## be skimmed.
static func head(cellar: BrewCellar, number := 1) -> bool:
	var batch := cellar.tun_batch(number)
	return batch != null and batch.stage == BrewIds.STAGE_PITCHED and batch.ferment_days >= 1 and batch.ferment < 1.0 \
		and not cellar.tuns[number - 1].skimmed

## `passes` of the skimmer over tun `number`; a head taken off gives yeast
## back to the crock.
static func skim(cellar: BrewCellar, number: int, passes: int) -> void:
	if passes <= 0 or not head(cellar, number):
		return
	var tun := cellar.tuns[number - 1]
	tun.passes = Values.whole(tun.passes) + passes
	if Values.whole(tun.passes) >= SKIM_PASSES:
		tun.skimmed = true
		cellar.crock_l = minf(BrewCellar.CROCK_L, cellar.crock_l + SKIM_YEAST)
