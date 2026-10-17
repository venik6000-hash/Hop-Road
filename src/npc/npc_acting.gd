class_name NpcActing
extends RefCounted
## What a villager's body does while they keep to one occupation. An occupation
## is a set of recorded clips: the ones it is made of, each repeated for a
## while, and the short things a person does between them (a yawn, a stretch,
## a drink). The villager asks for the occupation in every tick and gets the
## clip to play now.
## A model without recorded motion plays FALLBACK's clip of its own instead.
const FALLBACK := {"bar": "wipe", "talk": "idle"}
## Occupation -> {loops: clips repeated in turn, breaks: clips played once
## between them}. A clip named twice is picked twice as often.
const SETS := {
	"idle": {"loops": ["idle", "idle_hips", "idle_shift", "idle_arms"],
		"breaks": ["yawn", "stretch", "shrug"]},
	"chop": {"loops": ["chop", "chop", "chop_quick", "slice", "slice", "knead"],
		"breaks": ["stretch", "yawn", "drink", "idle"]},
	"stir": {"loops": ["stir", "stir", "idle"],
		"breaks": ["stretch", "yawn"]},
	"wipe": {"loops": ["wipe"], "breaks": []},
	"bar": {"loops": ["wipe", "wipe", "idle_hips", "idle_shift", "idle_arms"],
		"breaks": ["drink", "yawn", "stretch"]},
	"talk": {"loops": ["talk", "talk_more"], "breaks": ["laugh", "shrug"]},
}
## Seconds a repeated clip is kept, from and to; it ends on a whole repeat.
const HOLD := Vector2(7.0, 15.0)
## Seconds a clip that repeats is played when it stands in for a break.
const GLANCE := 4.0
## The chance that a break follows a repeated clip.
const BREAK_CHANCE := 0.4

## Clip -> its length, seconds: the recorded clips the villager's model has.
var lengths: Dictionary = {}
var kind := ""
var clip := ""
## Whether `clip` is played over and over until its time is up.
var repeats := true
var _until := 0.0
var _random := RandomNumberGenerator.new()


func _init(seed_text := "") -> void:
	_random.seed = hash(seed_text)

## Keeps the body on `held` of `occupation`, repeated, until let_go(): a
## tool holds a clip to look at it.
func hold(occupation: String, held: String) -> void:
	kind = occupation
	clip = held
	repeats = true
	_until = INF

## Ends a hold: the next choice picks the occupation's clip anew.
func let_go() -> void:
	_until = 0.0

## Whether the model has the occupation recorded: the clip it is named for,
## the first of its set.
func knows(occupation: String) -> bool:
	if not SETS.has(occupation):
		return false
	var loops: Array = SETS[occupation].loops
	return lengths.has(loops[0])

## The clip of `occupation` to play at `now`, seconds on the villager's clock.
func choose(occupation: String, now: float) -> String:
	if occupation != kind:
		kind = occupation
		_next(false, now)
	elif now >= _until:
		_next(repeats and _random.randf() < BREAK_CHANCE, now)
	return clip

func _next(pause: bool, now: float) -> void:
	var set_of: Dictionary = SETS[kind]
	var names: Array = set_of.breaks if pause else set_of.loops
	var known: Array[String] = []
	for name: String in names:
		if lengths.has(name) and (name != clip or names.size() == 1):
			known.append(name)
	if known.is_empty():
		for name: String in set_of.loops:
			if lengths.has(name):
				known.append(name)
		pause = false
	if known.is_empty():
		clip = ""
		_until = now + 1.0
		return
	clip = known[_random.randi() % known.size()]
	var length := Values.real(lengths[clip])
	var loops_too: Array = set_of.loops
	if not pause:
		repeats = true
		_until = now + maxf(1.0, ceilf(_random.randf_range(HOLD.x, HOLD.y) / length)) * length
	elif clip.begins_with("idle") or loops_too.has(clip):
		repeats = true
		_until = now + minf(GLANCE, length)
	else:
		repeats = false
		# The next clip is led in before this one stands still on its last frame.
		_until = now + maxf(0.2, length - NpcMotion.BLEND)
