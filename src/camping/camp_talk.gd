class_name CampTalk
extends Node
## What grows between the player and the villagers (CampSystem): the warmth of
## the time spent together, the treats, the toasts, the stories each
## storyteller tells when it is their turn, the place a companion loves, and
## what each villager remembers of the fires and the treats. Its part of the
## save is `memories` (CampSystem.to_dict). The villagers at rest are
## CampRest's, the signs of closeness CampSigns's. What the people say is in
## their sheets (PeopleBook); when they say it is the Storyteller's. The part
## reads no input: the sip of the mug comes as a signal.

## How near a person hears and is heard, and how near a companion walks "with"
## the player.
const TALK_REACH := 5.0
const WALK_REACH := 12.0
## The pace (m/s) under which the player has stopped to listen.
const STILL_SPEED := 0.6
## Seconds walked together and seconds sat beside that warm (spec 7.1).
const WALK_SECONDS := 180.0
const SIT_SECONDS := 120.0
## How near the place a companion loves the companion and the player must be
## for both to have come to it.
const PLACE_REACH := 6.0
const PLACE_PLAYER_REACH := 10.0
## Seconds between looks for a sign of closeness to show (CampSigns.look).
const SIGNS_SECONDS := 0.5

var camp: CampSystem
var rest: CampRest
var signs: CampSigns
## What each villager remembers of the fires and the treats ({camp, shared}),
## by their sheet (VillageNPC.person_id).
var memories: Dictionary = {}
## The day and the zone of the last frame, and the seconds of this day spent
## with each villager: "<person>:<event>" -> seconds.
var _day := 0
var _zone := ""
var _together: Dictionary = {}
var _signs_clock := 0.0

func _ready() -> void:
	rest = CampRest.new(camp)
	signs = CampSigns.new(camp)
	camp.player.viewmodel.sipped.connect(_sipped)

func _process(delta: float) -> void:
	if not camp.in_play():
		return
	keep_company(delta)
	_signs_clock += delta
	if _signs_clock >= SIGNS_SECONDS:
		_signs_clock = 0.0
		signs.look()

## What the villager remembers of the fires and the treats; {} for a
## passer-by without a sheet.
func memory(actor: VillageNPC) -> Dictionary:
	if actor.person_id.is_empty():
		return {}
	return memories.get(actor.person_id, {})

## Keeps what `actor` remembers under their sheet; a passer-by without one
## remembers nothing.
func _remember(actor: VillageNPC, known: Dictionary) -> void:
	if not actor.person_id.is_empty():
		memories[actor.person_id] = known

## A villager was treated to `food` ("potato" or "fish"): they remember it,
## warm to it — more to the food they love — and say their thanks.
func fed(actor: VillageNPC, food: String) -> void:
	var known := memory(actor)
	known["shared"] = Values.whole(known.get("shared", 0)) + 1
	_remember(actor, known)
	var loved := camp.population.people.sheet(actor.person_id).favorite_food == food
	warm(actor, "food", Acquaintance.FAVORITE_FOOD if loved else -1)
	camp.say(actor, line_of(actor, "food_" + food))
	camp.mark_changed()

## A cook was brought a raw catch.
func brought_catch(actor: VillageNPC) -> void:
	warm(actor, "catch")
	camp.say(actor, line_of(actor, "catch"))

## What the person says for `key` at the circle the player has reached with
## them: their own line, else the common one.
func line_of(actor: VillageNPC, key: String) -> String:
	return camp.population.people.line_at(actor.person_id, key)

## The circle the player has reached with the villager; 0 with a passer-by.
func circle_of(actor: VillageNPC) -> int:
	var bond := camp.population.people.bond(actor.person_id)
	return bond.circle if bond != null else 0

## Counts an event of the spec's table (7.1) for a villager, once a game day,
## and opens the next circle when the warmth has reached it. A passer-by
## without a sheet keeps no warmth.
func warm(actor: VillageNPC, event: String, amount := -1) -> void:
	var bond := camp.population.people.bond(actor.person_id)
	if bond == null:
		return
	var today := camp.current_day()
	if bond.note(event, today, amount) > 0:
		bond.settle(today)
		camp.mark_changed()

## The player asked a companion or a villager at rest to talk (E on them).
func talk(actor: VillageNPC) -> void:
	var teller := teller_of(actor)
	if teller == null:
		return
	var speaker := telling_now()
	voice_line(actor, teller.ask(moment_of(actor), speaker == null or speaker == teller))

## The villager's voice: the outing's for a companion, their own otherwise;
## null for a passer-by who is not one.
func teller_of(actor: VillageNPC) -> Storyteller:
	if actor.outing != null:
		return actor.outing.teller
	return camp.population.people.teller(actor.person_id)

## The moment as the villager's storyteller takes it (Storyteller).
func moment_of(actor: VillageNPC) -> Dictionary:
	if actor.outing != null:
		return _moment_for(actor.outing)
	return rest.moment(actor)

## Whether the companion and the player stand at the place the companion loves.
func at_favorite(actor: VillageNPC) -> bool:
	var path := camp.company.favorite_path(actor)
	if path.is_empty():
		return false
	var place := path[path.size() - 1]
	var player := camp.player
	return Vector2(actor.global_position.x, actor.global_position.z).distance_to(place) < PLACE_REACH \
		and Vector2(player.global_position.x, player.global_position.z).distance_to(place) < PLACE_PLAYER_REACH

## The companion and the player have come to the place the companion loves,
## led there or not: once an outing.
func reach_favorite(outing: NpcOuting) -> void:
	outing.reached_favorite = true
	warm(outing.actor, "favorite_place")
	camp.say(outing.actor, line_of(outing.actor, "favorite"))

## The companion sat down by the fire: the fire is remembered, an old one
## warms, a close companion brings a treat (CampSigns.treat), and they say so.
func arrive_at_fire(outing: NpcOuting) -> void:
	var actor := outing.actor
	var known := memory(actor)
	var key := CampFires.fire_key(outing.fire)
	var familiar: bool = known.get("camp", "") == key
	known["camp"] = key
	_remember(actor, known)
	if familiar:
		warm(actor, "old_camp")
	var words := line_of(actor, "fire_old" if familiar else "fire_new")
	if signs.treat(outing) and not line_of(actor, "treat").is_empty():
		words = line_of(actor, "treat")
	camp.say(actor, words)
	camp.mark_changed()

## The player took a sip. Companions resting near raise their mugs, and it is
## a toast with the villagers at rest the player sits or stands at the bar
## with; the one telling a story, or else the nearest companion, or else the
## nearest villager visited, goes on with their story by a beat; when there is
## no story to move, the toast is said aloud.
func _sipped() -> void:
	var toasted: VillageNPC
	for outing in camp.company.companions:
		if is_instance_valid(outing) and outing.mode == NpcOuting.Mode.REST \
				and camp.player.global_position.distance_to(outing.actor.global_position) < 4.0:
			outing.toast()
			warm(outing.actor, "toast")
			if toasted == null:
				toasted = outing.actor
	var host: VillageNPC = rest.toast()
	if toasted == null:
		toasted = host
	var speaker := _storyteller()
	if speaker == null:
		speaker = camp.company.nearest_companion(TALK_REACH)
	if speaker == null:
		speaker = rest.nearest_visited()
	if speaker != null and voice_line(speaker, teller_of(speaker).sip(moment_of(speaker), true)):
		return
	if toasted != null and not camp.hud.speaking():
		camp.say(toasted, line_of(toasted, "toast"))

## Keeps the company the player is in: counts the time walked and sat
## together, notices the place a companion loves, and lets each companion and
## each villager at rest the player has come up to speak when it is their turn.
func keep_company(delta: float) -> void:
	var people := camp.population.people
	var today := camp.current_day()
	if today != _day:
		_day = today
		_together.clear()
		# A circle the day's rule held back opens with the new day.
		for id: String in people.bonds:
			if people.bond(id).settle(today):
				camp.mark_changed()
	var zone := camp.valley.zone if camp.valley != null else ""
	var moved := zone != _zone
	_zone = zone
	var speaker := telling_now()
	for outing in camp.company.companions:
		if not is_instance_valid(outing) or not outing.along:
			continue
		# Another zone is another halt.
		if moved:
			outing.halt += 1
		var actor := outing.actor
		var near := camp.player.global_position.distance_to(actor.global_position)
		if outing.mode == NpcOuting.Mode.REST:
			if near < TALK_REACH and camp.interactions.seated.get("camp", false):
				spend(actor, "sit", delta, SIT_SECONDS)
		elif near < WALK_REACH:
			spend(actor, "walk", delta, WALK_SECONDS)
		if not outing.reached_favorite and at_favorite(actor):
			reach_favorite(outing)
		voice_line(actor, outing.teller.advance(delta, _moment_for(outing), speaker == null or speaker == outing.teller,
			not camp.hud.speaking() and near <= TALK_REACH))
	rest.keep(delta, speaker)

## Adds `delta` to the seconds of today spent in `event` with the villager;
## the event counts when they come to `enough`.
func spend(actor: VillageNPC, event: String, delta: float, enough: float) -> void:
	if not camp.population.people.knows(actor.person_id):
		return
	var key := actor.person_id + ":" + event
	var before: float = _together.get(key, 0.0)
	_together[key] = before + delta
	if before < enough and before + delta >= enough:
		warm(actor, event)

## The moment as the companion's storyteller takes it (Storyteller).
func _moment_for(outing: NpcOuting) -> Dictionary:
	var now: Dictionary = camp.valley.moment() if camp.valley != null else ValleyLoop.STILL.duplicate()
	var by_fire := outing.mode == NpcOuting.Mode.REST
	var still := player_still()
	var bond := camp.population.people.bond(outing.actor.person_id)
	var activity := PeopleIds.ACTIVITY_STAND if still else PeopleIds.ACTIVITY_WALK
	if by_fire:
		activity = PeopleIds.ACTIVITY_FIRE
	elif at_table():
		activity = PeopleIds.ACTIVITY_TABLE
	now["activity"] = String(activity)
	now["listening"] = (by_fire or still) and camp.player.global_position.distance_to(outing.actor.global_position) <= TALK_REACH
	now["halt"] = outing.halt
	now["company"] = rest.company(outing.actor)
	now["gift"] = bond.gift(camp.current_day()) if bond != null else ""
	now["can_guide"] = not camp.company.favorite_path(outing.actor).is_empty() and not outing.reached_favorite \
		and outing.mode != NpcOuting.Mode.GUIDE
	return now

## Whether the player has stopped: stands, or sits.
func player_still() -> bool:
	return Vector2(camp.player.velocity.x, camp.player.velocity.z).length() < STILL_SPEED

## Whether the player sits on a seat of the tavern, not on a log by a fire.
func at_table() -> bool:
	var seated := camp.interactions.seated
	var camp_seat: bool = seated.get("camp", false)
	return not seated.is_empty() and not camp_seat

## The storyteller who is telling a story now, null when nobody is.
func telling_now() -> Storyteller:
	var actor := _storyteller()
	return teller_of(actor) if actor != null else null

## The villager who is telling a story now, a companion or one at rest; null
## when nobody is.
func _storyteller() -> VillageNPC:
	var people := camp.population.people
	for outing in camp.company.companions:
		if is_instance_valid(outing) and outing.along and not outing.teller.telling.is_empty():
			return outing.actor
	for actor in camp.population.actors:
		if actor.outing == null and people.knows(actor.person_id) and not people.teller(actor.person_id).telling.is_empty():
			return actor
	return null

## Shows a storyteller's line; false when there is none. A beat of a shared
## story (PersonSheet) is said by the one of the two whose it is, and the
## story heard to the end warms the other teller as well.
func voice_line(actor: VillageNPC, line: Dictionary) -> bool:
	if line.is_empty():
		return false
	var population := camp.population
	var by: String = line.get("by", "")
	var voice := actor
	if not by.is_empty() and by != actor.person_id:
		# The second teller speaks while they are beside the first; a beat of
		# one who has gone is the first teller's to say.
		var other := population.actor_of(by)
		if other != null and other.present() \
				and other.global_position.distance_to(actor.global_position) <= CampRest.COMPANY_REACH:
			voice = other
	camp.say(voice, str(line.text))
	if line.kind == "beat" or line.kind == "hook_after":
		# The story's last beat ends the telling as it is said: one who walks
		# about their work stays for its caption, and until the hook that
		# follows it has been said.
		var words: String = line.text
		actor.stop_to_talk(camp.player.global_position, 0.0,
			Storyteller.caption_seconds(words) + Storyteller.NEXT_PAUSE + VillageNPC.TALK_HOLD)
	if line.kind == "introduce":
		# From now on the person goes by the name.
		population.refresh_titles()
	var partner: String = line.get("with", "")
	var last: bool = line.get("last", false)
	if last:
		# The story has warmed its teller (Acquaintance.finish): the circle it
		# has reached opens now.
		var bond := population.people.bond(actor.person_id)
		if bond != null:
			bond.settle(camp.current_day())
		if not partner.is_empty() and population.actor_of(partner) != null:
			warm(population.actor_of(partner), "story")
	camp.mark_changed()
	return true
