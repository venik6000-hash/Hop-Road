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
var soundscape: Node
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
var _old_eye := 1.6
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	name = "Lakeside"
	fishing.restore()
	boat = LakeBoat.new()
	boat.terrain = terrain
	boat.water = water
	boat.position = find_mooring()
	add_child(boat)
	boat.stroke.connect(func(point: Vector3):
		if soundscape != null: soundscape.play_event("swim", point, -15.0))
	build_rod()
	build_ui()

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
		if event.is_action_pressed("fish_journal") or event.is_action_pressed("release_mouse"):
			toggle_journal()
		get_viewport().set_input_as_handled()
		return
	if allowed() and event.is_action_pressed("place_camp") and (aboard or rod_out):
		notify("Убери удочку и выйди из лодки, чтобы поставить костёр.")
		get_viewport().set_input_as_handled()
		return
	if not allowed() or event.is_echo():
		return
	if event.is_action_pressed("fish_journal"):
		toggle_journal()
	elif event.is_action_pressed("fishing_rod"):
		if player.swimming and not aboard:
			notify("Для рыбалки выйди на берег или сядь в лодку.")
		elif not camping.holding_food():
			cancel_fishing()
			rod_out = not rod_out
			rod.visible = rod_out
			player.viewmodel.visible = not rod_out
	elif event.is_action_pressed("fish_use"):
		use_catch()
	elif rod_out and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_fishing()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and phase == "idle":
				phase = "charging"
				charge = 0.0
			elif not event.pressed and phase == "charging":
				cast()
			elif event.pressed and phase == "bite":
				phase = "fight"
				tension = 0.30
				progress = 0.0
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()

func context_text() -> String:
	if aboard:
		return "E — сойти на берег / в воду   ·   WASD — грести   ·   J — удочка"
	if can_board():
		return "E — сесть в лодку"
	return ""

func can_board() -> bool:
	return LAKESIDE_BOARDING.can_board(self)

func interact() -> bool:
	if panel.visible:
		return true
	if aboard:
		leave_boat()
		return true
	if can_board():
		board()
		return true
	return false

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
	player.viewmodel.show()
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
	advance_cooking(delta)
	update_hud()

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
		journal_text.text = LAKESIDE_HUD.journal(fishing)
	else:
		player.movement_locked = false
		Input.mouse_mode = _previous_mouse_mode

func update_hud() -> void:
	LAKESIDE_HUD.update(self)
