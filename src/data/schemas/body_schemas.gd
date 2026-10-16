class_name BodySchemas
extends RefCounted
## The schemas of the files that move bodies: the joint limits (JointLimits)
## and the facts a recorded motion carries (NpcMotion; docs/LIFE.md).

const D := preload("res://src/data/data_schema.gd")

## joint_limits.json: profiles of limits, each with the body's frame and a
## joint per bone ("*" stands for "R" and "L").
static func joint_limits() -> Dictionary:
	var joint := D.object({
		"bone": D.text(),
		"kind": D.choice(["hinge", "cone"]),
		"axis": D.optional(D.either([D.vector(3), D.choice(["rest", "straight"])])),
		"cone": D.optional(D.number(0.0, 180.0)),
		"bends": D.optional(D.vector(3)),
		"min": D.optional(D.number(-180.0, 180.0)),
		"max": D.optional(D.number(-180.0, 180.0)),
		"play": D.optional(D.number(0.0, 180.0)),
		"twist": D.vector(2, -360.0, 360.0),
		"spill": D.optional(D.flag()),
	})
	var profile := D.object({
		"frame": D.object({"right": D.vector(3), "up": D.vector(3), "forward": D.vector(3)}),
		"joints": D.list(joint, 1),
	})
	return D.object({"profiles": D.object({"villager": profile, "player_arm": profile})})

## assets/models/npc/motion/<model>.json: for each clip of the model, how
## long it runs and where the hands work.
static func npc_motion() -> Dictionary:
	return D.table(D.object({
		"length": D.number(0.0),
		"speed": D.optional(D.number(0.0)),
		"left_hand": D.optional(D.vector(3)),
		"left_hand_reach": D.optional(D.number(0.0)),
		"right_hand": D.optional(D.vector(3)),
		"right_hand_reach": D.optional(D.number(0.0)),
	}))

## assets/audio/lakeside/bank.json: the sound files of the lake's bank, by
## what they sound for (LakeSoundscape).
static func lake_bank() -> Dictionary:
	var sounds := D.list(D.stem(LakeSoundscape.DIRECTORY, ""), 1)
	var keys: Array[String] = ["step_grass", "step_rock", "step_sand", "step_wood", "step_water", "swim", "uw_swim",
		"submerge", "emerge", "pier_lap", "boat_lap", "splash", "plop", "rod_swish", "reel_wind", "fish_splash",
		"fish_flop", "bird_forest", "bird_dove", "crickets", "wind"]
	var fields := {}
	for key in keys:
		fields[key] = sounds
	return D.object(fields)
