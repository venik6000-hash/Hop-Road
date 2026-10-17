class_name BrewCarrying
extends Node
## What the hand carries at the brewery (BrewHouse, BrewWork): a utensil or a
## log taken in the hand and put down where it lands (BrewCarry), a full keg
## set on the tavern's counter for Borr, a log thrown into a fire, and a keg
## the counter emptied sent back to the rack.

## Where a keg lies on the tavern's counter, from the innkeeper's feet at work
## (VillageNPC.work_point): along the counter's back edge on his right, clear
## of his own keg on his left (NpcBarWork.KEG_AT) and of the bottles.
const BAR_KEG := Vector3(1.0, 1.09, -0.52)
## Why Borr does not take a keg, by BrewKegRack.set_tap's word: a line of LineTable.BREWERY.
const BAR_REFUSALS := {"busy": &"bar_busy", "not_ready": &"bar_not_ready", "ruined": &"bar_ruined"}

var house: BrewHouse
var _player: Player
var _eye: BrewEye
var _interactions: TavernInteractions
## The keg on the counter waits for the world to stand before it is set there.
var _seat_tap := false
## Where the bar's keg lies, world space; found by a ray once the world stands.
var _bar := Transform3D()
var _bar_top := Vector3.ZERO
var _bar_found := false

## The player's hands and eyes.
func attach(interactions: TavernInteractions, eye: BrewEye) -> void:
	_interactions = interactions
	_player = interactions.player
	_eye = eye

## A keg of a save stands on the counter once the world stands.
func seat_tap_later() -> void:
	_seat_tap = house.cellar.rack.tap != ""

## Utensil `id` into the hand; a log only while its woodpile has one.
func take(id: String) -> void:
	if not house.trade.has_log(id):
		house.readout.say(house.lines.text(&"woodpile_empty"))
		return
	var day := house.day
	var cellar := house.cellar
	_player.hands.claim(BodyChannels.BREWERY, house.body.at_work)
	house.carry.held = id
	if id == "hoist_bucket":
		day.hang_bucket(false)
	match BrewCarry.snaps_to(id):
		"keg":
			cellar.rack.stand_keg(id, 0)
			cellar.rack.take_tap(id)
		"funnel":
			cellar.rack.funnel_on = ""
		"bucket":
			if id == "cellar_bucket":
				cellar.bucket_at = ""
	# A carried thing is the level's: out of the brewery the building may be
	# hidden as a whole (InteriorSight), and the thing with it.
	house.layout.node_of(id).reparent(house.level())
	house.body.take_hold(id)

## The held thing put down at `place` (drop_place).
func put(place: Dictionary) -> void:
	var layout := house.layout
	var cellar := house.cellar
	var id := house.carry.held
	var node := layout.node_of(id)
	var at: Vector3 = place.at
	var anchor := str(place.anchor)
	var facing := Basis(Vector3.UP, Values.real(place.get("yaw", 0.0)))
	if anchor.begins_with("lager_") or anchor == "bar_keg":
		facing = facing * layout.keg_upright(id)
	if anchor == "" and layout.home(id).distance_to(at) > 0.001:
		var eye := house.to_local(_eye.camera.global_position) - at
		facing = Basis(Vector3.UP, atan2(eye.x, eye.z))
	if anchor == "bar_keg":
		var refused := cellar.rack.set_tap(id)
		if refused != "":
			var reason: StringName = BAR_REFUSALS[refused]
			house.readout.say(house.lines.text(reason))
			return
		var paid := house.trade.sell_to_borr(Values.table(cellar.rack.kegs[id].beer), house.book)
		house.readout.say(tr(house.lines.text(&"borr_buys")) % [paid, house.trade.coins])
		SaveService.save_soon()
		node.global_transform = _bar
	else:
		node.reparent(house)
		node.transform = Transform3D(facing, at)
	if anchor.begins_with("lager_"):
		cellar.rack.stand_keg(id, int(anchor.get_slice("_", 1)))
	elif anchor.begins_with("funnel_"):
		cellar.rack.funnel_on = anchor.trim_prefix("funnel_")
	elif id == "cellar_bucket":
		cellar.bucket_at = anchor
	if id == "hoist_bucket":
		match str(place.anchor):
			"lift_floor", "hop_back_bucket":
				house.day.hang_bucket(true, false)
			"lift_top":
				house.day.hang_bucket(true, true)
			_:
				if layout.home(id).distance_to(at) < 0.001:
					house.day.hang_bucket(true, false)
	house.carry.held = ""
	_player.pace = 1.0

## Where the held thing would land: a place of its own on the line of sight
## before the face the eye meets (or within reach, with no face), else
## BrewCarry.place at that face.
func drop_place() -> Dictionary:
	var camera := _eye.camera
	var from := camera.global_position
	var hit := _eye.ahead()
	var entry := house.layout.entry_of(house.carry.held)
	var anchors := _all_anchors()
	var toward := house.global_basis.inverse() * -camera.global_basis.z
	if hit.is_empty():
		return BrewCarry.on_ray(entry, house.to_local(from), toward, BrewEye.REACH, anchors)
	# A place of its own on the line of sight before the face it meets: a
	# keg's bung hole has no face of its own.
	var met: Vector3 = hit.position
	var before := BrewCarry.on_ray(entry, house.to_local(from), toward, from.distance_to(met), anchors)
	if not before.is_empty():
		return before
	var normal: Vector3 = hit.normal
	return BrewCarry.place(entry, house.to_local(met), house.global_basis.inverse() * normal, anchors)

## The table's anchors and the cellar's own: a keg's place under each sound
## cask's tap, the bung hole of a keg standing there for the funnel, and the
## keg's place on the tavern's counter.
func _all_anchors() -> Array:
	var layout := house.layout
	var cellar := house.cellar
	var anchors: Array = Values.list(layout.table.get("anchors", [])).duplicate()
	for number in range(1, cellar.sound_casks + 1):
		var place := layout.keg_at_tap(number)
		var middle := layout.keg_aim(number)
		anchors.append({"id": "lager_%d_keg" % number, "kind": "keg", "at": [place.origin.x, place.origin.y, place.origin.z],
			"aim": [middle.x, middle.y, middle.z], "yaw": PI * 0.5})
		var keg := cellar.rack.keg_under[number - 1]
		if keg != "":
			var bung := layout.bung(keg)
			anchors.append({"id": "funnel_" + keg, "kind": "funnel", "at": [bung.x, bung.y, bung.z]})
	if _find_bar():
		var spot := house.global_transform.affine_inverse() * _bar
		var top := house.to_local(_bar_top)
		anchors.append({"id": "bar_keg", "kind": "keg", "at": [spot.origin.x, spot.origin.y, spot.origin.z],
			"aim": [top.x, top.y, top.z], "yaw": spot.basis.get_euler().y})
	return anchors

## The keg's place on the tavern's counter, world space: BAR_KEG from the
## innkeeper's place at work, on the top a ray finds under it, the keg along
## the counter with its bung hole up. False while there is no innkeeper or no
## counter under the place.
func _find_bar() -> bool:
	if _bar_found or _interactions == null or _interactions.population == null:
		return _bar_found
	var keeper := _interactions.population.bartender
	if keeper == null:
		return false
	var turn := Basis(Vector3.UP, keeper.work_yaw)
	var over := keeper.work_point + turn * BAR_KEG
	var hit := _eye.ray(over + Vector3.UP * 0.4, over - Vector3.UP * 0.4)
	if hit.is_empty():
		return false
	var layout := house.layout
	var facing := turn * layout.keg_upright(BrewKegRack.KEGS[0])
	var middle := facing * Vector3(layout.bung_local(BrewKegRack.KEGS[0]).x, 0.0, 0.0)
	_bar_top = hit.position
	_bar = Transform3D(facing, _bar_top + Vector3.UP * BrewLayout.KEG_RADIUS - middle)
	_bar_found = true
	return true

## Whether the hand holds a log to burn.
func holding_log() -> bool:
	return house.carry.held == "log" or house.carry.held == "beech_log"

## The log in the hand thrown into a fire of the valley at world point `at`
## (a campfire): it flies there and goes to the woodpile again.
func throw_log(at: Vector3) -> void:
	if not holding_log():
		return
	var id := house.carry.held
	_let_log_go()
	var node := house.layout.node_of(id)
	var home := house.layout.home(id)
	var flight := create_tween()
	flight.tween_property(node, "global_position", at, 0.3)
	flight.tween_callback(func() -> void: node.transform = Transform3D(Basis.IDENTITY, home))

## The held log thrown into a firebox whose mouth is at `mouth` (the
## building's frame); it goes to the woodpile again: the pile has more.
## False when the hand holds nothing.
func throw_held(mouth: Vector3) -> bool:
	var id := house.carry.held
	if id == "":
		return false
	_let_log_go()
	var node := house.layout.node_of(id)
	var home := house.layout.home(id)
	var flight := create_tween()
	flight.tween_property(node, "position", mouth + Vector3(0.0, 0.0, 0.3), 0.3)
	flight.tween_callback(func() -> void: node.transform = Transform3D(Basis.IDENTITY, home))
	return true

## The log in the hand leaves it for a fire: burnt off the woodpile, the hand free.
func _let_log_go() -> void:
	var id := house.carry.held
	house.layout.node_of(id).reparent(house)
	house.carry.held = ""
	house.body.let_go()
	house.trade.burn_log(id)
	_player.pace = 1.0
	SaveService.save_soon()

## A keg the counter emptied goes back to the rack; a keg away at the market
## is hidden; the keg of a save is set on the counter once it stands.
func settle_kegs() -> void:
	var layout := house.layout
	var cellar := house.cellar
	var back := cellar.rack.take_emptied()
	if back != "" and layout.utensils.has(back):
		layout.send_home(back)
	for id: String in BrewKegRack.KEGS:
		if layout.utensils.has(id):
			layout.node_of(id).visible = not house.market.away(id)
	if _seat_tap and cellar.rack.tap != "" and _find_bar():
		_seat_tap = false
		var node := layout.node_of(cellar.rack.tap)
		node.reparent(house.level())
		node.global_transform = _bar
