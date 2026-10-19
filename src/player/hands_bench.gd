extends Node3D
## The hands bench (scenes/player/hands_bench.tscn, F6 in the editor): the
## real player and mug on a bare floor, and a stand-in for each doer of
## BodyChannels that claims and lets go as the real one does, with the
## game's own hands and things: the player's arms (Player.arms) on a log and
## at six station works, on the fishing rod (lakeside_rod.gd) and under the
## baked potato (CampProps), put there as BrewHouse, LakesideSystem and
## CampSystem put them. Keys 1-7 play the doers, 8 and 9 break the rules on purpose
## to show the guard (Player.guard_hands) putting them right. The overlay
## shows who has each part, the mug, the refusals and the guard's catches.
## docs/PLAYER.md, «Руки и рот».

const PLAYER := preload("res://scenes/player/player.tscn")
const LAKESIDE_ROD := preload("res://src/lakeside/lakeside_rod.gd")
## The real bite's length (CampFood.eat).
const BITE_SECONDS := 0.65
const NAMES: Dictionary[StringName, String] = {
	BodyChannels.MUG: "кружка",
	BodyChannels.BREWERY: "пивоварня",
	BodyChannels.ROD: "удочка",
	BodyChannels.POTATO: "картошка",
	BodyChannels.DRINK: "глоток",
	BodyChannels.BITE: "укус",
}
## The station works the stand-in plays, with the gesture of BrewGesture each is.
const WORKS: Array[String] = ["мешалка (circle)", "насос (rock)", "ворот (circle)",
	"колотушка (strike)", "лопата (stripe)", "ковш (tilt)"]
const KEYS := "1 — полено в руках   2 — станция   Tab — другая работа   3 — бросить полено\n" + \
	"4 — удочка   5 — картошка   6 / V — глоток   7 — укус\n" + \
	"8 — убрать удочку, не отпустив руки   9 — показать кружку мимо рук   0 — всё сбросить\n" + \
	"WASD — ходить   Esc — мышь   F1 — скрыть подсказку"
## The log across the body, the eye's frame: its middle, its length, its radius.
const LOG_AT := Vector3(0.0, -0.36, -0.30)
## How far from the log's middle each hand takes it.
const LOG_HANDS := 0.26
## The eye looks down at the work, as BrewHouse aims it (degrees).
const EYE_PITCH := -28.0
const LOG_LENGTH := 0.62
const LOG_RADIUS := 0.075
## The potato in the left hand, the camera's frame (as CampFood holds it).
const POTATO_AT := Vector3(-0.19, -0.20, -0.46)

var player: Player
var _camera: Camera3D
var _label: Label
## The station tool's guide lines, world space.
var _tool: MeshInstance3D
var _overlay_layer: CanvasLayer
var _log: Node3D
var _potato_node: Node3D
## Holds the rod LAKESIDE_ROD builds; never in the tree.
var _lake: LakesideSystem
## The stand-ins' state, as their real doers keep it.
var _carry := false
var _station := false
## The station work the arms do: an index of WORKS (Tab steps it).
var station_work := 0
var _letting_go := 0.0
var _rod := false
var _potato := false
var _bite := 0.0
## The bench's clock, seconds: the gestures move with it. A probe sets it
## to draw one phase.
var clock := 0.0
var _said := ""
var _catches := 0
var _caught := ""

## Seconds left of the bite of the potato, 0 when the mouth is free.
func bite_left() -> float:
	return _bite

## Shows or hides the overlay of who has the hands (F1).
func show_overlay(on: bool) -> void:
	_overlay_layer.visible = on

func _ready() -> void:
	_build_world()
	player = PLAYER.instantiate() as Player
	add_child(player)
	player.hands_breached.connect(_breached)
	_camera = player.camera
	_tool = MeshInstance3D.new()
	_tool.mesh = ImmediateMesh.new()
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("6b4a2b")
	_tool.material_override = ink
	_tool.top_level = true
	add_child(_tool)
	_log = Node3D.new()
	_log.name = "Log"
	_log.top_level = true
	CampProps.log_mesh(_log, Vector3.ZERO, LOG_LENGTH, LOG_RADIUS, PI / 2.0)
	_log.visible = false
	add_child(_log)
	_potato_node = CampProps.potato(true)
	_potato_node.scale = Vector3.ONE * 0.70
	_potato_node.visible = false
	_camera.add_child(_potato_node)
	_lake = LakesideSystem.new()
	_lake.player = player
	LAKESIDE_ROD.build(_lake)
	_build_overlay()
	player.rig.pitch_deg = EYE_PITCH
	player.rig.apply_look(Vector2.ZERO)

func _exit_tree() -> void:
	if is_instance_valid(_lake):
		_lake.free()

func _build_world() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(40.0, 40.0)
	plane.mesh = mesh
	floor_body.add_child(plane)
	add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	_overlay_layer = layer
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 17)
	panel.add_child(_label)
	layer.add_child(panel)
	add_child(layer)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			_carry = _brewery_toggle(_carry)
		KEY_2:
			_station = _brewery_toggle(_station)
		KEY_TAB:
			station_work = (station_work + 1) % WORKS.size()
		KEY_3:
			_throw()
		KEY_4:
			_rod_toggle()
		KEY_5:
			_potato_toggle()
		KEY_6:
			_sip()
		KEY_7:
			_eat()
		KEY_8:
			_forget()
		KEY_9:
			_stray_mug()
		KEY_0:
			_reset()
		KEY_F1:
			_overlay_layer.visible = not _overlay_layer.visible
		_:
			return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	clock += delta
	_letting_go = maxf(_letting_go - delta, 0.0)
	_lake.rod.visible = _rod
	_lake.rod.rotation.z = sin(clock * 0.8) * 0.03
	_potato_node.visible = _potato and not player.viewmodel.drinking()
	_potato_node.position = POTATO_AT + Vector3.UP * sin(_bite * PI / BITE_SECONDS) * 0.10
	_place_arms(delta)
	_brewery_done()
	if _bite > 0.0:
		_bite = maxf(_bite - delta, 0.0)
		if _bite <= 0.0:
			player.hands.release(BodyChannels.BITE)
	_label.text = _overlay()

# ---- The brewer's arms ---------------------------------------------------------

## The arms on the log or at the work while the brewery's stand-in has the
## hands, as BrewBody._place_hands puts them (while letting go they keep
## their place with the fingers open); on the rod and under the potato as
## LakesideSystem and CampSystem put them.
func _place_arms(delta: float) -> void:
	var frame := player.eye_frame()
	var arms := player.arms
	_log.visible = _carry
	_log.global_transform = Transform3D(frame.basis, frame * (LOG_AT + Vector3.UP * sin(clock * 3.0) * 0.01))
	var lines: Array[Vector3] = []
	if player.hands.has(BodyChannels.BREWERY):
		var shoulders := player.stand_arms()
		if _letting_go <= 0.0:
			arms.reach(_hands(frame, shoulders))
			if _station and not _carry:
				for point: Vector3 in work_pose(station_work, clock).tool:
					lines.append(frame * point)
		arms.pose(delta)
	_draw_tool(lines)
	var taken: Array[Dictionary] = []
	if _rod and player.hands.has(BodyChannels.ROD):
		taken = BrewHands.on_rod(_lake.rod.global_transform, _lake.rod_tip.global_position, player.stand_arms(), frame.basis.x)
	player.hold(BodyChannels.ROD, taken, delta)
	taken = []
	if _potato_node.visible and player.hands.has(BodyChannels.POTATO):
		taken = BrewHands.on_palm(_potato_node.global_position, player.stand_arms(), frame.basis.x)
	player.hold(BodyChannels.POTATO, taken, delta)

## The brewery's hands: under the log, or at the station's work.
func _hands(frame: Transform3D, shoulders: Array[Vector3]) -> Array[Dictionary]:
	var right := frame.basis.x
	var hands: Array[Dictionary] = []
	if _carry:
		# Under the log near its ends, palms up.
		var middle := _log.global_position
		for side: int in [BrewHands.RIGHT, BrewHands.LEFT]:
			var out := right * (LOG_HANDS if side == BrewHands.RIGHT else -LOG_HANDS)
			hands.append(BrewHands.hand(side, middle + out + Vector3.DOWN * LOG_RADIUS, right, shoulders[side], right, "hold", true))
	elif _station:
		for hold: Dictionary in work_pose(station_work, clock).hands:
			var side: int = hold.side
			var at: Vector3 = hold.at
			var along: Vector3 = hold.along
			hands.append(BrewHands.hand(side, frame * at, frame.basis * along,
				shoulders[side], right, str(hold.clip), Values.flag(hold.get("under", false))))
	return hands

## One pose of station work `work` at time `t`, in the eye's frame (x right,
## y up, -z ahead): {hands: [{side, at, along, clip, under}], tool: the tool's
## lines as pairs of points}. Each wrist stays 0.25-0.52 m from its shoulder
## (the elbow bent), within the eye's view as it looks down at the work
## (EYE_PITCH), and two hands on one tool keep apart (tools/probes/hands_shots.gd
## measures it).
static func work_pose(work: int, t: float) -> Dictionary:
	var right_hand := BrewHands.RIGHT
	var left_hand := BrewHands.LEFT
	match work:
		0:
			# A mash paddle stirred round the tun: the right hand on top of the
			# shaft goes round, the left lower down guides it.
			var turn := t * 2.2
			var top := Vector3(-0.01 + cos(turn) * 0.07, -0.20, -0.30 + sin(turn) * 0.07)
			var foot := Vector3(-0.03 + cos(turn) * 0.03, -0.80, -0.38 + sin(turn) * 0.03)
			var down := (foot - top).normalized()
			return {"hands": [
				{"side": right_hand, "at": top, "along": down, "clip": "grip"},
				{"side": left_hand, "at": top + down * 0.20, "along": down, "clip": "grip"}],
				"tool": [top - down * 0.08, foot]}
		1:
			# A pump handle rocking about its pivot ahead; both hands on the
			# crossbar at its end.
			var swing := sin(t * 2.5) * 0.45
			var pivot := Vector3(0.0, -0.30, -0.72)
			var end := pivot + Vector3(0.0, sin(swing), cos(swing)) * 0.40
			var bar := Vector3.RIGHT
			return {"hands": [
				{"side": right_hand, "at": end + bar * 0.13, "along": bar, "clip": "grip"},
				{"side": left_hand, "at": end - bar * 0.13, "along": bar, "clip": "grip"}],
				"tool": [pivot, end, end - bar * 0.2, end + bar * 0.2]}
		2:
			# A windlass crank turning in the body's plane of sight; both hands
			# side by side on its handle.
			var turn := t * 2.5
			var hub := Vector3(0.10, -0.30, -0.33)
			var grip := hub + Vector3(0.0, sin(turn), cos(turn)) * 0.09
			return {"hands": [
				{"side": right_hand, "at": grip + Vector3.RIGHT * 0.06, "along": Vector3.RIGHT, "clip": "grip"},
				{"side": left_hand, "at": grip - Vector3.RIGHT * 0.14, "along": Vector3.RIGHT, "clip": "grip"}],
				"tool": [hub + Vector3.RIGHT * 0.08, hub, hub, grip, grip + Vector3.RIGHT * 0.1, grip - Vector3.RIGHT * 0.2]}
		3:
			# A mallet on a bung: lifted slowly with the wrist cocked, brought
			# down hard; the left hand steadies the bung.
			var part := fmod(t, 1.2) / 1.2
			var lift := smoothstep(0.0, 0.7, part) * (1.0 - smoothstep(0.72, 0.8, part))
			var grip := Vector3(0.12, -0.38 + lift * 0.24, -0.36 + lift * 0.06)
			var handle := Vector3(-0.35, lift * 0.9 - 0.25, -1.0).normalized()
			var bung := Vector3(-0.06, -0.47, -0.38)
			return {"hands": [
				{"side": right_hand, "at": grip, "along": handle, "clip": "grip"},
				{"side": left_hand, "at": bung, "along": Vector3.RIGHT, "clip": "hold"}],
				"tool": [grip - handle * 0.05, grip + handle * 0.26, grip + handle * 0.26 + Vector3.UP * 0.05, grip + handle * 0.26 + Vector3.DOWN * 0.05]}
		4:
			# A malt shovel across the body: the right hand on the handle by
			# the hip, the left forward down the shaft; pushed out and drawn back.
			var push := sin(t * 2.0) * 0.04
			var back := Vector3(0.14, -0.34, -0.26)
			var front := Vector3(-0.06, -0.38, -0.40)
			var shaft := (front - back).normalized()
			back += shaft * push
			front += shaft * push
			return {"hands": [
				{"side": right_hand, "at": back, "along": shaft, "clip": "grip"},
				{"side": left_hand, "at": front, "along": shaft, "clip": "grip"}],
				"tool": [back - shaft * 0.06, front + shaft * 0.45]}
		_:
			# A dipper tipped to pour: the right hand rolls its handle, the left
			# is cupped under the bowl.
			var tip := (sin(t * 1.5) * 0.5 + 0.5) * 0.7
			# The wrist rises a little as it tips.
			var grip := Vector3(0.14, -0.30 + tip * 0.05, -0.32)
			var bowl := Vector3(-0.10, -0.36, -0.38)
			var handle := (bowl - grip).normalized()
			var roll := Basis(handle, tip) * Vector3.UP
			return {"hands": [
				{"side": right_hand, "at": grip, "along": handle, "clip": "grip"},
				{"side": left_hand, "at": bowl + Vector3.DOWN * 0.05, "along": Vector3.RIGHT, "clip": "hold", "under": true}],
				"tool": [grip - handle * 0.05, bowl, bowl, bowl + roll * 0.06]}

## The tool's lines of the work (a guide on the bench, no model).
func _draw_tool(points: Array[Vector3]) -> void:
	var mesh := _tool.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if points.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()

# ---- Stand-ins -----------------------------------------------------------------

## BrewBody.at_work: a thing held, a station worked, or the fingers still letting go.
func _brewery_busy() -> bool:
	return _carry or _station or _letting_go > 0.0

## Carry or station on or off, as BrewCarrying.take / BrewWork.enter_station do; the
## hands go back once the arms are gone (_brewery_done). Returns the new state.
func _brewery_toggle(on: bool) -> bool:
	if on:
		_set_said("")
		return false
	if not _refused(BodyChannels.BREWERY) and player.hands.claim(BodyChannels.BREWERY, _brewery_busy):
		return true
	return false

## Each frame after the arms are placed, as BrewBody._place_hands.
func _brewery_done() -> void:
	if not _brewery_busy():
		player.hands.release(BodyChannels.BREWERY)

## BrewCarrying.throw_log and throw_held: the log flies, the fingers open for LET_GO.
func _throw() -> void:
	if not _carry:
		_set_said("Нечего бросать: 1 — взять полено.")
		return
	_carry = false
	player.arms.let_go()
	_letting_go = BrewBody.LET_GO
	var flight := Node3D.new()
	flight.top_level = true
	CampProps.log_mesh(flight, Vector3.ZERO, LOG_LENGTH, LOG_RADIUS, PI / 2.0)
	add_child(flight)
	flight.global_transform = _log.global_transform
	var tween := create_tween()
	tween.tween_property(flight, "global_position", flight.global_position - player.eye_frame().basis.z * 3.0 + Vector3.DOWN * 1.2, 0.5)
	tween.tween_callback(flight.queue_free)
	_set_said("Бросок: пальцы разжаты %.1f с." % BrewBody.LET_GO)

func _rod_toggle() -> void:
	if _rod:
		_rod = false
		player.hands.release(BodyChannels.ROD)
	elif not _refused(BodyChannels.ROD):
		_rod = player.hands.claim(BodyChannels.ROD, func() -> bool: return _rod)

func _potato_toggle() -> void:
	if _potato:
		_potato = false
		player.hands.release(BodyChannels.POTATO)
	elif not _refused(BodyChannels.POTATO):
		_potato = player.hands.claim(BodyChannels.POTATO, func() -> bool: return _potato)

## The real sip of the real mug.
func _sip() -> void:
	if player.viewmodel.drink():
		_set_said("")
	elif not _refused(BodyChannels.DRINK):
		_set_said("Глоток не начат: кружки нет в руке или она пуста.")

func _eat() -> void:
	if not _potato:
		_set_said("Нечего кусать: 5 — взять картошку.")
	elif _bite <= 0.0 and not _refused(BodyChannels.BITE):
		player.hands.claim(BodyChannels.BITE, func() -> bool: return _bite > 0.0)
		_bite = BITE_SECONDS

## A doer that is done but does not let go: the guard must catch it.
func _forget() -> void:
	if not _rod:
		_set_said("Сначала достань удочку: 4.")
		return
	_rod = false
	_set_said("Удочка убрана без отпуска рук: ждём сторожа.")

## The mug set past the hands: the guard must put it back. The bench breaks
## the rule here on purpose (tests/test_body_channels.gd lets it).
func _stray_mug() -> void:
	player.viewmodel.visible = not player.viewmodel.visible
	_set_said("Кружка переключена мимо рук: ждём сторожа.")

func _reset() -> void:
	_carry = false
	_station = false
	_letting_go = 0.0
	_rod = false
	_potato = false
	_bite = 0.0
	player.viewmodel.refill()
	player.arms.drop()
	for doer: StringName in BodyChannels.DOERS:
		if doer != BodyChannels.MUG:
			player.hands.release(doer)
	_set_said("Всё сброшено, кружка полная.")

## Says what stops `doer`; true when something does.
func _refused(doer: StringName) -> bool:
	var busy := player.hands.busy_text(doer)
	_set_said("Отказ (%s): %s" % [NAMES[doer], busy] if busy != "" else "")
	return busy != ""

func _set_said(text: String) -> void:
	_said = text

func _breached(what: String) -> void:
	_catches += 1
	_caught = what

# ---- Overlay -------------------------------------------------------------------

func _overlay() -> String:
	var hands := player.hands
	var lines: Array[String] = ["СТЕНД РУК — моки всех жестов", ""]
	var right := hands.holder(BodyChannels.RIGHT_HAND)
	lines.append("Правая рука: %s" % _who(right, "свободна"))
	lines.append("Левая рука: %s" % _who(hands.holder(BodyChannels.LEFT_HAND), "свободна"))
	lines.append("Рот: %s" % _who(hands.holder(BodyChannels.MOUTH), "свободен"))
	lines.append("Кружка на экране: %s   Пиво: %d %%" % ["да" if player.viewmodel.visible else "нет", roundi(player.viewmodel.fill() * 100.0)])
	lines.append("Работа на станции: %s" % WORKS[station_work])
	lines.append("")
	lines.append("Моки: полено %s · станция %s · разжатие %s · удочка %s · картошка %s · укус %s" % [
		_mark(_carry), _mark(_station), _mark(_letting_go > 0.0), _mark(_rod), _mark(_potato), _mark(_bite > 0.0)])
	lines.append("Сообщение: %s" % (_said if _said != "" else "—"))
	lines.append("Сторож: поймал %d · %s" % [_catches, _caught if _caught != "" else "—"])
	lines.append("")
	lines.append(KEYS)
	return "\n".join(lines)

func _who(doer: StringName, free: String) -> String:
	return free if doer == &"" else NAMES[doer]

func _mark(on: bool) -> String:
	return "■" if on else "□"
