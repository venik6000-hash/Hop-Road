class_name BrewHouse
extends Node3D
## The brewing in the brewery's rooms (docs/plans/brewing.md, stages 2 and 3):
## the brewery's table (brewery.json) made to work. It owns the rules of the
## day, the cellar, the maltings and the trade (BrewDay, BrewCellar,
## BrewMaltings, BrewTrade, BrewGuide, BrewCarry), runs them by the game's
## lived time (GameClock.advanced), keeps them in the save, and wires the parts that each do one thing:
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

## Set before it enters the tree: the building's table.
var table: Dictionary:
	set(value):
		table = value
		layout = BrewLayout.new(self, value)
## What the brewery takes from the building it stands in (VillageBuilding),
## all null in a house without its building: the building's node, whose
## parent is the level; what moves in it (the taps, the cocks, the windlass);
## and its fires (the copper's, the kiln's), set once the building has lamps.
var site: Node3D
var machinery: BuildingMachinery
var fires: BuildingFires
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
## Game minutes lived since the last frame: the stations' work takes them.
var _lived := 0.0
## The batch's stage at the last look (BrewBatch.stage).
## How the brewery asks the save to keep it soon: a change the player would
## not want to lose (an order, a purchase, a new stage). The game's service;
## a test gives its own.
var ask_save: Callable = SaveService.save_soon
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

func _enter_tree() -> void:
	if not GameClock.advanced.is_connected(live):
		GameClock.advanced.connect(live)

func _exit_tree() -> void:
	if GameClock.advanced.is_connected(live):
		GameClock.advanced.disconnect(live)

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

## The level the brewery stands in: carried things and the counter's keg are its.
func level() -> Node:
	return site.get_parent() if site != null and site.get_parent() != null else self

func _process(delta: float) -> void:
	var minutes := _lived
	_lived = 0.0
	if note_stage():
		ask_save.call()
	work.update(delta, minutes)
	look.settle()
	body.update(delta)
	look.run(delta)
	market.lead()
	readout.update(delta)

## True once when the batch comes to another stage: the save keeps it soon.
func note_stage() -> bool:
	if day.batch.stage == _stage:
		return false
	_stage = day.batch.stage
	return true

## `minutes` of game time lived from game minute `from` (GameClock.advanced:
## the running clock, a night slept) go into the day and the cellar. Time set
## (a load, a debug key back) is not lived and gives none.
func live(minutes: float, from: float) -> void:
	advance(minutes, DayClock.hour_of(from))
	_lived += minutes

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
