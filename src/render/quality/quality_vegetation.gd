class_name QualityVegetation
extends QualityGroup
## The vegetation's share of a QualityProfile: how far the grass and the
## tree meshes reach and how thick the meadow grows.

## Where the grass starts to fade and where it is gone, m (the shader's
## fade_start and fade_end).
@export var grass_fade := Vector2(95.0, 115.0)
## Where the last mesh LOD of a tree starts to give way to its impostor and
## where it is gone, m. It sets the bands of the forest when it is built.
@export var tree_mesh_reach := Vector2(145.0, 165.0)
## Clumps of grass to the square metre of open meadow, flowers where the
## flower mask is full, and clumps of the low mat (GrassField).
@export var grass_density := 9.0
@export var flower_density := 1.4
@export var mat_density := 12.0

func read_at_start() -> Array[StringName]:
	return [&"tree_mesh_reach", &"grass_density", &"flower_density", &"mat_density"]
