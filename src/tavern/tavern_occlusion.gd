class_name TavernOcclusion
extends Node3D
## Real opaque faces, inset within their triangles. Includes floors and upper
## walls without sealing windows, stair openings, the attic hatch or board gaps.
## Regenerate with tools/pipeline/tavern/tavern_static.py --write after model edits.
const GEOMETRY := preload("res://src/tavern/tavern_occluder.tres")

func _ready() -> void:
	get_viewport().use_occlusion_culling = true
	var holder := OccluderInstance3D.new()
	holder.name = "OpaqueStructure"
	holder.occluder = GEOMETRY
	add_child(holder)
