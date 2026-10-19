class_name NpcJob
extends RefCounted
## What a villager does at their work (VillageNPC.duty, docs/LIFE.md,
## «Работы»). The region's villagers file names a job by its id; the job is
## the script `<folder><id>.gd` of the first of `folders` that has it, an
## NpcJob. Each villager gets a job of their own. The script brings the
## job's props, what it sets up at the place of work (NpcPopulation), its
## tick at work and its answers to the day's questions. A new job is a new
## script in FOLDER and the data that names it: no other file changes.

const FOLDER := "res://src/npc/jobs/"
## The folders a job's script is looked for in, in turn. A test puts its own
## folder in front.
static var folders: PackedStringArray = [FOLDER]

## The job's id: the stem of its script.
var id := ""
## Whether the villager walks the village road. A walker steps onto kerbs and
## stairs, is asked along from the road and goes back to it; any other job
## keeps the villager at a place of work.
var walks := false
## Whether the villager keeps the hall: the round waits for the hall's paths
## (NpcRounds.find_hall_paths), the stops with a top are wiped, and a story
## stops the round with the villager turned to the listener.
var keeps_hall := false
## Whether a raw catch may be brought to the villager at their work.
var takes_catch := false

## The script of the job `job_id`, "" when no folder has one.
static func path_of(job_id: String) -> String:
	if job_id.is_empty():
		return ""
	for folder in folders:
		var path := folder + job_id + ".gd"
		if ResourceLoader.exists(path):
			return path
	return ""

## Whether a job of `job_id` exists.
static func exists(job_id: String) -> bool:
	return not path_of(job_id).is_empty()

## A new job `job_id` for one villager. A missing script is an error; the
## villager then gets this bare job, which only plays the clip of its id.
static func make(job_id: String) -> NpcJob:
	var job: NpcJob = null
	var path := path_of(job_id)
	if not path.is_empty():
		var script := load(path) as GDScript
		var made: Variant = script.new() if script != null else null
		if made is NpcJob:
			job = made
	if job == null:
		push_error("NpcJob: no job '%s' in %s" % [job_id, ", ".join(folders)])
		job = NpcJob.new()
	job.id = job_id
	return job

## Gives the villager what the job holds and wears: a knife, a spoon, a rag.
## Called once the model and the skeleton are in (VillageNPC._ready).
func setup(_actor: VillageNPC) -> void:
	pass

## Sets up the place of work from the region's work file (RegionDef.tavern_work,
## {} without one): the bar, the board, the pot, the round of the hall.
## Called once the villager stands at `actor.work_point` (NpcPopulation).
func place_work(_population: NpcPopulation, _actor: VillageNPC, _work: Dictionary) -> void:
	pass

## A physics tick of the villager at their work: not on an outing, not on a
## seat of the hall or a spot of the yard. The round is walked; one without
## a round plays the clip named as the job.
func tick(actor: VillageNPC, delta: float) -> void:
	if not actor.rounds.route.is_empty():
		actor.rounds.walk(delta)
	else:
		actor.play(id)

## A frame after the poses (VillageNPC._process): what the hand holds follows it.
func frame(_actor: VillageNPC, _delta: float) -> void:
	pass

## The villager leaves the place of work (VillagerPresence): what was under
## way there is put back in order.
func leave(_actor: VillageNPC) -> void:
	pass

## The prompt at the villager at work when E is the job's (TavernInteractions),
## translated; "" when it is not.
func interaction_text(_actor: VillageNPC) -> String:
	return ""

## E on the villager at work. False when the job has nothing for it.
func interact(_actor: VillageNPC, _player: Player) -> bool:
	return false

## A rag for the hands of the villager (NpcWipe): the strip `strip` wiped,
## or the rag's own strip when it is empty. Null for a model without a
## skeleton.
static func add_wipe(actor: VillageNPC, strip: Dictionary = {}) -> NpcWipe:
	if actor.skeleton == null:
		return null
	var wipe := NpcWipe.new()
	wipe.name = "Wipe"
	wipe.actor = actor
	if not strip.is_empty():
		wipe.set_strip(strip)
	actor.add_child(wipe)
	return wipe
