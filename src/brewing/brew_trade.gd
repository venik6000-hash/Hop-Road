class_name BrewTrade
extends RefCounted
## The brewing's economy (docs/plans/brewing.md, section 6): the player's
## copper coins, the trust stalls of the valley, Borr's price for a keg, the
## order board at the market and the cart at the cellar gates. Wares, prices
## and orders are assets/brewing/trade.json; what a ware gives the brewery is
## here (buy). The coins are kept in ValleyLoop's section of the save, the
## rest in the brewery's (BrewHouse.to_dict).
##
## Kegs: the brewery owns the first `kegs_owned` kegs of the rack
## (BrewKegRack.KEGS); the cooperage sells the others one by one. A keg the
## cart or an order takes is `away` and comes back empty at the next dawn.

const DATA := "res://assets/brewing/trade.json"
## Logs the woodpiles hold at most, of spruce and of beech.
const WOOD_CAP := {"log": 80, "beech_log": 40}
## Logs a bundle of the market gives.
const BUNDLE := {BrewIds.WARE_LOGS: ["log", 20], BrewIds.WARE_BEECH_LOGS: ["beech_log", 10]}
## Litres of starter the herbalist's ware puts into the yeast crock.
const YEAST_L := 1.0
## Days of the chain from the raw stuff to a keg at the board, besides the
## ageing (BrewBatch.AGE_DAYS): the brewing day and its night of cooling, the
## fermentation at the cellar's 10°, a day to fill the kegs and carry them.
const BREW_DAYS := 2
const FERMENT_DAYS := 5
const DELIVER_DAYS := 1
## Below this a sack or the hop basket is not full and a new one is bought.
const FULL_SLACK := 0.5
const HOPS_SLACK := 50.0
## Litres a keg must hold for the order board and the cart to take it.
const SALE_L := BrewKegRack.KEG_L - 2.0
## What the herbalist's and the market's raw stuff fills: the property of the
## brewing day or the cellar, and how much a ware holds.
const RAW := {BrewIds.WARE_HONEY: ["honey_kg", BrewDay.HONEY_POT_KG], BrewIds.WARE_LINDEN: ["linden_kg", BrewDay.LINDEN_KG],
	BrewIds.WARE_JUNIPER: ["juniper_kg", BrewDay.JUNIPER_KG], BrewIds.WARE_CHERRIES: ["cherries_kg", BrewCellar.CHERRY_BASKET_KG]}

## The data of trade.json.
var data: Dictionary = {}
var coins := 0
var kegs_owned := 0
var away: Array[String] = []
## Logs on the woodpiles: "log" (spruce), "beech_log".
var wood := {}
## Open orders: {id (of trade.json's orders), kegs_left, days_left, taken}.
## An order not taken hangs on the board `days_left`; a taken one is due in
## `days_left` (take).
var orders: Array[Dictionary] = []
## The order of trade.json the board shows next.
var next_order := 0

static func load_file(path := DATA) -> BrewTrade:
	var parsed: Variant = DataFile.read(path, BrewingSchemas.trade())
	return BrewTrade.new(Values.table(parsed if parsed is Dictionary else {}))

func _init(of_data: Dictionary = {}) -> void:
	data = of_data
	coins = Values.whole(data.get("start_coins", 0))
	kegs_owned = Values.whole(data.get("start_kegs", BrewKegRack.KEGS.size()))
	var start: Dictionary = data.get("start_wood", {})
	for id: String in WOOD_CAP:
		wood[id] = Values.whole(start.get(id, 0))
	if not template_list().is_empty():
		_open_next()

# ---- Data ------------------------------------------------------------------------

func ware(id: String) -> Dictionary:
	return Values.table(data.get("wares", {})).get(id, {})

func price(ware_id: String) -> int:
	return Values.whole(ware(ware_id).get("price", 0))

func stalls() -> Array:
	return data.get("stalls", [])

func stall(id: String) -> Dictionary:
	for entry: Dictionary in stalls():
		if entry.id == id:
			return entry
	return {}

func template_list() -> Array:
	return data.get("orders", [])

func template(id: String) -> Dictionary:
	for entry: Dictionary in template_list():
		if entry.id == id:
			return entry
	return {}

# ---- Buying ----------------------------------------------------------------------

## Ware `ware_id` bought: its price paid, what it gives put into the brewery.
## "" when it is bought, else why not: "coins" (too few), "full" (no room for
## it), "done" (the brewery has it already), "order" (mend the third cask first).
func buy(ware_id: String, day: BrewDay, cellar: BrewCellar, maltings: BrewMaltings) -> String:
	if not BrewIds.WARES.has(ware_id) or ware(ware_id).is_empty():
		return "done"
	var refused := _room_for(ware_id, day, cellar, maltings)
	if refused != "":
		return refused
	if coins < price(ware_id):
		return "coins"
	coins -= price(ware_id)
	match ware_id:
		BrewIds.WARE_BARLEY_SACK:
			var lots: Array[MaltLot] = [MaltLot.barley(BrewMaltings.SACK_KG)]
			maltings.sacks[_empty_barley_sack(maltings)] = lots
		BrewIds.WARE_OATS_SACK, BrewIds.WARE_PALE_MALT_SACK:
			day.sacks[ware_id] = Values.real(BrewDay.SACKS[ware_id][1])
		BrewIds.WARE_HOPS:
			day.hops_g = BrewDay.HOP_BASKET_G
		BrewIds.WARE_KEG:
			kegs_owned += 1
		BrewIds.WARE_MEND_TUN_2:
			cellar.sound_tuns = 2
		BrewIds.WARE_MEND_CASK_3:
			cellar.sound_casks = 3
		BrewIds.WARE_MEND_CASK_4:
			cellar.sound_casks = 4
		BrewIds.WARE_YEAST:
			cellar.crock_l = minf(BrewCellar.CROCK_L, cellar.crock_l + YEAST_L)
		BrewIds.WARE_LOGS, BrewIds.WARE_BEECH_LOGS:
			var bundle: Array = BUNDLE[ware_id]
			wood[bundle[0]] = mini(Values.whole(WOOD_CAP[bundle[0]]), Values.whole(wood[bundle[0]]) + Values.whole(bundle[1]))
		BrewIds.WARE_FINE_THERMOMETER:
			day.fine_thermometer = true
		BrewIds.WARE_FULL_WEIGHTS:
			day.full_weights = true
		BrewIds.WARE_HONEY, BrewIds.WARE_LINDEN, BrewIds.WARE_JUNIPER, BrewIds.WARE_CHERRIES:
			_raw_holder(ware_id, day, cellar).set(str(RAW[ware_id][0]), Values.real(RAW[ware_id][1]))
	return ""

## The brewing day or the cellar, whichever keeps the raw stuff of `ware_id`.
static func _raw_holder(ware_id: String, day: BrewDay, cellar: BrewCellar) -> Object:
	return cellar if ware_id == BrewIds.WARE_CHERRIES else day

## Why ware `ware_id` cannot be taken now, "" when it can.
func _room_for(ware_id: String, day: BrewDay, cellar: BrewCellar, maltings: BrewMaltings) -> String:
	match ware_id:
		BrewIds.WARE_BARLEY_SACK:
			return "full" if _empty_barley_sack(maltings) == "" else ""
		BrewIds.WARE_OATS_SACK, BrewIds.WARE_PALE_MALT_SACK:
			return "full" if Values.real(day.sacks[ware_id]) > Values.real(BrewDay.SACKS[ware_id][1]) - FULL_SLACK else ""
		BrewIds.WARE_HOPS:
			return "full" if day.hops_g > BrewDay.HOP_BASKET_G - HOPS_SLACK else ""
		BrewIds.WARE_KEG:
			return "full" if kegs_owned >= BrewKegRack.KEGS.size() else ""
		BrewIds.WARE_MEND_TUN_2:
			return "done" if cellar.sound_tuns >= 2 else ""
		BrewIds.WARE_MEND_CASK_3:
			return "done" if cellar.sound_casks >= 3 else ""
		BrewIds.WARE_MEND_CASK_4:
			if cellar.sound_casks >= 4:
				return "done"
			return "order" if cellar.sound_casks < 3 else ""
		BrewIds.WARE_YEAST:
			return "full" if cellar.crock_l > BrewCellar.CROCK_L - YEAST_L else ""
		BrewIds.WARE_LOGS, BrewIds.WARE_BEECH_LOGS:
			var bundle: Array = BUNDLE[ware_id]
			return "full" if Values.whole(wood[bundle[0]]) + Values.whole(bundle[1]) > Values.whole(WOOD_CAP[bundle[0]]) else ""
		BrewIds.WARE_FINE_THERMOMETER:
			return "done" if day.fine_thermometer else ""
		BrewIds.WARE_FULL_WEIGHTS:
			return "done" if day.full_weights else ""
		BrewIds.WARE_HONEY, BrewIds.WARE_LINDEN, BrewIds.WARE_JUNIPER, BrewIds.WARE_CHERRIES:
			var held := Values.real(_raw_holder(ware_id, day, cellar).get(str(RAW[ware_id][0])))
			return "full" if held > Values.real(RAW[ware_id][1]) * 0.5 else ""
	return ""

## The first empty barley sack of the maltings, "" when none is empty.
static func _empty_barley_sack(maltings: BrewMaltings) -> String:
	for id: String in BrewIds.BARLEY_SACKS:
		if maltings.sack_kg(id) < 0.01:
			return id
	return ""

## The kegs on the rack: owned and not away.
func rack_kegs() -> Array[String]:
	var result: Array[String] = []
	for index in mini(kegs_owned, BrewKegRack.KEGS.size()):
		if not away.has(BrewKegRack.KEGS[index]):
			result.append(BrewKegRack.KEGS[index])
	return result

## A log of `id` ("log", "beech_log") is on its woodpile to be taken.
func has_log(id: String) -> bool:
	return Values.whole(wood.get(id, 1)) > 0

## A log of `id` taken from a woodpile of the valley: it is the brewery's
## while it is carried, as if taken from its own pile.
func gather_log(id: String) -> void:
	if wood.has(id):
		wood[id] = mini(Values.whole(WOOD_CAP[id]), Values.whole(wood[id]) + 1)

## A log of `id` thrown into a fire.
func burn_log(id: String) -> void:
	if wood.has(id):
		wood[id] = maxi(0, Values.whole(wood[id]) - 1)

# ---- Selling ---------------------------------------------------------------------

## Coins Borr gives for a keg of `beer` (BrewTaste.profile): the price of its
## sort by the book, times its quality; 0 for a spoiled batch, which he does
## not take.
func borr_price(beer: Dictionary, book: BrewBook) -> int:
	if beer.get("ruined", false):
		return 0
	var base := _base(beer, book)
	return maxi(1, roundi(base * Values.real(beer.get("quality", 0.0))))

func _base(beer: Dictionary, book: BrewBook) -> float:
	var prices: Dictionary = data.get("beer_prices", {})
	return Values.real(prices.get(str(book.name_beer(beer).get("id", "nameless")), prices.get("nameless", 0)))

## Coins the cart gives for a keg: half Borr's price; for a spoiled batch
## half the price of spoiled beer.
func cart_price(beer: Dictionary, book: BrewBook) -> int:
	var share := Values.real(data.get("cart_share", 0.5))
	var full := _base(beer, book) if beer.get("ruined", false) else float(borr_price(beer, book))
	return maxi(1, roundi(full * share))

## Coins an order pays for a keg of its sort: Borr's price of its sort at
## full quality, marked up.
func order_pay(order: Dictionary) -> int:
	var prices: Dictionary = data.get("beer_prices", {})
	var beer := str(template(str(order.id)).get("beer", ""))
	return roundi(Values.real(prices.get(beer, 0)) * Values.real(data.get("order_markup", 1.0)))

## Borr takes keg `beer` onto his counter: the coins he gives.
func sell_to_borr(beer: Dictionary, book: BrewBook) -> int:
	var paid := borr_price(beer, book)
	coins += paid
	return paid

## The open order the keg of `beer` fits (its sort by the book), -1 for none:
## order `prefer` (an order id) when it fits, else the first that does.
func order_for(beer: Dictionary, book: BrewBook, prefer := "") -> int:
	if beer.get("ruined", false):
		return -1
	var sort := str(book.name_beer(beer).get("id", ""))
	var found := -1
	for index in orders.size():
		if str(template(str(orders[index].id)).get("beer", "")) != sort:
			continue
		if str(orders[index].id) == prefer:
			return index
		if found < 0:
			found = index
	return found

## Keg `keg` of `beer` delivered to the order board: the coins paid, 0 when no
## open order takes it. The keg goes to order `prefer` when it fits
## (order_for). The keg goes away; an order with no kegs left is done.
func deliver(keg: String, beer: Dictionary, book: BrewBook, prefer := "") -> int:
	var index := order_for(beer, book, prefer)
	if index < 0:
		return 0
	var order := orders[index]
	var paid := order_pay(order)
	coins += paid
	order.kegs_left = Values.whole(order.kegs_left) - 1
	if Values.whole(order.kegs_left) <= 0:
		orders.remove_at(index)
	_send_away(keg)
	return paid

## Keg `keg` of `beer` loaded on the cart: the coins paid. The keg goes away.
func load_cart(keg: String, beer: Dictionary, book: BrewBook) -> int:
	var paid := cart_price(beer, book)
	coins += paid
	_send_away(keg)
	return paid

func _send_away(keg: String) -> void:
	if not away.has(keg):
		away.append(keg)

# ---- Days --------------------------------------------------------------------------

## A new day: the kegs away come back empty (returned, for the rack); each
## order has a day less, the late ones are dropped; the board fills up.
func dawn() -> Array[String]:
	var back := away.duplicate()
	away.clear()
	for index in range(orders.size() - 1, -1, -1):
		orders[index].days_left = Values.whole(orders[index].days_left) - 1
		if Values.whole(orders[index].days_left) < 0:
			orders.remove_at(index)
	if orders.size() < Values.whole(data.get("open_orders", 0)):
		_open_next()
	return back

func _open_next() -> void:
	var list := template_list()
	if list.is_empty():
		return
	var entry: Dictionary = list[next_order % list.size()]
	next_order = (next_order + 1) % list.size()
	orders.append({"id": str(entry.id), "kegs_left": Values.whole(entry.kegs), "days_left": Values.whole(entry.days), "taken": false})

## Days of the whole chain for a keg of sort `beer` (recipes.json's id).
static func chain_days(beer: String) -> int:
	var age := BrewBatch.CHERRY_AGE_DAYS if beer == BrewIds.SORT_CHERRY_DARK else BrewBatch.AGE_DAYS
	return BREW_DAYS + FERMENT_DAYS + age + DELIVER_DAYS

## Days a taken order `id` gives: its own days and the chain of its sort.
func due_days(id: String) -> int:
	var entry := template(id)
	return Values.whole(entry.get("days", 0)) + chain_days(str(entry.get("beer", "")))

## Takes open order `index`: its term starts now and holds the chain of its sort.
func take(index: int) -> void:
	orders[index].taken = true
	orders[index].days_left = due_days(str(orders[index].id))

## An open order as the board says it: how long an order not taken hangs, the
## days it gives when taken; the days left of a taken one. Translated.
func order_words(order: Dictionary, book: BrewBook) -> String:
	var entry := template(str(order.id))
	var beer := tr(str(book.recipe(str(entry.get("beer", ""))).get("name", entry.get("beer", ""))))
	var taken: bool = order.get("taken", false)
	var left := Values.whole(order.days_left)
	var due := left if taken else due_days(str(order.id))
	var term := tr_n("срок %d день", "срок %d дня", due) % due
	if not taken:
		term = tr_n("висит %d день", "висит %d дня", left) % left + ", " + term
	return tr("%s: %s × %d, %s, %d медн.") % [tr(str(entry.get("who", ""))), beer, Values.whole(order.kegs_left), term, order_pay(order)]

# ---- Save --------------------------------------------------------------------------

## The trade as plain data for the brewery's section; the coins are ValleyLoop's.
func to_dict() -> Dictionary:
	return {"kegs_owned": kegs_owned, "away": away.duplicate(), "wood": wood.duplicate(), "orders": orders.duplicate(true),
		"next_order": next_order}

## Reads back to_dict() through JSON; what is missing or wrong keeps the start's.
func restore(saved: Dictionary) -> void:
	kegs_owned = int(Values.number(saved.get("kegs_owned"), kegs_owned, 0, BrewKegRack.KEGS.size()))
	var saved_away: Variant = saved.get("away")
	if saved_away is Array:
		away.clear()
		for keg: Variant in saved_away:
			if keg is String and BrewKegRack.KEGS.has(keg) and not away.has(keg):
				away.append(keg)
	var saved_wood: Variant = saved.get("wood")
	if saved_wood is Dictionary:
		var wood_rows: Dictionary = saved_wood
		for id: String in WOOD_CAP:
			wood[id] = int(Values.number(wood_rows.get(id), Values.real(wood[id]), 0, Values.real(WOOD_CAP[id])))
	var saved_orders: Variant = saved.get("orders")
	if saved_orders is Array:
		orders.clear()
		for item: Variant in saved_orders:
			if not item is Dictionary:
				continue
			var order: Dictionary = item
			if order.get("id") is String and not template(str(order.id)).is_empty():
				orders.append({"id": order.id, "kegs_left": int(Values.number(order.get("kegs_left"), 1, 1, 100)),
					"days_left": int(Values.number(order.get("days_left"), 0, 0, 1000)), "taken": order.get("taken") == true})
	next_order = int(Values.number(saved.get("next_order"), next_order, 0, maxi(0, template_list().size() - 1)))
