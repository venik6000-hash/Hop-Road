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
## The region's lake (RegionDef.lake): where the boat moors.
var plan: LakePlan
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

## The rod hangs on the player's camera, which stays when the region's
## content goes (docs/LEVEL.md, «Общие системы и содержимое»): it goes with
## the lake, and the hands are given back.
func _exit_tree() -> void:
	if rod_out:
		player.hands.release(BodyChannels.ROD)
		rod_out = false
	if is_instance_valid(rod):
		rod.queue_free()

func find_mooring() -> Vector3:
	return LAKESIDE_BOARDING.find_mooring(self)

## Where the lake's waves are asked for (WorldContext.water_probes): the boat,
## then the bobber's catch point (x, z). They follow the player's point, so
## the boat reads surface_height(1) and the bobber surface_height(2).
func probe_points() -> PackedVector2Array:
	return PackedVector2Array([Vector2(boat.position.x, boat.position.z), Vector2(catch_point.x, catch_point.z)])

func build_rod() -> void:
	LAKESIDE_ROD.build(self)

func build_ui() -> void:
	LAKESIDE_HUD.build(self)

## The player's modes where the lake's keys work: on foot, in a seat, in
## the boat. Not on the ladder, at a brewery's station or book, asleep.
const LAKE_MODES: Array[StringName] = [Player.WALK, Player.SEATED, Player.BOAT]

## Whether the lake's keys work: the player's own eye, the game in play
## (InputActions.in_play), a mode of LAKE_MODES and no fire being laid.
func allowed() -> bool:
	return interactions.camera.current and InputActions.in_play() and LAKE_MODES.has(player.mode) \
		and not camping.placing

func notify(text: String) -> void:
	message = text
	message_time = 6.0

func play(name: String, at: Vector3) -> void:
	if soundscape != null:
		soundscape.play_event(name, at, -13.0)

func _input(event: InputEvent) -> void:
	if panel.visible:
		if InputActions.takes(event, &"fish_journal") or InputActions.takes(event, &"pause"):
			toggle_journal()
		get_viewport().set_input_as_handled()
		return
	if allowed() and InputActions.takes(event, &"place_camp") and (aboard or rod_out):
		notify("Убери удочку и выйди из лодки, чтобы поставить костёр.")
		get_viewport().set_input_as_handled()
		return
	if not allowed() or event.is_echo():
		return
	if InputActions.takes(event, &"fish_journal"):
		toggle_journal()
	elif InputActions.takes(event, &"fishing_rod"):
		toggle_rod()
	elif InputActions.takes(event, &"fish_use"):
		use_catch()
	elif rod_out and InputActions.takes(event, &"fish_cancel"):
		cancel_fishing()
	elif rod_out and InputActions.takes(event, &"fish_cast"):
		if phase == "idle":
			phase = "charging"
			charge = 0.0
		elif phase == "bite":
			phase = "fight"
			tension = 0.30
			progress = 0.0
		else:
			return
	elif rod_out and InputActions.releases(event, &"fish_cast"):
		if phase == "charging":
			cast()
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()

## J: the rod out into both hands, or put away. While it is out, the rod's
## context of the input lies over the game's (InputActions.ROD): the left
## trigger reels in instead of diving.
func toggle_rod() -> void:
	if player.swimming and not aboard:
		notify("Для рыбалки выйди на берег или сядь в лодку.")
	elif rod_out:
		_put_rod_away()
	elif player.hands.claim(BodyChannels.ROD, func() -> bool: return rod_out):
		cancel_fishing()
		rod_out = true
		rod.visible = true
		InputActions.push(InputActions.ROD, rod)
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
	_put_rod_away()
	if panel.visible:
		toggle_journal()

## The rod out of the hands and its context of the input off.
func _put_rod_away() -> void:
	cancel_fishing()
	rod_out = false
	rod.hide()
	player.hands.release(BodyChannels.ROD)
	InputActions.pop(rod)

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

## The catch's journal opened or shut. Open, it has its context of the input
## on top (InputActions.JOURNAL) and frees the pointer; on foot it also owns
## the player's mode (Player.MENU). In a seat or the boat that mode holds
## the feet already.
func toggle_journal() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		player.enter(Player.MENU, panel)
		InputActions.push(InputActions.JOURNAL, panel)
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		journal_text.text = InputActions.hint(LAKESIDE_HUD.journal(fishing))
	else:
		player.leave(panel)
		InputActions.pop(panel)
		Input.mouse_mode = _previous_mouse_mode

func update_hud() -> void:
	LAKESIDE_HUD.update(self)
