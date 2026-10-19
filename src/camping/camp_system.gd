class_name CampSystem
extends Node3D
## Camps and outings belong to the alpine level, not to the tavern interior
## (docs/PLAYER.md, «Костёр и прогулки»). The node holds what its parts
## share — the player, the interactions, the people, the valley, the camp's
## lines, the site check (camp_site.gd) — and the parts, as its children:
## - CampHud: the caption and the food hint;
## - CampPlacing: laying a fire where the player looks;
## - CampFires: the fires, E, Q and X at them, their save (`sites`);
## - CampFood: the potato in the hand;
## - CampCompany: the companions and the invitations;
## - CampTalk: the warmth, the stories and the memories (`memories`), with the
##   villagers at rest (CampRest) and the signs of closeness (CampSigns).
## Each part reads only its own actions of its own context of the input
## (InputActions.takes_in). The node is the camp's face to the rest of the
## game: the interactions, the controls and the save go through it.
const CAMP_SITE = preload("res://src/camping/camp_site.gd")

var player: Player
var interactions: TavernInteractions
var population: NpcPopulation
## The game's day, hour, weather and zone (the world loader's ValleyLoop);
## without it the moment is ValleyLoop.STILL.
var valley: ValleyLoop
var water_level := 0.72
## What the camp says under no one's name, by id.
var lines := LineTable.read(LineTable.CAMP, PeopleSchemas.camp_lines())
var hud: CampHud
var placer: CampPlacing
var campfires: CampFires
var food: CampFood
var company: CampCompany
var talk: CampTalk
## Whether the player is choosing the place of a fire (CampPlacing).
var placing: bool:
	get:
		return placer != null and placer.active
	set(value):
		if placer == null or value == placer.active:
			return
		if value:
			placer.start()
		else:
			placer.cancel()
## Query resources are reused, but collision results are never cached.
var site_ground_query := PhysicsRayQueryParameters3D.new()
var site_roof_query := PhysicsRayQueryParameters3D.new()
var site_clearance_query := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	hud = CampHud.new()
	placer = CampPlacing.new()
	placer.name = "Placing"
	campfires = CampFires.new()
	campfires.name = "Fires"
	food = CampFood.new()
	food.name = "Food"
	company = CampCompany.new()
	company.name = "Company"
	talk = CampTalk.new()
	talk.name = "Talk"
	hud.camp = self
	placer.camp = self
	campfires.camp = self
	food.camp = self
	company.camp = self
	talk.camp = self
	# The parts take their frames in this order: the caption first, the talk last.
	for part: Node in [hud, placer, campfires, food, company, talk]:
		add_child(part)
	if interactions != null:
		interactions.add_source(_interaction)
		interactions.add_hold(_hold)
	GameEvents.sleep_started.connect(fast_travel)

## Whether the camp's parts show and take the input: the player's camera is
## the view and no window of the input holds the pointer.
func in_play() -> bool:
	return player.camera.current and InputActions.in_play()

func ground_at(point: Vector3, above := 2.0, below := 5.0) -> Dictionary:
	return CAMP_SITE.ground_at(self, point, above, below)

func check_site(point: Vector3, restoring := false) -> Dictionary:
	return CAMP_SITE.check_site(self, point, restoring)

## A source of targets for E (TavernInteractions.add_source): the nearest of a
## villager to talk to or take for a walk (CampCompany), a fire and a seat at
## a fire (CampFires).
func _interaction(best: float) -> Interaction:
	var found := find_target(best)
	if found.is_empty():
		return null
	var distance: float = found.distance
	var target: Variant = found.target
	if target is VillageNPC:
		var actor: VillageNPC = target
		return interactions.npc_interaction(actor, distance)
	if target is Campfire:
		var fire: Campfire = target
		return Interaction.of(fire, distance, func() -> String: return fire.interaction_text(food.holding(), campfires.holding_log()),
			campfires.interact_fire.bind(fire))
	var seat: Dictionary = target
	return interactions.seat_interaction(seat, distance)

## What E would do nearest within `best` metres among the villagers, the fires
## and their seats: {distance, target}; {} when nothing.
func find_target(best: float) -> Dictionary:
	var found := company.find_target(best)
	var fire_target := campfires.find_target(Values.real(found.distance) if not found.is_empty() else best)
	return fire_target if not fire_target.is_empty() else found

## What holds E here (TavernInteractions.add_hold): a fire being laid, or a
## seat at a campfire sat on, with the mug's and the food's keys.
func _hold() -> Interaction:
	if placer.active:
		return placer.hold()
	if interactions.seated.get("camp", false):
		return Interaction.of(interactions.seated, 0.0, func() -> String: return tr(TavernInteractions.STAND_HINT) + hud.seated_text(),
			interactions.stand)
	return null

## The prompt at a villager (TavernInteractions.npc_interaction).
func interaction_text(actor: VillageNPC) -> String:
	return company.interaction_text(actor)

## E on a villager (TavernInteractions.npc_interaction).
func interact_npc(actor: VillageNPC) -> void:
	company.interact_npc(actor)

## Whether somebody sits on the seat by a fire (TavernInteractions.sit).
func seat_occupied(seat: Dictionary) -> bool:
	return campfires.seat_occupied(seat)

## Shows `words` under the speaker's name (CampHud.say).
func say(actor: VillageNPC, words: String) -> void:
	hud.say(actor, words)

func current_day() -> int:
	return valley.day if valley != null else 1

## The fires or what the player has with the villagers have changed: the
## valley saves them soon.
func mark_changed() -> void:
	SaveService.save_soon()

## The player is carried away (sleep, the boat): no fire is being laid, and
## the companions go home.
func fast_travel() -> void:
	placer.cancel()
	company.dismiss_all()

## The fires and the villagers' memories of them as the save holds them
## (SaveService, section "camping" of the region): {memories, sites: [[x, y,
## z, fuel seconds], ...]}.
func to_dict() -> Dictionary:
	return {"memories": talk.memories.duplicate(true), "sites": campfires.sites()}

## Takes the memories and the fires back from to_dict(), checked. The fires
## are laid once the ground under them stands (CampFires.restore).
func restore(saved_state: Variant) -> void:
	if not saved_state is Dictionary:
		return
	var saved: Dictionary = saved_state
	var saved_memories: Variant = saved.get("memories")
	if saved_memories is Dictionary:
		talk.memories = saved_memories
	await campfires.restore(saved.get("sites"))
