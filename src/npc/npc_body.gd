class_name NpcBody
extends BodyArbiter
## Who drives a villager's legs, arms and head over the recorded clip now
## (docs/LIFE.md, «Части тела»), by the rules of BodyArbiter. The clip is
## under everything: a gesture takes a hand from the seat and gives it back
## at its end.

## The parts.
const RIGHT_ARM := BodyArbiter.ARM_R
const LEFT_ARM := BodyArbiter.ARM_L
const ARMS := RIGHT_ARM | LEFT_ARM

## The doers.
## Sits on a log or a chair: hips and legs bent, hands on the lap (CampPose,
## NpcArmPose).
const SEAT := &"seat"
## Raises the mug in the right hand (NpcOuting.toast).
const TOAST := &"toast"
## Holds food up in the left hand (NpcOuting.receive_food).
const MEAL := &"meal"
## Stumbles in an active ragdoll after the player bumps into the villager
## (NpcStumble): the whole body, for NpcStumble.SECONDS.
const STUMBLE := &"stumble"
## Draws a beer at the bar (NpcBarWork): the hands at the shelf, the tankard
## and the tap; the trunk bends with them (NpcReach).
const POUR := &"pour"
## Wipes a counter or a table (NpcWipe): the rag hand on the top, the other
## resting on it; the trunk bends with them (NpcReach).
const WIPE := &"wipe"

const DOERS := {
	SEAT: {"parts": LEGS | ARMS, "layer": Layer.POSTURE},
	TOAST: {"parts": RIGHT_ARM, "layer": Layer.GESTURE},
	MEAL: {"parts": LEFT_ARM, "layer": Layer.GESTURE},
	STUMBLE: {"parts": ALL, "layer": Layer.REACTION, "fade": 0.35},
	POUR: {"parts": ARMS, "layer": Layer.WORK, "fade": 0.3},
	WIPE: {"parts": ARMS, "layer": Layer.WORK},
}
## The doers of the layer WORK: they bend the trunk with the arms (NpcReach).
const WORKERS: Array[StringName] = [POUR, WIPE]

func _init() -> void:
	super(DOERS)
