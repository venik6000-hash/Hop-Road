class_name BrewGuide
extends RefCounted
## The guide of an order taken at the order board (docs/plans/brewing.md,
## section 7.7): the steps from the purchase of the raw stuff to the keg at the
## board, one at a time. The steps are assets/brewing/guide.json; the steps of
## other sorts are left out. Each step is done by what the brewery holds
## (BrewDay, BrewCellar, BrewTrade), not by a key: a step the brewery has
## already done is passed without a word. No graphics here: BrewGuidePanel
## shows the parchment and the arrow.

const PATH := "res://assets/brewing/guide.json"
## Litres of hot water a cask takes to be scalded is BrewCellar's; litres
## under which a vessel counts as empty.
const EMPTY_L := 5.0
## Wort on the coolship enough to count as hoisted.
const COOLSHIP_L := 100.0
## Kg a sack pours out before it counts as poured.
const SACK_POURED := 5.0
## Litres of yeast that three dippers give.
const YEAST_L := 2.5

var places := {}
var steps: Array[Dictionary] = []

## The order taken: trade.json's order id, "" when none.
var order_id := ""
## The sort of the order (recipes.json's id) and kegs still to deliver.
var beer := ""
var kegs_left := 0
## The step now shown, among `active()`.
var step := 0
## The kg of the current step's sack when the step began ("sack" steps).
var mark_kg := -1.0
## Why the guide ended without the order done: "late" or "".
var ended := ""
## Whether no step has been shown since the order was taken.
var fresh := false

static func load_file() -> BrewGuide:
	var guide := BrewGuide.new()
	var data: Variant = DataFile.read(PATH, BrewingSchemas.guide())
	if data is Dictionary:
		var table: Dictionary = data
		guide.places = table.get("places", {})
		for entry: Variant in table.get("steps", []):
			if entry is Dictionary:
				guide.steps.append(entry)
	return guide

func taken() -> bool:
	return order_id != ""

## Takes open order `order` of the board (BrewTrade.orders): its term starts
## now (BrewTrade.take).
func take(order: Dictionary, trade: BrewTrade) -> void:
	for index in trade.orders.size():
		if str(trade.orders[index].id) == str(order.id):
			trade.take(index)
	order_id = str(order.id)
	beer = str(trade.template(order_id).get("beer", ""))
	kegs_left = Values.whole(order.kegs_left)
	step = 0
	mark_kg = -1.0
	ended = ""
	fresh = true

## Gives the order up.
func drop() -> void:
	order_id = ""
	beer = ""
	kegs_left = 0
	step = 0
	mark_kg = -1.0

## The steps of the order's sort.
func active() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in steps:
		if entry.has("sorts") and not Values.list(entry.sorts).has(beer):
			continue
		if entry.has("except") and Values.list(entry.except).has(beer):
			continue
		result.append(entry)
	return result

## The step now shown, {} when no order is taken or all are done.
func current() -> Dictionary:
	var list := active()
	return list[step] if taken() and step < list.size() else {}

## A keg of the order's sort delivered to the board.
func delivered() -> void:
	kegs_left = maxi(0, kegs_left - 1)

## The steps done since the last call, in order; the guide stands at the
## first step not done. `arrived` tells whether the player is at the current
## step's place. Steps done already as they come up, and steps passed before
## the first is shown, are passed silently: they are not in the result. A late
## order ends the guide (`ended`); an order filled ends it with the step shown
## ticked.
func update(day: BrewDay, cellar: BrewCellar, trade: BrewTrade, book: BrewBook, arrived: bool) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	if not taken():
		return done
	if kegs_left > 0 and not _open(trade):
		drop()
		ended = "late"
		return done
	var list := active()
	# Kegs of an earlier batch may fill the order before its steps are done.
	if kegs_left <= 0:
		if not fresh and step < list.size():
			done.append(list[step])
		drop()
		return done
	var first := true
	while step < list.size():
		var entry := list[step]
		if str(entry.done[0]) == "sack" and mark_kg < 0.0:
			mark_kg = Values.real(day.sacks.get(str(entry.done[1]), 0.0))
		if not passed(entry, day, cellar, trade, book, arrived and first):
			break
		if first and not fresh:
			done.append(entry)
		step += 1
		mark_kg = -1.0
		first = false
	fresh = false
	if step >= list.size():
		drop()
	return done

func _open(trade: BrewTrade) -> bool:
	for order: Dictionary in trade.orders:
		if str(order.id) == order_id:
			return true
	return false

## Whether step `entry` is done by what the brewery holds now.
func passed(entry: Dictionary, day: BrewDay, cellar: BrewCellar, trade: BrewTrade, book: BrewBook, arrived: bool) -> bool:
	var done: Array = entry.done
	var what := str(done[0])
	var number := Values.real(done[2]) if done.size() > 2 else (Values.real(done[1]) if done.size() > 1 and (done[1] is float or done[1] is int) else 0.0)
	var brewing := day.batch
	var brewed := _rank(brewing)
	var latest := cellar.latest_batch()
	var cellared := _rank(latest) if latest != null else -1
	match what:
		"arrive":
			return arrived
		"have":
			return _stock(str(done[1]), day, cellar, trade) >= number
		"copper_l":
			return day.copper_l >= number or brewed >= 1 or day.tun_water_l > EMPTY_L
		"fire":
			return day.fire > 0.0 or brewed >= 1 or day.tun_water_l > EMPTY_L
		"copper_temp":
			return day.copper_temp >= number or brewed >= 1 or day.tun_water_l > EMPTY_L
		"juniper":
			return brewing.juniper_kg > 0.0 or brewed >= 1 or day.tun_water_l > EMPTY_L
		"tun_water":
			return day.tun_water_l >= number or brewed >= 1
		"stage":
			return brewed >= BrewIds.STAGES.find(str(done[1]))
		"sack":
			return Values.real(day.sacks.get(str(done[1]), 0.0)) <= mark_kg - SACK_POURED or brewed >= 2
		"stirred":
			return brewing.stir_turns >= int(number) or brewed >= 2
		"converted":
			return brewing.conversion >= BrewBatch.CONVERTED or brewed >= 2
		"wort_in_copper":
			return (day.copper_wort and day.underback_l < EMPTY_L) or brewed >= 3
		"hops":
			return not brewing.hops.is_empty() or brewed >= 4
		"boiled":
			return brewing.boil_minutes >= number or brewed >= 4
		"fire_out":
			return brewing.fire_out or _handed(day, latest)
		"honey_in":
			return brewing.honey_kg > 0.0 or _handed(day, latest)
		"linden_in":
			return brewing.linden_kg > 0.0 or _handed(day, latest)
		"knocked_out":
			return (brewed >= 3 and day.copper_l < EMPTY_L) or day.hop_back_l > EMPTY_L or day.coolship_l > EMPTY_L \
				or _handed(day, latest)
		"on_coolship":
			return (day.coolship_l > COOLSHIP_L and day.hop_back_l < EMPTY_L and day.bucket_l < 1.0) or _handed(day, latest)
		"in_tun":
			return _handed(day, latest)
		"cool":
			return latest != null and (cellared >= 5 or (cellared == 4 and latest.wort_temp <= BrewBatch.YEAST_DIES))
		"pitched":
			return latest != null and (latest.yeast_l >= YEAST_L or latest.ferment_days > 0 or cellared >= 6)
		"skimmed":
			return latest != null and (latest.skimmed or cellared >= 6)
		"fermented":
			return latest != null and (latest.ferment >= 1.0 or cellared >= 6)
		"scalded":
			return _cask(cellar, latest) > 0 or _scalded(cellar) > 0
		"cherries_in_cask":
			var number_of := _scalded(cellar)
			return _cask(cellar, latest) > 0 or (number_of > 0 and Values.real(cellar.casks[number_of - 1].cherries) > 0.0)
		"racked":
			var cask := _cask(cellar, latest)
			return cask > 0 and cellar.tun_of(latest) == 0
		"cask_bunged":
			var cask := _cask(cellar, latest)
			return (cask > 0 and Values.flag(cellar.casks[cask - 1].bunged)) or full_kegs(cellar, trade, book) >= kegs_left
		"aged":
			var cask := _cask(cellar, latest)
			return (cask > 0 and latest.age_days >= latest.ready_days()) or full_kegs(cellar, trade, book) >= kegs_left
		"kegs":
			return full_kegs(cellar, trade, book) >= kegs_left
		"delivered":
			return kegs_left <= 0
	return false

## Kegs on the rack or in the hand, full, under their bung, of the order's sort.
func full_kegs(cellar: BrewCellar, trade: BrewTrade, book: BrewBook) -> int:
	var count := 0
	var rack := trade.rack_kegs()
	for id: String in cellar.rack.kegs:
		var keg: Dictionary = cellar.rack.kegs[id]
		var keg_beer: Dictionary = keg.beer
		if not rack.has(id) or not keg.bunged or Values.real(keg.liters) < BrewTrade.SALE_L or keg_beer.get("ruined", false):
			continue
		if str(book.name_beer(keg_beer).get("id", "")) == beer:
			count += 1
	return count

## What the brewery has of `id`: kg of a sack, g of hops, logs, litres of
## yeast, kg of honey, linden, juniper, cherries.
static func _stock(id: String, day: BrewDay, cellar: BrewCellar, trade: BrewTrade) -> float:
	match id:
		"hops":
			return day.hops_g
		"logs":
			return Values.real(trade.wood.get("log", 0))
		"yeast":
			return cellar.crock_l
		"honey":
			return day.honey_kg
		"linden":
			return day.linden_kg
		"juniper":
			return day.juniper_kg
		"cherries":
			return cellar.cherries_kg
	return Values.real(day.sacks.get(id, 0.0))

## Whether the brewing day has handed its wort to a fermenting tun.
static func _handed(day: BrewDay, latest: BrewBatch) -> bool:
	return _rank(day.batch) == 0 and latest != null and _rank(latest) >= 4 and day.coolship_l < EMPTY_L

static func _rank(batch: BrewBatch) -> int:
	return BrewIds.STAGES.find(batch.stage) if batch != null else -1

## The lager cask (1..) holding `batch`, 0 for none.
static func _cask(cellar: BrewCellar, batch: BrewBatch) -> int:
	if batch == null:
		return 0
	for index in cellar.casks.size():
		if cellar.casks[index].batch == batch:
			return index + 1
	return 0

## The first sound, empty, scalded lager cask (1..), 0 for none.
static func _scalded(cellar: BrewCellar) -> int:
	for number in range(1, cellar.casks.size() + 1):
		if cellar.sound_cask(number) and cellar.casks[number - 1].batch == null and cellar.scalded(number):
			return number
	return 0

# ---- Save -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"order": order_id, "beer": beer, "kegs_left": kegs_left, "step": step, "mark_kg": mark_kg}

func restore(saved: Dictionary) -> void:
	order_id = str(saved.get("order", ""))
	beer = str(saved.get("beer", ""))
	kegs_left = int(Values.number(saved.get("kegs_left"), 0.0, 0.0, 100.0))
	step = int(Values.number(saved.get("step"), 0.0, 0.0, float(steps.size())))
	mark_kg = Values.number(saved.get("mark_kg"), -1.0, -1.0, 1000.0)
