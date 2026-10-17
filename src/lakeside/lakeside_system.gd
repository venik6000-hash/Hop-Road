class_name LakesideSystem
extends Node3D
## Lake activities share one owner so input, seats, camera and food cannot compete.
## The HUD, the rod, the boat, the fishing and the cooking live in these helpers.
const LAKESIDE_HUD = preload("res://src/lakeside/lakeside_hud.gd")
const LAKESIDE_ROD = preload("res://src/lakeside/lakeside_rod.gd")
const LAKESIDE_BOARDING = preload("res://src/lakeside/lakeside_boarding.gd")
const LAKESIDE_FISHING = preload("res://src/lakeside/lakeside_fishing.gd")
const LAKESIDE_COOKING = preload("res://src/lakeside/lakeside_cooking.gd")
var player: Player
var terrain: TerrainSystem
var water: WaterSystem
var sky: SkySystem
var interactions: TavernInteractions
var camping: CampSystem
var soundscape: LakeSoundscape
var boat: LakeBoat
var aboard := false
var fishing := FishingState.new()
var rod_out := false
var phase := "idle"
var charge := 0.0
var wait_time := 0.0
var tension := 0.0
var progress := 0.0
var fish_kind := ""
var catch_point := Vector3.ZERO
var clock := 0.0
var message := ""
var message_time := 0.0
var cooking: Dictionary = {}
var cooking_fire: Campfire
var cook_time := 0.0
var cooked_visual: Node3D
var panel: PanelContainer
var journal_text: Label
var hud: Label
var gauge: ProgressBar
var rod: Node3D
var rod_tip: Node3D
var line: MeshInstance3D
var bobber: MeshInstance3D
var boarded_eye := 1.6
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	name = "Lakeside"
	boat = LakeBoat.new()
	boat.terrain = terrain
	boat.water = water
	boat.position = find_mooring()
	add_child(boat)
	boat.stroke.connect(func(point: Vector3) -> void:
		if soundscape != null: soundscape.play_event("swim", point, -15.0))
	build_rod()
	build_ui()
	if interactions != null:
		interactions.add_source(_boat_target)
		interactions.add_hold(_hold)

func find_mooring() -> Vector3:
	return LAKESIDE_BOARDING.find_mooring(self)

func build_rod() -> void:
	LAKESIDE_ROD.build(self)

func build_ui() -> void:
	LAKESIDE_HUD.build(self)

func allowed() -> bool:
	return interactions.camera.current and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not interactions.climbing and not camping.placing

func notify(text: String) -> void:
	message = text
	message_time = 6.0

func play(name: String, at: Vector3) -> void:
	if soundscape != null:
		soundscape.play_event(name, at, -13.0)

func _input(event: InputEvent) -> void:
	if panel.visible:
		if InputActions.pressed(event, "fish_journal") or InputActions.pressed(event, "pause"):
			toggle_journal()
		get_viewport().set_input_as_handled()
		return
	if allowed() and InputActions.pressed(event, "place_camp") and (aboard or rod_out):
		notify("Убери удочку и выйди из лодки, чтобы поставить костёр.")
		get_viewport().set_input_as_handled()
		return
	if not allowed() or event.is_echo():
		return
	if InputActions.pressed(event, "fish_journal"):
		toggle_journal()
	elif InputActions.pressed(event, "fishing_rod"):
		toggle_rod()
	elif InputActions.pressed(event, "fish_use"):
		use_catch()
	elif rod_out and InputActions.pressed(event, "fish_cancel"):
		cancel_fishing()
	elif rod_out and InputActions.pressed(event, "fish_cast"):
		if phase == "idle":
			phase = "charging"
			charge = 0.0
		elif phase == "bite":
			phase = "fight"
			tension = 0.30
			progress = 0.0
		else:
			return
	elif rod_out and event.is_action_released("fish_cast"):
		if phase == "charging":
			cast()
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()

## J: the rod out into both hands, or put away.
func toggle_rod() -> void:
	if player.swimming and not aboard:
		notify("Для рыбалки выйди на берег или сядь в лодку.")
	elif rod_out:
		cancel_fishing()
		rod_out = false
		rod.visible = false
		player.hands.release(BodyChannels.ROD)
	elif player.hands.claim(BodyChannels.ROD, func() -> bool: return rod_out):
		cancel_fishing()
		rod_out = true
		rod.visible = true
	else:
		notify(player.hands.busy_text(BodyChannels.ROD))

## The prompt while the player is in the boat, which E alone answers; "" on
## the shore.
func context_text() -> String:
	return "{interact} — сойти на берег / в воду   ·   {move} — грести   ·   {fishing_rod} — удочка" if aboard else ""

## What holds E here (TavernInteractions.add_hold): the boat under way, where
## E only takes the player ashore, or the catch's journal open.
func _hold() -> Interaction:
	return Interaction.of(boat, 0.0, context_text, interact) if aboard or panel.visible else null

## E in the boat or over the open journal: true when it is taken here.
func interact() -> bool:
	if panel.visible:
		return true
	if aboard:
		leave_boat()
		return true
	return false

## Boarding the boat as a target for E (TavernInteractions.add_source). The
## boat is boarded from LAKESIDE_BOARDING.REACH, farther than other things are
## reached, so its distance is told in their reach.
func _boat_target(best: float) -> Interaction:
	if aboard or panel.visible:
		return null
	var distance := LAKESIDE_BOARDING.board_distance(self)
	if distance < 0.0:
		return null
	var told := distance * TavernInteractions.REACH / LAKESIDE_BOARDING.REACH
	if told >= best:
		return null
	return Interaction.of(boat, told, func() -> String: return "{interact} — сесть в лодку", board)

func board() -> void:
	LAKESIDE_BOARDING.board(self)

func leave_boat() -> bool:
	return LAKESIDE_BOARDING.leave_boat(self)

func unboard(at: Vector3) -> void:
	LAKESIDE_BOARDING.unboard(self, at)

func reset() -> void:
	if aboard:
		unboard(player.global_position)
	cancel_fishing()
	rod_out = false
	rod.hide()
	player.hands.release(BodyChannels.ROD)
	if panel.visible:
		toggle_journal()

func cast() -> bool:
	return LAKESIDE_FISHING.cast(self)

func cancel_fishing() -> void:
	phase = "idle"
	if bobber != null:
		bobber.hide()
	if line != null:
		(line.mesh as ImmediateMesh).clear_surfaces()

func _process(delta: float) -> void:
	clock += delta
	message_time = maxf(0, message_time - delta)
	var active := allowed() and not panel.visible
	if aboard:
		boat.rowing = active and not rod_out
		boat.throttle = Input.get_axis("move_back", "move_forward") if boat.rowing else 0.0
		boat.steering = Input.get_axis("move_right", "move_left") if boat.rowing else 0.0
		player.global_position = boat.to_global(Vector3(0, 0.20, 0.65))
	if rod_out and player.swimming and not aboard:
		reset()
	LAKESIDE_FISHING.advance(self, delta, active)
	if rod_out:
		rod.rotation.x = -charge * 0.25 if phase == "charging" else tension * 0.09
	_hold_rod(delta)
	advance_cooking(delta)
	update_hud()

## The player's arms on the rod while it is out (BrewHands.on_rod).
func _hold_rod(delta: float) -> void:
	var taken: Array[Dictionary] = []
	if rod_out and player.hands.has(BodyChannels.ROD):
		var shoulders := player.stand_arms()
		taken = BrewHands.on_rod(rod.global_transform, rod_tip.global_position, shoulders, player.arms.global_basis.x)
	player.hold(BodyChannels.ROD, taken, delta)

func advance_fight(delta: float, reel: bool) -> void:
	LAKESIDE_FISHING.advance_fight(self, delta, reel)

func draw_line() -> void:
	LAKESIDE_ROD.draw_line(self)

func use_catch() -> void:
	LAKESIDE_COOKING.use_catch(self)

func advance_cooking(delta: float) -> void:
	LAKESIDE_COOKING.advance_cooking(self, delta)

func toggle_journal() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		player.movement_locked = true
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		journal_text.text = InputActions.hint(LAKESIDE_HUD.journal(fishing))
	else:
		player.movement_locked = false
		Input.mouse_mode = _previous_mouse_mode

func update_hud() -> void:
	LAKESIDE_HUD.update(self)
