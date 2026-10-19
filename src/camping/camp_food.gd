class_name CampFood
extends Node
## The baked potato in the player's left hand (CampSystem): its halves are the
## player's (PlayerState.held), the potato shows in front of the camera, the
## left hand holds it, and the line over it names the keys. While it shows,
## the FOOD context of the input lies over the game's: F eats a half, Q gives
## one to the companion or the villager at rest nearest. The part reads only
## FOOD.

## Seconds a bite takes.
const BITE_SECONDS := 0.65

var camp: CampSystem
## The potato shown in the left hand while the player holds one; null when
## the hand is empty.
var held_potato: Node3D
var _bite_time := 0.0

func _process(delta: float) -> void:
	var player := camp.player
	var shown := camp.in_play()
	var hint_label := camp.hud.food_hint
	hint_label.visible = shown and holding()
	var hint := InputActions.hint(tr("Печёная картошка · {eat_potato} — съесть половину · {camp_secondary} — поделиться · {drink_beer} — пиво")) if holding() else ""
	if hint_label.text != hint:
		hint_label.text = hint
	_bite_time = maxf(0.0, _bite_time - delta)
	if _bite_time <= 0.0:
		player.hands.release(BodyChannels.BITE)
	_show_held()
	if held_potato != null:
		held_potato.visible = shown and holding() and not player.viewmodel.drinking()
		held_potato.position = Vector3(-0.19, -0.20 + sin(_bite_time * PI / BITE_SECONDS) * 0.10, -0.46)
	_hold_potato(delta)

func _input(event: InputEvent) -> void:
	if not camp.in_play() or event.is_echo():
		return
	if InputActions.takes_in(event, &"eat_potato", InputActions.FOOD):
		eat()
		get_viewport().set_input_as_handled()
	elif InputActions.takes_in(event, &"camp_secondary", InputActions.FOOD):
		share()
		get_viewport().set_input_as_handled()

## Whether the player holds a potato with a half left.
func holding() -> bool:
	return camp.player.state.held == PlayerState.POTATO and camp.player.state.held_portions > 0

## The baked potato of `meal` into the left hand: its halves are the
## player's now (PlayerState.hold), the fire's meal is empty.
func take_meal(meal: CampMeal) -> void:
	camp.player.state.hold(PlayerState.POTATO, meal.portions)
	meal.portions = 0
	_show_held()

## The player's left hand under the potato while it shows (BrewHands.on_palm).
func _hold_potato(delta: float) -> void:
	var player := camp.player
	var taken: Array[Dictionary] = []
	if held_potato != null and held_potato.visible and player.hands.has(BodyChannels.POTATO):
		var shoulders := player.stand_arms()
		taken = BrewHands.on_palm(held_potato.global_position, shoulders, player.arms.global_basis.x)
	player.hold(BodyChannels.POTATO, taken, delta)

## The potato shows in the left hand while the player holds one, also one
## a save gave back: the hand is claimed and the food's context of the input
## lies over the game's (InputActions.FOOD). Once it is gone, the hand is
## free.
func _show_held() -> void:
	var player := camp.player
	if holding() == (held_potato != null):
		return
	if held_potato != null:
		held_potato.queue_free()
		held_potato = null
		player.hands.release(BodyChannels.POTATO)
		InputActions.pop(self, InputActions.FOOD)
		return
	if not player.hands.claim(BodyChannels.POTATO, holding):
		return
	held_potato = CampProps.potato(true)
	held_potato.scale = Vector3.ONE * 0.70
	player.camera.add_child(held_potato)
	for mesh: MeshInstance3D in held_potato.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := mesh.material_override as StandardMaterial3D
		material.no_depth_test = true
		material.render_priority = 2
	InputActions.push(InputActions.FOOD, self)

## A half of the potato is eaten. False while a bite is under way, or when
## the hands are busy.
func eat() -> bool:
	if not holding() or _bite_time > 0:
		return false
	var player := camp.player
	var busy := player.hands.busy_text(BodyChannels.BITE)
	if busy != "":
		camp.say(null, busy)
		return false
	if not player.state.use_held():
		return false
	_show_held()
	player.hands.claim(BodyChannels.BITE, func() -> bool: return _bite_time > 0.0)
	_bite_time = BITE_SECONDS
	camp.say(null, camp.lines.text(&"potato_eaten"))
	return true

## Half of the potato goes to the nearest companion, else to the nearest
## villager at rest.
func share() -> bool:
	if not holding() or _bite_time > 0:
		return false
	var companion := camp.company.nearest_companion(3.6)
	var actor: VillageNPC = companion if companion != null else camp.talk.rest.nearest(3.0)
	if actor == null:
		camp.say(null, camp.lines.text(&"come_closer"))
		return false
	if not camp.player.state.use_held():
		return false
	_show_held()
	if companion != null:
		companion.outing.toast()
		companion.outing.receive_food()
	camp.talk.fed(actor, PeopleIds.FOOD_POTATO)
	return true

func _exit_tree() -> void:
	InputActions.pop(self)
