class_name QualityEffects
extends QualityGroup
## The effects' share of a QualityProfile: the clouds' march, the fog's grid,
## the rain's drops and the map of what the rain cannot reach.

## Samples of the cloud march along a view ray (the sky's march_steps).
@export var cloud_steps := 64
## Columns, rows and depth slices of the fog's view-aligned grid
## (AtmosphereFog): two 3D textures of that size, marched once a frame.
@export var fog_cells := Vector3i(160, 90, 48)
## Streaks the rain draws round the eye (RainFall): one MultiMesh.
@export var rain_drops := 9000
## Texels along a side of the rain's shelter map (RainShelter, 256 m a side);
## a whole number of RainShelter.TILE.
@export var shelter_cells := 1024

func read_at_start() -> Array[StringName]:
	return [&"fog_cells", &"rain_drops", &"shelter_cells"]
