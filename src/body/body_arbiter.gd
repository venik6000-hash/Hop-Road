class_name BodyArbiter
extends RefCounted
## Who drives each part of a body now (docs/plans/body.md, section 2): the
## player's hands and mouth (BodyChannels) and a villager's limbs (NpcBody)
## by one set of rules.
##
## A doer claims the parts its row of the table gives it and lets them go
## when it is done. A part goes to the claim of the highest layer; of two on
## one layer, to the earlier. A claim is refused as a whole when any of its
## parts is held by a doer of the same or a higher layer. A doer of a lower
## layer that holds a thing (`holds`) gives its parts up only to a doer that
## needs that thing (`needs`) or puts it away (`stows`). An outranked doer
## keeps its claim and drives its parts again when the higher one is done.
##
## A claim may bring a test of whether its doer is still at it: audit() lets
## go of a claim whose doer is not, and says so with `leaked`. What a doer
## drives is eased in and out over its `fade`, never switched.

signal changed
signal leaked(doer: StringName)

## The parts, as bits. An arm places the hand; a grip closes the fingers.
const ARM_R := 1
const ARM_L := 2
const GRIP_R := 4
const GRIP_L := 8
const LEGS := 16
const HEAD := 32
const MOUTH := 64
const PARTS: Array[int] = [ARM_R, ARM_L, GRIP_R, GRIP_L, LEGS, HEAD, MOUTH]
const ALL := 127

## The layers, low to high: a higher one takes the part.
enum Layer {BASE, POSTURE, HOLD, WORK, GESTURE, REACTION, SCRIPT}

## Seconds over which a doer takes a part or gives it back, unless its row
## says otherwise.
const FADE := 0.4

## Doer -> its row: {parts: int, layer: Layer, holds: StringName,
## needs: StringName, stows: Array[StringName], fade: float}. Only `parts`
## and `layer` must be given.
var doers: Dictionary
## Doer -> the parts it has claimed.
var _claims: Dictionary[StringName, int] = {}
## The doers in the order of their claims.
var _order: Array[StringName] = []
## Doer -> its test of whether it is still at it.
var _busy: Dictionary[StringName, Callable] = {}
## Doer -> seconds left of a claim that ends by itself.
var _until: Dictionary[StringName, float] = {}
## Doer -> how far it drives each part of PARTS, 0..1, not eased.
var _drive: Dictionary[StringName, PackedFloat32Array] = {}

func _init(table: Dictionary) -> void:
	doers = table

## The doer of the highest layer that has any of `parts`, &"" for none.
func holder(parts: int) -> StringName:
	var best := &""
	for doer: StringName in _order:
		if _claims[doer] & parts and (best == &"" or _rank(doer) > _rank(best)):
			best = doer
	return best

## Whether `doer` has claimed any of `parts`, whether it drives them now or not.
func has(doer: StringName, parts := ALL) -> bool:
	return _claims.get(doer, 0) & parts != 0

## Whether a doer that holds `thing` drives any of its parts now.
func holds(thing: StringName) -> bool:
	for doer: StringName in _order:
		var row: Dictionary = doers[doer]
		if row.get("holds", &"") == thing and drives(doer):
			return true
	return false

## The doer that stops `doer` claiming `parts` (its row's by default), &"" when
## none does. A thing `doer` needs and nobody holds is answered by the doer
## that would hold it.
func blocker(doer: StringName, parts := -1) -> StringName:
	var row: Dictionary = doers[doer]
	if parts < 0:
		parts = Values.whole(row.parts)
	var needs: StringName = row.get("needs", &"")
	if needs != &"" and not holds(needs):
		var keeper := _keeper(needs)
		return holder(Values.whole(doers[keeper].parts)) if has(keeper) else keeper
	var stows: Array = row.get("stows", [])
	for part in PARTS:
		if not part & parts:
			continue
		var other := holder(part)
		if other == &"" or other == doer:
			continue
		if _rank(other) >= _rank(doer):
			return other
		var other_row: Dictionary = doers[other]
		var thing: StringName = other_row.get("holds", &"")
		if thing != &"" and thing != needs and not stows.has(thing):
			return other
	return &""

## Gives `doer` `parts` (its row's by default) besides those it has, while
## `busy` returns true (no test when it is not valid). False, and nothing
## given, when blocker() names a doer. A doer that has its parts claims
## again with a new test.
func claim(doer: StringName, busy := Callable(), parts := -1) -> bool:
	assert(doers.has(doer), "BodyArbiter: unknown doer %s" % doer)
	if blocker(doer, parts) != &"":
		return false
	if parts < 0:
		parts = Values.whole(doers[doer].parts)
	var before := Values.whole(_claims.get(doer, 0))
	if before == 0:
		_order.append(doer)
	_claims[doer] = before | parts
	if busy.is_valid():
		_busy[doer] = busy
	_until.erase(doer)
	if _claims[doer] != before:
		changed.emit()
	return true

## Claims `parts` for `seconds`; step() lets them go. A claim made again
## before its end lasts `seconds` from now.
func claim_for(doer: StringName, seconds: float, parts := -1) -> bool:
	if not claim(doer, Callable(), parts):
		return false
	_until[doer] = seconds
	return true

## Takes `parts` (all by default) from `doer`.
func release(doer: StringName, parts := ALL) -> void:
	if not _claims.has(doer):
		return
	var left := _claims[doer] & ~parts
	if left == _claims[doer]:
		return
	if left != 0:
		_claims[doer] = left
	else:
		_claims.erase(doer)
		_order.erase(doer)
		_busy.erase(doer)
		_until.erase(doer)
	changed.emit()

## Lets go of each claim whose doer is not at it any more, with `leaked`.
func audit() -> void:
	for doer: StringName in _busy.keys():
		if not _busy.has(doer):
			continue
		var busy: Callable = _busy[doer]
		if not busy.is_valid() or not Values.flag(busy.call()):
			release(doer)
			leaked.emit(doer)

## Moves the time on by `delta` seconds: claims for a time end, and every
## doer goes over its fade from not driving a part to driving it in full.
## False when nothing drives any part.
func step(delta: float) -> bool:
	for doer: StringName in _until.keys():
		_until[doer] -= delta
		if _until[doer] <= 0.0:
			release(doer)
	for doer: StringName in _claims:
		if not _drive.has(doer):
			var empty := PackedFloat32Array()
			empty.resize(PARTS.size())
			_drive[doer] = empty
	var busy := false
	for doer: StringName in _drive.keys():
		var drive: PackedFloat32Array = _drive[doer]
		var row: Dictionary = doers[doer]
		var rate := delta / Values.real(row.get("fade", FADE))
		var left := false
		for index in PARTS.size():
			var goal := 1.0 if holder(PARTS[index]) == doer else 0.0
			drive[index] = move_toward(drive[index], goal, rate)
			left = left or drive[index] > 0.0
		if left:
			_drive[doer] = drive
			busy = true
		else:
			_drive.erase(doer)
	return busy

## How far `doer` drives `part`, 0..1, eased at both ends.
func weight(doer: StringName, part: int) -> float:
	if not _drive.has(doer):
		return 0.0
	var linear := _drive[doer][PARTS.find(part)]
	return linear * linear * (3.0 - 2.0 * linear)

## How far all doers together drive `part`, 0..1: the rest is the layer below.
func total(part: int) -> float:
	var sum := 0.0
	for doer: StringName in _drive:
		sum += weight(doer, part)
	return minf(sum, 1.0)

## The doers that drive `part` at all now.
func drivers(part: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for doer: StringName in _drive:
		if weight(doer, part) > 0.0:
			found.append(doer)
	return found

## Whether `doer` drives any part now: it has it and no higher doer does.
func drives(doer: StringName) -> bool:
	for part in PARTS:
		if holder(part) == doer:
			return true
	return false

func _rank(doer: StringName) -> int:
	return Values.whole(doers[doer].layer)

## The doer of the table that holds `thing`.
func _keeper(thing: StringName) -> StringName:
	for doer: StringName in doers:
		var row: Dictionary = doers[doer]
		if row.get("holds", &"") == thing:
			return doer
	assert(false, "BodyArbiter: no doer holds %s" % thing)
	return &""
