class_name BodyChannels
extends BodyArbiter
## Who has the player's hands and mouth now (docs/PLAYER.md, «Руки и рот»),
## by the rules of BodyArbiter. A refused claim gives nothing, and
## busy_text() tells the player what is in the way.
##
## The mug is the doer of the right hand's lowest layer: the player claims
## it once, the brewery and the rod put it away while they have the hands,
## and it comes back when they let go. A sip needs the mug in the hand.
##
## Each claim brings a test of whether its doer is still at it: a claim
## cannot outlive its doer (BodyArbiter.audit).

## The parts.
const RIGHT_HAND := BodyArbiter.ARM_R | BodyArbiter.GRIP_R
const LEFT_HAND := BodyArbiter.ARM_L | BodyArbiter.GRIP_L
const HANDS := RIGHT_HAND | LEFT_HAND

## The doers.
## The mug in the right hand (Player).
const MUG := &"mug"
## A brewery's thing carried, or a brewery's station worked (BrewHouse).
const BREWERY := &"brewery"
## The fishing rod out (LakesideSystem).
const ROD := &"rod"
## A baked potato in the left hand (CampSystem).
const POTATO := &"potato"
## A sip from the mug (BeerViewmodel.drink).
const DRINK := &"drink"
## A bite of the potato (CampSystem.eat).
const BITE := &"bite"

const DOERS := {
	MUG: {"parts": RIGHT_HAND, "layer": Layer.HOLD, "holds": &"mug"},
	POTATO: {"parts": LEFT_HAND, "layer": Layer.HOLD, "holds": &"potato"},
	BREWERY: {"parts": HANDS, "layer": Layer.WORK, "stows": [&"mug"]},
	ROD: {"parts": HANDS, "layer": Layer.WORK, "stows": [&"mug"]},
	DRINK: {"parts": MOUTH | ARM_R, "layer": Layer.GESTURE, "needs": &"mug"},
	BITE: {"parts": MOUTH, "layer": Layer.GESTURE},
}

## The doers that put the player's arms (Player.arms) on what they hold.
const ARMS_DOERS: Array[StringName] = [BREWERY, ROD, POTATO]

## What the player is told when a doer is in the way of another.
const BUSY: Dictionary[StringName, String] = {
	MUG: "Кружки нет в руке.",
	BREWERY: "Руки заняты: {interact} — положить ношу или отойти от работы.",
	ROD: "{fishing_rod} — убери удочку.",
	POTATO: "Сначала доешь или раздели картошку: {eat_potato} / {camp_secondary}.",
	DRINK: "Сначала допей.",
	BITE: "Сначала прожуй.",
}

func _init() -> void:
	super(DOERS)

## What stops `doer` taking its parts, "" when nothing does.
func busy_text(doer: StringName) -> String:
	var other := blocker(doer)
	return "" if other == &"" else BUSY[other]

## Whether the mug is in the right hand.
func mug_in_hand() -> bool:
	return holder(GRIP_R) == MUG

## Whether a doer that puts the arms on its thing drives the hands.
func arms_held() -> bool:
	return ARMS_DOERS.any(drives)
