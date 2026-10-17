class_name BrewMarket
extends Node
## The brewery's trade in the valley (BrewHouse, BrewTrade): the stalls'
## wares bought, an order taken at the board or given up, a full keg handed
## over for an order or loaded onto the cart, the boards read by the
## crosshair; and the order taken led on step by step (BrewGuide): the
## parchment ticks the steps done, the arrow turns to the next task's place,
## the mark stands over its station (BrewGuidePanel).

## What E does at each kind of the trade's places.
const TRADE_KINDS := {"stall": "buy", "order_board": "order", "cart": "cart"}
## Why a ware is not bought, by BrewTrade.buy's word: a line of LineTable.BREWERY.
const REFUSALS := {"coins": &"no_coins", "full": &"no_room", "done": &"had_already", "order": &"mend_cask_first"}
## Metres within which the mark over a task's station shows.
const MARK_NEAR := 12.0

var house: BrewHouse
## Stall id -> the index of the ware its board offers (the mouse wheel).
var wares := {}
## The order the board offers to take, as the mouse wheel turns it.
var offer := 0
var guide_panel: BrewGuidePanel
var _player: Player
var _eye: BrewEye
## The task the parchment shows (its language, its step and its words), ""
## when it is closed.
var _guide_shown := ""

## The player whose eye reads the boards and whom the guide leads.
func attach(player: Player, eye: BrewEye) -> void:
	_player = player
	_eye = eye
	guide_panel = BrewGuidePanel.new()
	guide_panel.name = "GuidePanel"
	add_child(guide_panel)

## Whether utensil `id` is a keg the brewery does not have now: not bought
## yet, or away with the cart or an order.
func away(id: String) -> bool:
	return BrewKegRack.KEGS.has(id) and not house.trade.rack_kegs().has(id)

# ---- What E does at the trade's places -------------------------------------------

## The trade's place the eye is on within `best` metres: a stall to buy at;
## with a full keg in the hand, the order board or the cart; with an empty
## hand, the order board to take an order or give it up; {} when none
## (BrewWork.find_target).
func target(best: float, interactions: TavernInteractions) -> Dictionary:
	var stalls := house.stalls
	if stalls == null:
		return {}
	var trade := house.trade
	var found := {}
	for id: String in stalls.places:
		var place: Dictionary = stalls.places[id]
		var kind := str(TRADE_KINDS[place.kind])
		if kind == "order" and house.carry.held == "":
			if house.guide.taken():
				kind = "drop_order"
			elif not trade.orders.is_empty():
				kind = "take_order"
		if kind != "buy" and kind != "take_order" and kind != "drop_order" and not _keg_for_sale():
			continue
		for point: Vector3 in place.looks:
			var distance := interactions.target_distance(point, null, true)
			if distance < best:
				best = distance
				found = BrewWork.target_of(kind, id, distance)
	return found

## Whether the hand holds a full keg under its bung.
func _keg_for_sale() -> bool:
	var cellar := house.cellar
	if not cellar.rack.kegs.has(house.carry.held):
		return false
	var keg: Dictionary = cellar.rack.kegs[house.carry.held]
	return keg.bunged and Values.real(keg.liters) >= BrewTrade.SALE_L

## The beer of the keg in the hand.
func _held_beer() -> Dictionary:
	var cellar := house.cellar
	return cellar.rack.kegs[house.carry.held].beer if cellar.rack.kegs.has(house.carry.held) else {}

## The ware stall `id`'s board offers now.
func _ware(id: String) -> String:
	var offered: Array = house.trade.stall(id).get("wares", [])
	return str(offered[posmod(Values.whole(wares.get(id, 0)), offered.size())]) if not offered.is_empty() else ""

## The prompt of a trade's target; "" for another kind.
func text(target: BrewWork.Target) -> String:
	var trade := house.trade
	var book := house.book
	var guide := house.guide
	match target.kind:
		"buy":
			var offered: Array = trade.stall(target.id).get("wares", [])
			var ware_id := _ware(target.id)
			var line := tr("{interact} — купить: %s · %d медн. · в кошельке %d") % [tr(str(trade.ware(ware_id).title)),
				trade.price(ware_id), trade.coins]
			return line + (tr("   ·   {choice} — другой товар") if offered.size() > 1 else "")
		"take_order":
			var open: Dictionary = trade.orders[posmod(offer, trade.orders.size())]
			var line := tr("{interact} — взять заказ · %s") % trade.order_words(open, book)
			return line + (tr("   ·   {choice} — другой заказ") if trade.orders.size() > 1 else "")
		"drop_order":
			return tr("{interact} — отказаться от заказа: он уйдёт с доски · %s") % tr(str(trade.template(guide.order_id).get("who", "")))
		"order":
			var index := trade.order_for(_held_beer(), book, guide.order_id)
			if index < 0:
				return "Бочонок не подходит ни к одному заказу"
			var order: Dictionary = trade.orders[index]
			return tr("{interact} — сдать бочонок по заказу · %s · %d медн.") % [tr(str(trade.template(str(order.id)).who)),
				trade.order_pay(order)]
		"cart":
			return tr("{interact} — погрузить бочонок на телегу · %d медн.") % trade.cart_price(_held_beer(), book)
	return ""

## What E does at a trade's target.
func act(target: BrewWork.Target) -> void:
	var trade := house.trade
	var book := house.book
	var guide := house.guide
	var lines := house.lines
	var readout := house.readout
	match target.kind:
		"buy":
			_buy(target.id)
		"take_order":
			guide.take(trade.orders[posmod(offer, trade.orders.size())], trade)
			readout.say(tr(lines.text(&"order_taken")) % tr(str(trade.template(guide.order_id).get("who", ""))))
			GameEvents.order_taken.emit(guide.order_id)
		"drop_order":
			# A refused order leaves the board: its term ran from the taking.
			var dropped := guide.order_id
			trade.orders.assign(trade.orders.filter(func(order: Dictionary) -> bool: return str(order.id) != dropped))
			guide.drop()
			readout.say(lines.text(&"order_dropped"))
			GameEvents.order_dropped.emit(dropped)
		"order":
			var keg := house.carry.held
			var index := trade.order_for(_held_beer(), book, guide.order_id)
			var guided := index >= 0 and str(trade.orders[index].id) == guide.order_id
			var order_id := str(trade.orders[index].id) if index >= 0 else ""
			var paid := trade.deliver(keg, _held_beer(), book, guide.order_id)
			if guided and paid > 0:
				guide.delivered()
			if paid > 0:
				_sold(keg, tr(lines.text(&"order_delivered")) % [paid, trade.coins])
				GameEvents.order_delivered.emit(order_id, paid)
			else:
				readout.say(lines.text(&"no_order_fits"))
		"cart":
			var keg := house.carry.held
			var paid := trade.load_cart(keg, _held_beer(), book)
			_sold(keg, tr(lines.text(&"cart_loaded")) % [paid, trade.coins])

## A choice (`turn`, the mouse wheel) at the target E has: the next ware of a
## stall's board, or at the order board the next order. True when it was taken.
func turn(by: int, interactions: TavernInteractions) -> bool:
	if by == 0 or interactions == null:
		return false
	var selected: BrewWork.Target = interactions.selected if interactions.selected is BrewWork.Target else null
	if selected != null and selected.kind == "take_order":
		offer += by
		return true
	if selected == null or selected.kind != "buy":
		return false
	wares[selected.id] = Values.whole(wares.get(selected.id, 0)) + by
	return true

## The ware stall `id` offers bought: the coins left in its box.
func _buy(id: String) -> void:
	var trade := house.trade
	var ware_id := _ware(id)
	var refused := trade.buy(ware_id, house.day, house.cellar, house.maltings)
	if refused != "":
		var reason: StringName = REFUSALS[refused]
		house.readout.say("%s: %s" % [tr(house.lines.text(reason)), tr(str(trade.ware(ware_id).title))])
		return
	house.readout.say(tr(house.lines.text(&"bought")) % [tr(str(trade.ware(ware_id).title)), trade.coins])
	SaveService.save_soon()

## Keg `keg` in the hand went away with its beer: the hand is empty.
func _sold(keg: String, words: String) -> void:
	house.cellar.rack.empty_keg(keg)
	house.carry.held = ""
	house.layout.send_home(keg)
	if _player != null:
		_player.pace = 1.0
	house.readout.say(words)
	SaveService.save_soon()

## What the eye reads off the trade's place looked at: a stall's price board,
## the order board's orders, the cart's terms; "" when none is looked at.
func reading() -> String:
	var stalls := house.stalls
	if stalls == null:
		return ""
	var trade := house.trade
	for id: String in stalls.places:
		var place: Dictionary = stalls.places[id]
		var looked := false
		for point: Vector3 in place.looks:
			looked = looked or _eye.aimed(point) < INF
		if not looked:
			continue
		match str(place.kind):
			"stall":
				var prices := PackedStringArray()
				for ware_id: Variant in trade.stall(id).get("wares", []):
					prices.append("%s — %d" % [tr(str(trade.ware(str(ware_id)).title)), trade.price(str(ware_id))])
				return "%s: %s" % [tr(str(place.title)), "; ".join(prices)]
			"order_board":
				if trade.orders.is_empty():
					return "Доска заказов пуста"
				var orders := PackedStringArray()
				for order: Dictionary in trade.orders:
					orders.append(trade.order_words(order, house.book))
				return tr("Заказы · %s") % " · ".join(orders)
			"cart":
				return "Телега берёт бочонки за половину цены Борра, кислое пиво — на уксус"
	return ""

# ---- The guide of the order taken -----------------------------------------------

## The order taken led on: the steps done are ticked on the parchment, the
## arrow turns to the next task's place, the mark stands over its station.
func lead() -> void:
	if guide_panel == null or _player == null:
		return
	var guide := house.guide
	var trade := house.trade
	var book := house.book
	if not guide.taken():
		if guide.ended == "late":
			house.readout.say(house.lines.text(&"order_late"))
			guide.ended = ""
		if _guide_shown != "" and not guide_panel.ticking():
			guide_panel.close()
			_guide_shown = ""
		return
	var entry := guide.current()
	var done := guide.update(house.day, house.cellar, trade, book,
		_place_distance(str(entry.get("place", ""))) <= _arrive(entry))
	if _guide_shown == "":
		guide_panel.open("")
	for _step in done:
		guide_panel.tick()
	if not guide.taken():
		if guide.ended == "":
			house.readout.say(house.lines.text(&"order_done"))
		guide_panel.point(false, 0.0, "")
		guide_panel.mark(false, Vector2.ZERO)
		return
	var order := _guided_order()
	if not order.is_empty():
		guide_panel.open(tr("Заказ · %s") % trade.order_words(order, book))
	entry = guide.current()
	var task := tr(str(entry.text))
	if str(entry.done[0]) == "kegs" or str(entry.done[0]) == "delivered":
		task += tr(" Бочонков по заказу: %d, готово: %d.") % [guide.kegs_left, guide.full_kegs(house.cellar, trade, book)]
	# The language is part of what is shown: the parchment is written anew in another.
	var shown := "%s %d %s" % [TranslationServer.get_locale(), guide.step, task]
	if shown != _guide_shown:
		guide_panel.task(task, guide.step, guide.active().size())
		guide_panel.note(_guide_note())
		_guide_shown = shown
	_point_guide(entry)

## The open order the guide leads, {} when the board has it no more.
func _guided_order() -> Dictionary:
	for order: Dictionary in house.trade.orders:
		if str(order.id) == house.guide.order_id:
			return order
	return {}

## A warning for the parchment: the beer in the cellar is not of the order's sort.
func _guide_note() -> String:
	var latest := house.cellar.latest_batch()
	if latest == null or latest.ferment < 1.0:
		return ""
	var named := house.book.name_beer(BrewTaste.profile(latest))
	if str(named.get("id", "")) == house.guide.beer:
		return ""
	return tr("Партия в погребе вышла другим сортом: «%s». Этот заказ её не возьмёт.") % tr(str(named.get("name", "")))

## Where task place `id` is in the world: the brewery's gates, a stall, the
## order board.
func place_point(id: String) -> Vector3:
	var stalls := house.stalls
	if id != "brewery" and stalls != null and stalls.places.has(id):
		var looks: Array = stalls.places[id].looks
		if not looks.is_empty():
			return looks[0]
	return house.to_global(house.layout.stand("gate"))

## Metres on the ground from the player to task place `id`.
func _place_distance(id: String) -> float:
	var point := place_point(id)
	return Vector2(point.x - _player.global_position.x, point.z - _player.global_position.z).length()

## Metres within which the player is at the place of task `entry`.
func _arrive(entry: Dictionary) -> float:
	var place: Dictionary = house.guide.places.get(str(entry.get("place", "")), {})
	return Values.real(place.get("arrive", BrewWork.STAND))

## The arrow to the task's place while the player is far from it; near, the
## mark over the task's station.
func _point_guide(entry: Dictionary) -> void:
	var camera := _eye.camera
	var place := str(entry.get("place", ""))
	var distance := _place_distance(place)
	var far := distance > _arrive(entry)
	if far:
		var point := place_point(place)
		var forward := -camera.global_basis.z
		var ahead := Vector2(forward.x, forward.z)
		var toward := Vector2(point.x - camera.global_position.x, point.z - camera.global_position.z)
		var angle := ahead.angle_to(toward) if ahead.length() > 0.01 and toward.length() > 0.01 else 0.0
		var place_row: Dictionary = house.guide.places.get(place, {})
		var title := str(place_row.get("title", ""))
		guide_panel.point(true, angle, tr("%s · %d м") % [tr(title), roundi(distance)])
	else:
		guide_panel.point(false, 0.0, "")
	var marked := str(entry.get("mark", ""))
	var shown := false
	var at := Vector2.ZERO
	var stations := house.layout.stations
	if not far and stations.has(marked) and house.work.station == null:
		var look := house.to_global(house.layout.look(marked))
		if look.distance_to(camera.global_position) < MARK_NEAR and not camera.is_position_behind(look):
			shown = true
			at = camera.unproject_position(look)
	guide_panel.mark(shown, at)
