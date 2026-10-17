@tool
class_name RegionSpawn
extends Resource
## A place where the player comes into a region (RegionDef.spawns).

@export var id: StringName
## Where the player stands before the ground is found under them.
@export var position := Vector3.ZERO
## The camera's turn and tilt there (degrees, CameraRig).
@export var yaw_deg := 0.0
@export var pitch_deg := 0.0
