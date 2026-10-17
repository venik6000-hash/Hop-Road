class_name BrewHouse
extends Node3D
## The brewing in the brewery's rooms (docs/plans/brewing.md, stages 2 and 3):
## the brewery's table (brewery.json) made to work. It owns the rules of the
## day, the cellar, the maltings and the trade (BrewDay, BrewCellar,
## BrewMaltings, BrewTrade, BrewGuide, BrewCarry), runs them by the sky's
## clock, keeps them in the save, and wires the parts that each do one thing:
##
## - BrewLayout: where things are (anchors, stations, utensils, surfaces).
## - BrewWork: what E and the mouse do (stations, carrying, the book).
## - BrewMarket: the trade's places and the order taken led on.
## - BrewBody: the player's body and arms at the work.
## - BrewLook: surfaces, streams, steam, fires, poses and their sounds.
## - BrewReadout: the line by the crosshair.
##
## A full keg carried to the tavern's counter is the one Borr buys and pours
## from (draw_beer). TavernInteractions asks the brewery for what E can do
## (attach). It stands in the building's frame.

const GROUP := &"brew_house"

## Set before it enters the tree: the building's table and the building.
var table: Dictionary:
	set(value):
		table = value
		layout = BrewLayout.new(self, value)
var building: VillageBuilding
## What the brewery says by the crosshair, by id.
var lines := LineTable.read(LineTable.BREWERY, BrewingSchemas.lines())
var day: BrewDay
var book: BrewBook
var cellar := BrewCellar.new()
var maltings := BrewMaltings.new()
var trade := BrewTrade.load_file()
## The trade's places in the valley; null until the level stands them.
var stalls: BrewStalls
var carry := BrewCarry.new()
var guide := BrewGuide.load_file()
var layout: BrewLayout
var work := BrewWork.new()
var market := BrewMarket.new()
var body := BrewBody.new()
var look := BrewLook.new()
var readout := BrewReadout.new()
## The sky's hour at the last frame; below 0 before the first.
var last_hour := -1.0
## The batch's stage at the last look (BrewBatch.stage).
var _stage := ""

func _init() -> void:
	add_to_group(GROUP)
	work.house = self
	market.house = self
	body.house = self
	look.house = self
	readout.house = self
	work.name = "Work"
	market.name = "Market"
	body.name = "Body"
	look.name = "Look"
	readout.name = "Readout"
	for part: Node in [work, market, body, look, readout]:
		add_child(part)

func _ready() -> void:
	day = BrewDay.new()
	day.capacity = BrewDay.capacities(table)
	book = BrewBook.load_files()
	look.build()
	_stage = day.batch.stage
	GameEvents.night_slept.connect(pass_hours)

## The trade's stalls, board and cart for the level to stand.
func make_stalls() -> BrewStalls:
	stalls = BrewStalls.new()
	stalls.name = "BrewStalls"
	stalls.build(trade)
	return stalls

## Takes the utensils and the vessels' surfaces out of a part scene
## (BrewLayout.take), before the building batches what is left.
func take(scene: Node3D) -> void:
	layout.take(scene, BrewLook.LIQUID, BrewLook.DEEP_WATER)

## The player's hands and eyes; TavernInteractions calls it once it stands.
func attach(interactions: TavernInteractions) -> void:
	var eye := BrewEye.new(interactions.player, interactions.camera)
	readout.attach(eye)
	body.attach(interactions.player, eye)
	market.attach(interactions.player, eye)
	work.attach(interactions, eye)
	if building != null and building.sky_system != null:
		last_hour = building.sky_system.time_of_day

## The level the brewery stands in: carried things and the counter's keg are its.
func level() -> Node:
	return building.get_parent() if building != null and building.get_parent() != null else self

func _process(delta: float) -> void:
	var minutes := _tick_clock()
	tell_stage()
	work.update(delta, minutes)
	look.settle()
	body.update(delta)
	look.run(delta)
	market.lead()
	readout.update(delta)

## GameEvents hears when the batch comes to another stage.
func tell_stage() -> void:
	if day.batch.stage != _stage:
		_stage = day.batch.stage
		GameEvents.brew_stage_changed.emit(_stage)

## Game minutes since the last frame go into the day and the cellar; the
## clock turned back (a debug key) gives none.
func _tick_clock() -> float:
	if building == null or building.sky_system == null:
		return 0.0
	var minutes := 0.0
	var hour := building.sky_system.time_of_day
	if last_hour >= 0.0:
		minutes = maxf(0.0, wrapf(hour - last_hour, -12.0, 12.0)) * 60.0
		advance(minutes, last_hour)
	last_hour = hour
	return minutes

## The night slept away goes by in the brewery too (GameEvents.night_slept):
## the clock already stands at the morning.
func pass_hours(hours: float) -> void:
	if building == null or building.sky_system == null:
		advance(hours * 60.0, fposmod(DayClock.WAKE_HOUR - hours, 24.0))
		return
	var now: float = building.sky_system.time_of_day
	advance(hours * 60.0, fposmod(now - hours, 24.0))
	last_hour = now

## `minutes` of game time from `hour` in the brewery and the cellar, an hour
## at a time; each dawn on the way is a day of fermentation and ageing.
func advance(minutes: float, hour: float) -> void:
	var left := minutes
	var at := hour
	while left > 0.0:
		var step := minf(left, 60.0)
		day.advance(step)
		cellar.advance(day, step, at)
		maltings.advance(step)
		for _dawn in DayClock.dawns_passed(at, step / 60.0):
			cellar.dawn()
			maltings.dawn()
			for keg: String in trade.dawn():
				if layout.utensils.has(keg):
					layout.send_home(keg)
		at = fposmod(at + step / 60.0, 24.0)
		left -= step

## Kg of what a carried thing holds: the brewing day's or the cellar's.
func load_kg(id: String) -> float:
	return day.load_kg(id) + cellar.load_kg(id) + maltings.load_kg(id)

## The batch the book's journal shows: the brewing day's, else the cellar's
## latest once the day has handed its wort over.
func book_batch() -> BrewBatch:
	if day.batch.stage == BrewIds.STAGE_NEW and cellar.latest_batch() != null:
		return cellar.latest_batch()
	return day.batch

## A mug drawn from the keg on the tavern's counter: the beer's profile, {}
## for the old beer when no keg stands there or the world has no brewery.
static func draw_beer(tree: SceneTree) -> Dictionary:
	var house := tree.get_first_node_in_group(GROUP) as BrewHouse
	return house.cellar.rack.pour_mug() if house != null else {}

# ---- Save ---------------------------------------------------------------------------

## The brewery as plain data for its section of the save ("brewing" of the
## region): the day, and where each utensil stands that is not at home ([x,
## y, z, yaw] in the building's frame).
func to_dict() -> Dictionary:
	return {"day": day.to_dict(), "utensils": layout.places(carry.held), "cellar": cellar.to_dict(day.batch),
		"maltings": maltings.to_dict(), "trade": trade.to_dict(), "guide": guide.to_dict()}

## Reads back to_dict(); what is wrong in it is left as it stands.
func restore(data: Dictionary) -> void:
	var saved: Variant = data.get("day")
	if saved is Dictionary:
		day = BrewDay.from_dict(Values.table(saved), day.capacity)
	var cellar_saved: Variant = data.get("cellar")
	if cellar_saved is Dictionary:
		cellar = BrewCellar.from_dict(Values.table(cellar_saved), day.batch)
	var maltings_saved: Variant = data.get("maltings")
	if maltings_saved is Dictionary:
		maltings = BrewMaltings.from_dict(Values.table(maltings_saved))
	var trade_saved: Variant = data.get("trade")
	if trade_saved is Dictionary:
		trade.restore(Values.table(trade_saved))
	var guide_saved: Variant = data.get("guide")
	if guide_saved is Dictionary:
		guide.restore(Values.table(guide_saved))
	layout.restore_places(data.get("utensils"))
	# Kegs stand upright under the taps, the funnel in a bung hole; the keg on
	# the counter waits for the world.
	layout.seat_kegs(cellar)
	work.carrying.seat_tap_later()
	_stage = day.batch.stage
