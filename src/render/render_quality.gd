extends RefCounted
## Render budgets (GameSettings.render_quality), applied while the game runs.
##
## "maximum" is the picture as it was authored, 1280 x 720 shaded pixels
## resolved by TAA, in a window of that size or smaller. Every tier shades a
## fixed number of pixels, whatever the window measures; a larger window gets
## them resolved by TAA and enlarged by FSR 1. (MetalFX's temporal upscaler
## left a grid of dots along every hard edge of a still picture, which
## flickered from frame to frame; FSR 2 costs more than it saves here.) The
## tiers also shorten the work whose cost does not fall with the pixel count:
## the sun's shadow range, the cloud march and the ambient occlusion.

const TIERS := ["performance", "balanced", "maximum"]
const DEFAULT := "balanced"
## pixels: 3D pixels shaded per frame.
## shadow_distance: reach of the sun's shadow cascades, m.
## shadow_size: the sun's shadow atlas, px.
## cloud_steps: samples of the cloud march along a view ray.
const PRESETS := {
	"performance": {"pixels": 300000, "ssao": RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		"shadow_distance": 90.0, "shadow_size": 2048, "shadow_blend": false, "cloud_steps": 36},
	"balanced": {"pixels": 450000, "ssao": RenderingServer.ENV_SSAO_QUALITY_LOW,
		"shadow_distance": 120.0, "shadow_size": 4096, "shadow_blend": true, "cloud_steps": 48},
	"maximum": {"pixels": 921600, "ssao": RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		"shadow_distance": 160.0, "shadow_size": 4096, "shadow_blend": true, "cloud_steps": 64},
}
static func valid(tier: String) -> String:
	return tier if tier in TIERS else DEFAULT

## The tier the settings hold (the default without them, as in tools that
## build the level alone).
static func selected(tree: SceneTree) -> String:
	var settings := tree.root.get_node_or_null("GameSettings")
	return valid(str(settings.render_quality)) if settings != null else DEFAULT

static func apply(viewport: Viewport, sky: SkySystem, tier: String) -> void:
	var preset: Dictionary = PRESETS[valid(tier)]
	var scale := apply_resolution(viewport, tier)
	RenderingServer.environment_set_ssao_quality(preset.ssao, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.directional_shadow_atlas_set_size(preset.shadow_size, true)
	if sky != null:
		for light: DirectionalLight3D in [sky.sun, sky.moon]:
			light.directional_shadow_blend_splits = preset.shadow_blend
		# The tier's reach outdoors; an eye in the tavern's rooms takes less.
		TavernPortals.set_shadow_reach(sky, preset.shadow_distance)
		sky.sky_material.set_shader_parameter("march_steps", preset.cloud_steps)
	print("RENDER_QUALITY tier=%s scale=%.3f internal=%s window=%s mode=%d" % [valid(tier), scale,
		Vector2i(Vector2(viewport.size) * scale), viewport.size, viewport.scaling_3d_mode])

## Sets the 3D resolution of `viewport` for `tier` and returns its scale. Call
## again when the window changes size: the budget is in pixels.
static func apply_resolution(viewport: Viewport, tier: String) -> float:
	var budget: int = PRESETS[valid(tier)].pixels
	var size := Vector2(viewport.size)
	var scale := 1.0
	if size.x * size.y > budget:
		scale = sqrt(budget / (size.x * size.y))
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if scale < 0.999:
		scale = maxf(scale, 0.5)
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		# FSR's own sharpening off (2 is none): it sharpened what TAA had left
		# of its jitter, and a still picture crawled. SharpenPost sharpens.
		viewport.fsr_sharpness = 2.0
	else:
		scale = 1.0
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.use_taa = true
	viewport.texture_mipmap_bias = 0.0
	viewport.scaling_3d_scale = scale
	# The engine measures the mesh LOD error in window pixels; keep it one
	# pixel of the image that is actually shaded.
	viewport.mesh_lod_threshold = 1.0 / scale
	return scale
