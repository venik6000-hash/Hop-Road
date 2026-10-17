class_name BrewWork
extends Node
## What E and the mouse do at the brewery (BrewHouse): the thing the eye is
## on for E (find_target; the trade's places are BrewMarket's), a utensil or
## a log from a woodpile taken in the hand (carried and put down by
## BrewCarrying), a station worked by the mouse's gestures (BrewStation), the
## hourglass turned, and the brewer's book opened on the desk
## (BrewBookPanel). While a station is worked or the book is open, the
## brewery holds E (TavernInteractions.add_hold).

## How near its stand the player must be to work a station, m; how near the
## building's origin to have anything of it in reach.
const STAND := 1.2
const NEAR := 20.0
## How much a thing off the middle of the view counts as farther.
const OFF_AIM := 60.0
## Prompts for the gestures of a station's work.
const GESTURE_HINTS := {"tilt": "{look} от себя — наклонить", "circle": "{look} по кругу", "rock": "{look} вниз-вверх — качать",
	"draw": "{look} — тянуть", "stripe": "{look} полосами", "strike": "замах и удар", "throw": "замах вниз, бросок вверх"}

## A thing of the brewery E can be pointed at: a station, the book, a
## utensil to take, a woodpile, the hourglass, a place to put the held thing
## down, a place of the trade (BrewMarket).
class Target:
	var kind := ""
	var id := ""
	## Where a thing put down lands (BrewCarry.place).
	var place := {}

var house: BrewHouse:
	set(value):
		house = value
		carrying.house = value
## The station the hand works, null when the player walks.
var station: BrewStation
var station_id := ""
## The mouse's motion since the last frame, for the station's gesture; a
## tool moves the hand by adding to it.
var motion := Vector2.ZERO
var woodpiles := BrewWoodpiles.new()
var book_panel: BrewBookPanel
## What the hand carries and puts down.
var carrying := BrewCarrying.new()
var _player: Player
var _eye: BrewEye
var _interactions: TavernInteractions

func _init() -> void:
	carrying.name = "Carrying"
	add_child(carrying)

## The player's hands and eyes: the brewery is a source of E's targets and
## holds E while it is busy.
func attach(interactions: TavernInteractions, eye: BrewEye) -> void:
	_interactions = interactions
	_player = interactions.player
	_eye = eye
	interactions.add_source(_interaction)
	interactions.add_hold(_held)
	interactions.released.connect(_released)
	carrying.attach(interactions, eye)
	book_panel = BrewBookPanel.new()
	add_child(book_panel)
	woodpiles.gather(house, house.level())

func _input(event: InputEvent) -> void:
	if book_panel != null and book_panel.visible:
		# The book takes the walk to turn its pages.
		if event.is_echo():
			return
		if InputActions.pressed(event, "move_left"):
			book_panel.turn(-1)
		elif InputActions.pressed(event, "move_right"):
			book_panel.turn(1)
		elif InputActions.pressed(event, "pause"):
			interact_busy()
		elif not event is InputEventMouseMotion:
			return
		get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var turn := _choice(event)
	if station == null:
		if house.market.turn(turn, _interactions):
			get_viewport().set_input_as_handled()
		return
	var motion_event := event as InputEventMouseMotion
	if motion_event != null:
		motion += motion_event.relative
		get_viewport().set_input_as_handled()
	elif turn != 0:
		station.next(house.day, turn)
		house.body.approach()
		get_viewport().set_input_as_handled()

## +1 for "choice_next", -1 for "choice_previous" (the mouse wheel), else 0.
static func _choice(event: InputEvent) -> int:
	if event.is_echo():
		return 0
	if InputActions.pressed(event, "choice_next"):
		return 1
	if InputActions.pressed(event, "choice_previous"):
		return -1
	return 0

## The station's work of this frame, `minutes` of game time long, and what
## the cellar did since the last frame.
func update(delta: float, minutes: float) -> void:
	# At a station the right stick works as the mouse does.
	if _player != null:
		_player.look_held = station != null
	if station != null:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			motion += _player.stick_gesture(delta)
		var work := station.work()
		var before := [station.gesture.count, station.gesture.amount, station.gesture.turns]
		var thrown := station.update(house.day, motion, delta, minutes)
		_sound_work(work, before, delta)
		if thrown:
			_throw_held()
		motion = Vector2.ZERO
	_pour_taste()
	carrying.settle_kegs()

# ---- What E does here (TavernInteractions) ----------------------------------

## Whether the hand is busy here: a station worked or the book open.
func busy() -> bool:
	return station != null or (book_panel != null and book_panel.visible)

func busy_text() -> String:
	if book_panel != null and book_panel.visible:
		return "{move_left} / {move_right} — листать   ·   {interact} — закрыть книгу"
	var work := station.work()
	var title := tr(str(work.title))
	var text := "%s   ·   %s" % [title.left(1).to_upper() + title.substr(1), tr(str(GESTURE_HINTS.get(work.gesture, "")))]
	if station.works.size() > 1:
		text += tr("   ·   {choice} — другое дело")
	return text + tr("   ·   {interact} — отойти")

## E while busy: steps away from the station, shuts the book.
func interact_busy() -> void:
	if book_panel != null and book_panel.visible:
		book_panel.visible = false
		_player.movement_locked = false
	elif station != null:
		leave_station()

## The brewery's hold on E (TavernInteractions.add_hold): while busy.
func _held() -> Interaction:
	return Interaction.of(self, 0.0, busy_text, interact_busy) if busy() else null

## The player was taken out of whatever held them (TavernInteractions.reset).
func _released() -> void:
	if busy():
		interact_busy()

## find_target as a source of targets for E (TavernInteractions.add_source).
func _interaction(best: float) -> Interaction:
	var found := find_target(best)
	if found.is_empty():
		return null
	var target: Target = found.target
	return Interaction.of(target, Values.real(found.distance), target_text.bind(target), interact.bind(target))

## {distance, target} for a new target of `kind` and `id`.
static func target_of(kind: String, id: String, distance: float) -> Dictionary:
	var target := Target.new()
	target.kind = kind
	target.id = id
	return {"distance": distance, "target": target}

## What E would do nearest within `best` metres: {distance, target}; {} when
## nothing. Putting down what the hand holds comes last of all.
func find_target(best: float) -> Dictionary:
	if _interactions == null:
		return {}
	var held := house.carry.held
	var trading := house.market.target(best, _interactions)
	var wood := {}
	if held == "":
		var pile := woodpiles.looked_at(_eye, best)
		if not pile.is_empty():
			wood = target_of("firewood", str(pile.index), Values.real(pile.distance))
	if not wood.is_empty() and (trading.is_empty() or Values.real(wood.distance) < Values.real(trading.distance)):
		return wood
	if not trading.is_empty() or not near():
		return trading
	var layout := house.layout
	# Of what is in sight nearer than `best`, the thing the eye is most on:
	# in the cellar a tap, the funnel and a keg stand within a hand.
	var found := {}
	var score := INF
	var candidates: Array[Array] = []
	for id: String in layout.stations:
		var reads := id == "desk" and held == ""
		var works := BrewStation.works_for(id, held, house.cellar)
		if works.is_empty() and not reads:
			continue
		# The look of a station may lie in a vessel, behind its rim: it is
		# looked at from where one stands to work it, through nothing.
		var stand := house.to_global(layout.stand(id))
		if Vector2(stand.x - _player.global_position.x, stand.z - _player.global_position.z).length() > STAND:
			continue
		# A station is aimed at by its look or by a part its works move: the
		# pump's handle, a cock's key.
		var look := house.to_global(layout.look(id))
		var aim := _eye.aimed(look)
		for point in layout.part_points(works):
			var distance := _eye.aimed(point)
			if distance < aim:
				aim = distance
				look = point
		candidates.append(["book" if reads else "station", id, look, aim])
	if held == "":
		for id: String in layout.utensils:
			if house.market.away(id) or id == house.cellar.rack.tap:
				continue
			candidates.append(["take", id, layout.grip(id), _interactions.target_distance(layout.grip(id), null, true)])
		var glass := layout.moving_point("hourglass")
		candidates.append(["hourglass", "hourglass", glass, _interactions.target_distance(glass, null, true)])
	for candidate: Array in candidates:
		var distance: float = candidate[3]
		if distance >= best:
			continue
		var point: Vector3 = candidate[2]
		var off := _eye.off_aim(point)
		if distance * (1.0 + OFF_AIM * off) < score:
			score = distance * (1.0 + OFF_AIM * off)
			found = target_of(str(candidate[0]), str(candidate[1]), distance)
	if held != "" and found.is_empty():
		var place := carrying.drop_place()
		if not place.is_empty():
			found = target_of("put", held, best - 0.001)
			var put_down: Target = found.target
			put_down.place = place
	return found

## Whether the player is about the brewery at all, carrying something or not.
func near() -> bool:
	return house.carry.held != "" or _player.global_position.distance_to(house.global_position) < NEAR

func target_text(target: Target) -> String:
	var layout := house.layout
	match target.kind:
		"station":
			var works := BrewStation.works_for(target.id, house.carry.held, house.cellar)
			return "{interact} — %s · %s" % [tr(str(works[0].title)), tr(str(layout.stations[target.id].title))]
		"book":
			return "{interact} — открыть книгу пивовара"
		"take":
			return tr("{interact} — взять · %s") % tr(str(layout.entry_of(target.id).title))
		"firewood":
			var stack: Dictionary = woodpiles.stacks[int(target.id)]
			return tr("{interact} — взять полено · %s") % tr(str(stack.title))
		"hourglass":
			return "{interact} — перевернуть песочные часы"
		"put":
			var put_down := tr("{interact} — поставить на стойку · %s") if target.place.get("anchor", "") == "bar_keg" \
				else tr("{interact} — поставить · %s")
			return put_down % tr(str(layout.entry_of(house.carry.held).title))
	return house.market.text(target)

func interact(target: Target) -> void:
	match target.kind:
		"station":
			if _hands_free():
				enter_station(target.id)
		"book":
			book_panel.open(func() -> PackedStringArray: return house.book.pages(house.book_batch()))
			_player.movement_locked = true
		"take":
			if _hands_free():
				carrying.take(target.id)
		"firewood":
			if not _hands_free():
				return
			var stack: Dictionary = woodpiles.stacks[int(target.id)]
			if stack.valley:
				house.trade.gather_log(str(stack.log))
			carrying.take(str(stack.log))
		"hourglass":
			house.day.turn_hourglass()
		"put":
			carrying.put(target.place)
		_:
			house.market.act(target)

## Whether the hands are free for the brewery's work; says what holds them when not.
func _hands_free() -> bool:
	var holder := _player.hands.busy_text(BodyChannels.BREWERY)
	if holder != "":
		house.readout.say(holder)
	return holder == ""

# ---- Stations -------------------------------------------------------------------

## Station `id` worked with what the hand holds, when it has a work for it.
func enter_station(id: String) -> void:
	var mode := BrewStation.open(id, house.carry.held, house.day, house.cellar, house.maltings)
	if mode == null:
		return
	_player.hands.claim(BodyChannels.BREWERY, house.body.at_work)
	station = mode
	station_id = id
	motion = Vector2.ZERO
	_player.movement_locked = true
	_player.velocity = Vector3.ZERO
	house.body.approach()

## Steps away from the station: the body back on its stand.
func leave_station() -> void:
	house.body.leave(station_id)
	station = null
	station_id = ""

## The sounds the hand's work made this frame (BrewSounds): a stroke, a blow,
## a pass, a throw; a tap leaving its end, the hatch or a damper at one; the
## loop of a turning work or of a tipped thing that pours where no stream
## shows (a bucket filled). `before`: the gesture's count, amount and turns
## before the frame.
func _sound_work(work: Dictionary, before: Array, delta: float) -> void:
	var sounds := house.look.sounds
	var anchors := house.layout.anchors
	var gesture := station.gesture
	var at := _work_point(work)
	var shot := BrewSounds.shot_of(str(work.id))
	if shot != "" and gesture.count > Values.whole(before[0]):
		var loud := maxf(gesture.force, 0.4) if gesture.kind == "strike" or gesture.kind == "throw" else 1.0
		if shot == "log":
			at = house.to_global(anchors["kiln_stoke"] if station_id == "kiln" else anchors["copper_stoke"])
		sounds.play(shot, at, loud)
	if work.gesture == "draw" and work.has("part"):
		var sound := BrewSounds.draw_sound(str(work.id), Values.real(before[1]), gesture.amount)
		if sound != "":
			sounds.play(sound, at)
	var loop := BrewSounds.loop_of(work)
	if loop == "":
		return
	var amount := absf(gesture.turns - Values.real(before[2])) / maxf(delta, 0.001) / BrewSounds.FULL_TURNS
	if work.gesture == "tilt":
		if house.layout.pour_landing(str(work.id), station).is_finite():
			return
		amount = gesture.flow()
	sounds.hum("work", loop, at, amount)

## Where a work is heard: the part it turns, the thing in the hand, else what
## the station looks at. World space.
func _work_point(work: Dictionary) -> Vector3:
	var layout := house.layout
	if work.has("part") and layout.moving.has(work.part):
		return layout.moving_point(str(work.part))
	if house.carry.held != "":
		return layout.node_of(house.carry.held).global_position
	return house.to_global(layout.look(station_id))

## A log thrown into the fire the station stokes: it flies into the firebox,
## and the hand steps away from the station.
func _throw_held() -> void:
	var anchors := house.layout.anchors
	var mouth: Vector3 = anchors["kiln_stoke"] if station_id == "kiln" else anchors["copper_stoke"]
	if carrying.throw_held(mouth):
		leave_station()

# ---- What the cellar did --------------------------------------------------------

## The taste a cask gave goes into the mug.
func _pour_taste() -> void:
	var taste := house.cellar.take_taste()
	if not taste.is_empty() and _player != null:
		if _player.viewmodel != null:
			_player.viewmodel.refill(taste)
		house.readout.say(BrewReadout.taste_words(taste, house.book))
