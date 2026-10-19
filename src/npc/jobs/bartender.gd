class_name NpcBarJob
extends NpcJob
## The innkeeper behind his counter: the keg, the tankard and the draw are his
## bar (NpcBarWork, at his place of work). Between orders he wipes the back
## edge of the counter. E orders a beer, he draws it, and E takes it.

## Where an order stands: none (he works the bar), the beer being drawn, the
## tankard being set down, the tankard full on the counter.
enum Order {WORKING, POURING, SERVING, READY}
## He wipes the back edge of his counter, between the brewed keg's place and
## his keg, one hand: NpcWipe's strip in his own space.
const BAR_WIPE := {"middle": 0.05, "across": 0.15, "near": 0.39, "far": 0.46, "rest": Vector3.ZERO}

var order := Order.WORKING

func setup(actor: VillageNPC) -> void:
	actor.wipe = add_wipe(actor, BAR_WIPE)

func place_work(population: NpcPopulation, actor: VillageNPC, _work: Dictionary) -> void:
	population.bartender = actor
	var bar := NpcBarWork.new()
	bar.name = "Bar"
	bar.actor = actor
	bar.transform = Transform3D(Basis(Vector3.UP, actor.work_yaw), actor.work_point)
	population.bar = bar
	population.add_child(bar)
	actor.bar = bar
	actor.posed.connect(bar.follow)

func tick(actor: VillageNPC, delta: float) -> void:
	if not actor.at_work():
		super(actor, delta)
		return
	var bar := actor.bar
	match order:
		Order.WORKING:
			actor.play("bar")
		Order.POURING, Order.SERVING:
			actor.play("idle")
			if bar == null:
				order = Order.WORKING
			elif bar.clock >= NpcBarWork.T_CLOSE:
				order = Order.SERVING
			if bar != null and bar.served:
				order = Order.READY
		Order.READY:
			actor.play("idle")

## Puts the bar back in order when he leaves it: nothing is being poured and
## nothing stands ready.
func leave(actor: VillageNPC) -> void:
	order = Order.WORKING
	if actor.bar != null:
		actor.bar.clear()
	actor.body.release(NpcBody.POUR)

func interaction_text(actor: VillageNPC) -> String:
	match order:
		Order.POURING: return tr("%s наливает пиво…") % tr(actor.title)
		Order.SERVING: return tr("%s подаёт кружку…") % tr(actor.title)
		Order.READY: return tr("{interact} — взять пиво · %s") % tr(actor.title)
	return tr("{interact} — заказать пиво · %s") % tr(actor.title)

func interact(actor: VillageNPC, player: Player) -> bool:
	if order == Order.WORKING:
		if actor.bar == null or not actor.bar.start():
			return false
		actor.stop_wiping()
		actor.poses.gesture(NpcBody.POUR, NpcBarWork.LENGTH)
		order = Order.POURING
		return true
	if order == Order.READY:
		player.viewmodel.refill(BrewHouse.draw_beer(actor.get_tree()))
		actor.bar.take()
		order = Order.WORKING
		return true
	return false

## Whether he takes an order now: no beer is being drawn or stands ready.
func takes_orders() -> bool:
	return order == Order.WORKING
