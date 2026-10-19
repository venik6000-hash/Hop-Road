extends NpcJob
## The one who keeps the hall: walks the round of the work file (`round`)
## between the furniture and wipes the tops at its stops (`wipes`, NpcRounds).
## A story she tells stops the round, and she turns to the listener.

func _init() -> void:
	keeps_hall = true

func setup(actor: VillageNPC) -> void:
	actor.wipe = add_wipe(actor)
	actor.rounds.find_hall_paths.call_deferred()

func place_work(_population: NpcPopulation, actor: VillageNPC, work: Dictionary) -> void:
	if not work.has("round"):
		return
	var round_route: Array[Vector3] = [actor.work_point]
	for point: Variant in Values.list(work.round):
		round_route.append(Values.vec3(point))
	actor.rounds.route.assign(round_route)
	# She wipes the counter facing it, the other hand on its top, and the small
	# table by it from its free side, a narrower strip on the round top and the
	# other hand at her side.
	for wipe: Dictionary in Values.list(work.wipes):
		var row := wipe.duplicate()
		row.rest = Values.vec3(wipe.rest)
		actor.rounds.wipes[Values.whole(wipe.stop)] = row
