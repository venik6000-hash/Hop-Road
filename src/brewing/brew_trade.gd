class_name BrewTrade
extends RefCounted
## The brewing's economy (docs/plans/brewing.md, section 6): the player's
## copper coins, the trust stalls of the valley, Borr's price for a keg, the
## order board at the market and the cart at the cellar gates. Wares, prices
## and orders are assets/brewing/trade.json; what a ware gives the brewery is
## here (buy). The coins are kept in ValleyLoop's save, the rest in the
## brewery's (BrewHouse.to_dict).
##
## Kegs: the brewery owns the first `kegs_owned` kegs of the rack
## (BrewCellar.KEGS); the cooperage sells the others one by one. A keg the
## cart or an order takes is `away` and comes back empty at the next dawn.

const DATA := "res://assets/brewing/trade.json"
## Logs the woodpiles hold at most, of spruce and of beech.
const WOOD_CAP := {"log": 80, "beech_log": 40}
## Logs a bundle of the market gives.
const BUNDLE := {"logs": ["log", 20], "beech_logs": ["beech_log", 10]}
## Litres of starter the herbalist's ware puts into the yeast crock.
const YEAST_L := 1.0
## Below this a sack or the hop basket is not full and a new one is bought.
const FULL_SLACK := 0.5
const HOPS_SLACK := 50.0
## Wares whose effect buy() knows; the test checks the data against it.
const KNOWN_WARES: Array[String] = ["barley_sack", "oats_sack", "pale_malt_sack", "hops", "keg", "mend_tun_2",
	"mend_cask_3", "mend_cask_4", "yeast", "logs", "beech_logs", "fine_thermometer", "full_weights", "honey", "linden",
	"juniper", "cherries"]
## What the herbalist's and the market's raw stuff fills: the property of the
## brewing day or the cellar, and how much a ware holds.
const RAW := {"honey": ["honey_kg", BrewDay.HONEY_POT_KG], "linden": ["linden_kg", BrewDay.LINDEN_KG],
	"juniper": ["juniper_kg", BrewDay.JUNIPER_KG], "cherries": ["cherries_kg", BrewCellar.CHERRY_BASKET_KG]}

## The data of trade.json.
var data: Dictionary = {}
var coins := 0
var kegs_owned := 0
var away: Array[String] = []
## Logs on the woodpiles: "log" (spruce), "beech_log".
var wood := {}
## Open orders: {id (of trade.json's orders), kegs_left, days_left}.
var orders: Array[Dictionary] = []
## The order of trade.json the board shows next.
var next_order := 0

static func load_file(path := DATA) -> BrewTrade:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return BrewTrade.new(parsed if parsed is Dictionary else {})

func _init(of_data: Dictionary = {}) -> void:
	data = of_data
	coins = int(data.get("start_coins", 0))
	kegs_owned = int(data.get("start_kegs", BrewCellar.KEGS.size()))
	var start: Dictionary = data.get("start_wood", {})
	for id: String in WOOD_CAP:
		wood[id] = int(start.get(id, 0))
	if not template_list().is_empty():
		_open_next()

# ---- Data ------------------------------------------------------------------------

func ware(id: String) -> Dictionary:
	return (data.get("wares", {}) as Dictionary).get(id, {})

func price(ware_id: String) -> int:
	return int(ware(ware_id).get("price", 0))

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
	if not KNOWN_WARES.has(ware_id) or ware(ware_id).is_empty():
		return "done"
	var refused := _room_for(ware_id, day, cellar, maltings)
	if refused != "":
		return refused
	if coins < price(ware_id):
		return "coins"
	coins -= price(ware_id)
	match ware_id:
		"barley_sack":
			var lots: Array[MaltLot] = [MaltLot.barley(BrewMaltings.SACK_KG)]
			maltings.sacks[_empty_barley_sack(maltings)] = lots
		"oats_sack", "pale_malt_sack":
			day.sacks[ware_id] = float(BrewDay.SACKS[ware_id][1])
		"hops":
			day.hops_g = BrewDay.HOP_BASKET_G
		"keg":
			kegs_owned += 1
		"mend_tun_2":
			cellar.sound_tuns = 2
		"mend_cask_3":
			cellar.sound_casks = 3
		"mend_cask_4":
			cellar.sound_casks = 4
		"yeast":
			cellar.crock_l = minf(BrewCellar.CROCK_L, cellar.crock_l + YEAST_L)
		"logs", "beech_logs":
			var bundle: Array = BUNDLE[ware_id]
			wood[bundle[0]] = mini(int(WOOD_CAP[bundle[0]]), int(wood[bundle[0]]) + int(bundle[1]))
		"fine_thermometer":
			day.fine_thermometer = true
		"full_weights":
			day.full_weights = true
		"honey", "linden", "juniper", "cherries":
			_raw_holder(ware_id, day, cellar).set(str(RAW[ware_id][0]), float(RAW[ware_id][1]))
	return ""

## The brewing day or the cellar, whichever keeps the raw stuff of `ware_id`.
static func _raw_holder(ware_id: String, day: BrewDay, cellar: BrewCellar) -> Object:
	return cellar if ware_id == "cherries" else day

## Why ware `ware_id` cannot be taken now, "" when it can.
func _room_for(ware_id: String, day: BrewDay, cellar: BrewCellar, maltings: BrewMaltings) -> String:
	match ware_id:
		"barley_sack":
			return "full" if _empty_barley_sack(maltings) == "" else ""
		"oats_sack", "pale_malt_sack":
			return "full" if float(day.sacks[ware_id]) > float(BrewDay.SACKS[ware_id][1]) - FULL_SLACK else ""
		"hops":
			return "full" if day.hops_g > BrewDay.HOP_BASKET_G - HOPS_SLACK else ""
		"keg":
			return "full" if kegs_owned >= BrewCellar.KEGS.size() else ""
		"mend_tun_2":
			return "done" if cellar.sound_tuns >= 2 else ""
		"mend_cask_3":
			return "done" if cellar.sound_casks >= 3 else ""
		"mend_cask_4":
			if cellar.sound_casks >= 4:
				return "done"
			return "order" if cellar.sound_casks < 3 else ""
		"yeast":
			return "full" if cellar.crock_l > BrewCellar.CROCK_L - YEAST_L else ""
		"logs", "beech_logs":
			var bundle: Array = BUNDLE[ware_id]
			return "full" if int(wood[bundle[0]]) + int(bundle[1]) > int(WOOD_CAP[bundle[0]]) else ""
		"fine_thermometer":
			return "done" if day.fine_thermometer else ""
		"full_weights":
			return "done" if day.full_weights else ""
		"honey", "linden", "juniper", "cherries":
			var held := float(_raw_holder(ware_id, day, cellar).get(str(RAW[ware_id][0])))
			return "full" if held > float(RAW[ware_id][1]) * 0.5 else ""
	return ""

## The first empty barley sack of the maltings, "" when none is empty.
static func _empty_barley_sack(maltings: BrewMaltings) -> String:
	for id: String in BrewMaltings.SACKS:
		if maltings.sack_kg(id) < 0.01:
			return id
	return ""

## The kegs on the rack: owned and not away.
func rack_kegs() -> Array[String]:
	var result: Array[String] = []
	for index in mini(kegs_owned, BrewCellar.KEGS.size()):
		if not away.has(BrewCellar.KEGS[index]):
			result.append(BrewCellar.KEGS[index])
	return result

## A log of `id` ("log", "beech_log") is on its woodpile to be taken.
func has_log(id: String) -> bool:
	return int(wood.get(id, 1)) > 0

## A log of `id` thrown into a fire.
func burn_log(id: String) -> void:
	if wood.has(id):
		wood[id] = maxi(0, int(wood[id]) - 1)

# ---- Selling ---------------------------------------------------------------------

## Coins Borr gives for a keg of `beer` (BrewBatch.profile): the price of its
## sort by the book, times its quality; 0 for a spoiled batch, which he does
## not take.
func borr_price(beer: Dictionary, book: BrewBook) -> int:
	if beer.get("ruined", false):
		return 0
	var base := _base(beer, book)
	return maxi(1, roundi(base * float(beer.get("quality", 0.0))))

func _base(beer: Dictionary, book: BrewBook) -> float:
	var prices: Dictionary = data.get("beer_prices", {})
	return float(prices.get(str(book.name_beer(beer).get("id", "nameless")), prices.get("nameless", 0)))

## Coins the cart gives for a keg: half Borr's price; for a spoiled batch
## half the price of spoiled beer.
func cart_price(beer: Dictionary, book: BrewBook) -> int:
	var share := float(data.get("cart_share", 0.5))
	var full := _base(beer, book) if beer.get("ruined", false) else float(borr_price(beer, book))
	return maxi(1, roundi(full * share))

## Coins an order pays for a keg of its sort: Borr's price of its sort at
## full quality, marked up.
func order_pay(order: Dictionary) -> int:
	var prices: Dictionary = data.get("beer_prices", {})
	var beer := str(template(str(order.id)).get("beer", ""))
	return roundi(float(prices.get(beer, 0)) * float(data.get("order_markup", 1.0)))

## Borr takes keg `beer` onto his counter: the coins he gives.
func sell_to_borr(beer: Dictionary, book: BrewBook) -> int:
	var paid := borr_price(beer, book)
	coins += paid
	return paid

## The first open order the keg of `beer` fits (its sort by the book), -1 for none.
func order_for(beer: Dictionary, book: BrewBook) -> int:
	if beer.get("ruined", false):
		return -1
	var sort := str(book.name_beer(beer).get("id", ""))
	for index in orders.size():
		if str(template(str(orders[index].id)).get("beer", "")) == sort:
			return index
	return -1

## Keg `keg` of `beer` delivered to the order board: the coins paid, 0 when no
## open order takes it. The keg goes away; an order with no kegs left is done.
func deliver(keg: String, beer: Dictionary, book: BrewBook) -> int:
	var index := order_for(beer, book)
	if index < 0:
		return 0
	var order := orders[index]
	var paid := order_pay(order)
	coins += paid
	order.kegs_left = int(order.kegs_left) - 1
	if int(order.kegs_left) <= 0:
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
		orders[index].days_left = int(orders[index].days_left) - 1
		if int(orders[index].days_left) < 0:
			orders.remove_at(index)
	if orders.size() < int(data.get("open_orders", 0)):
		_open_next()
	return back

func _open_next() -> void:
	var list := template_list()
	if list.is_empty():
		return
	var entry: Dictionary = list[next_order % list.size()]
	next_order = (next_order + 1) % list.size()
	orders.append({"id": str(entry.id), "kegs_left": int(entry.kegs), "days_left": int(entry.days)})

## An open order as the board says it.
func order_words(order: Dictionary, book: BrewBook) -> String:
	var entry := template(str(order.id))
	var beer := str(book.recipe(str(entry.get("beer", ""))).get("name", entry.get("beer", "")))
	return "%s: %s × %d, %d дн., %d медн." % [str(entry.get("who", "")), beer, int(order.kegs_left), int(order.days_left),
		order_pay(order)]

# ---- Save --------------------------------------------------------------------------

## The trade as plain data for the brewery's save; the coins are ValleyLoop's.
func to_dict() -> Dictionary:
	return {"kegs_owned": kegs_owned, "away": away.duplicate(), "wood": wood.duplicate(), "orders": orders.duplicate(true),
		"next_order": next_order}

## Reads back to_dict() through JSON; what is missing or wrong keeps the start's.
func restore(saved: Dictionary) -> void:
	kegs_owned = int(_number(saved.get("kegs_owned"), kegs_owned, 0, BrewCellar.KEGS.size()))
	var saved_away: Variant = saved.get("away")
	if saved_away is Array:
		away.clear()
		for keg: Variant in saved_away:
			if keg is String and BrewCellar.KEGS.has(keg) and not away.has(keg):
				away.append(keg)
	var saved_wood: Variant = saved.get("wood")
	if saved_wood is Dictionary:
		for id: String in WOOD_CAP:
			wood[id] = int(_number(saved_wood.get(id), wood[id], 0, WOOD_CAP[id]))
	var saved_orders: Variant = saved.get("orders")
	if saved_orders is Array:
		orders.clear()
		for item: Variant in saved_orders:
			if item is Dictionary and item.get("id") is String and not template(item.id).is_empty():
				orders.append({"id": item.id, "kegs_left": int(_number(item.get("kegs_left"), 1, 1, 100)),
					"days_left": int(_number(item.get("days_left"), 0, 0, 1000))})
	next_order = int(_number(saved.get("next_order"), next_order, 0, maxi(0, template_list().size() - 1)))

static func _number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback
