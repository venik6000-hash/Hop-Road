class_name BrewJournal
extends RefCounted
## The batch's journal for the brewer's book (BrewBatch.journal): a line for
## each step with its numbers, the field `step` naming it. A run of the same
## step is kept as one line.

## Steps whose runs the journal keeps as one line: these numbers are summed,
## the others are the last step's. A boil at another fire starts a new line.
const RUNS := {"rest": ["minutes"], "boil": ["minutes"], "cool": ["hours"], "grain": ["kg"], "pour": ["liters"],
	"spill": ["liters"], "water_down": ["liters"], "pitch": ["yeast_l"]}

## Step `step` with its `numbers` into `journal`.
static func note(journal: Array[Dictionary], step: String, numbers: Dictionary) -> void:
	var entry := {"step": step}
	entry.merge(numbers)
	if RUNS.has(step) and not journal.is_empty():
		var last: Dictionary = journal[journal.size() - 1]
		if last.step == step and last.get("fire") == entry.get("fire"):
			for key: String in RUNS[step]:
				entry[key] = Values.real(last[key]) + Values.real(entry[key])
			journal[journal.size() - 1] = entry
			return
	journal.append(entry)

## Grain poured on with nothing done between but the rest is still the
## mashing in: the line of the mash-in takes the mash's new `grain_kg` and
## `mash_temp`. False when the grain comes after other steps.
static func amend_mash_in(journal: Array[Dictionary], grain_kg: float, mash_temp: float) -> bool:
	for index in range(journal.size() - 1, -1, -1):
		var entry: Dictionary = journal[index]
		if entry.step == "mash_in":
			entry.grain_kg = grain_kg
			entry.mash_temp = mash_temp
			return true
		if entry.step != "rest":
			break
	return false
