class_name QualityPost
extends QualityGroup
## The post passes' share of a QualityProfile: the ambient occlusion and the
## eye's light meter.

@export var ssao := RenderingServer.ENV_SSAO_QUALITY_MEDIUM
## The light meter (LightMeter) asks for a reading once in this many frames.
@export_range(1, 16) var meter_every := 4

func read_at_start() -> Array[StringName]:
	return [&"meter_every"]
