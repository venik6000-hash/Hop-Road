extends RefCounted
## Render budgets (GameSettings.render_quality), applied while the game runs.
##
## "maximum" is the picture as it was authored, 1280 x 720 shaded pixels
## resolved by TAA, in a window of that size or smaller. Every tier shades a
## fixed number of pixels, whatever the window measures, and lets MetalFX
## rebuild a larger window's resolution from them over the frames. That upscaler resolves the same
## per-frame jitter TAA does (cloud march, foliage alpha, the trees' LOD
## dither), so nothing that relies on it changes. The tiers also shorten the
## work whose cost does not fall with the pixel count: the sun's shadow range,
## the cloud march and the ambient occlusion.

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
## The upscaler's input must stay inside its range after the sizes are
## rounded to whole pixels.
const SCALE_MARGIN := 1.03
## Texture mip bias under the temporal upscaler, on top of the engine's own
## for the scale. The upscaler rebuilds the window's detail from jittered
## frames, so textures bear a sharper level than the shaded pixels alone
## would: grass blades, bark and ground read crisper at no cost in frame time.
const TEMPORAL_MIP_BIAS := -0.5

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
			light.directional_shadow_max_distance = preset.shadow_distance
			light.directional_shadow_blend_splits = preset.shadow_blend
		# Past the shadow map the trees' shadow is the canopy field's
		# (src/vegetation/shaders/canopy.gdshaderinc).
		RenderingServer.global_shader_parameter_set("sun_shadow_reach",
			Vector2(sky.sun.directional_shadow_fade_start, 1.0) * preset.shadow_distance)
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
	var limits := _temporal_upscale_range()
	if scale < 0.999 and limits.y > 0.0:
		scale = clampf(scale, limits.x * SCALE_MARGIN, limits.y)
		viewport.use_taa = false
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
		viewport.texture_mipmap_bias = TEMPORAL_MIP_BIAS
	elif scale < 0.999:
		# No temporal upscaler on this device: TAA on the smaller image, then
		# FSR 1 to the window. (FSR 2 costs more than it saves here.)
		scale = maxf(scale, 0.5)
		viewport.use_taa = true
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		viewport.texture_mipmap_bias = 0.0
	else:
		scale = 1.0
		viewport.use_taa = true
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.texture_mipmap_bias = 0.0
	viewport.scaling_3d_scale = scale
	# The engine measures the mesh LOD error in window pixels; keep it one
	# pixel of the image that is actually shaded.
	viewport.mesh_lod_threshold = 1.0 / scale
	return scale

## Smallest and largest 3D scale MetalFX's temporal scaler takes (0, 0 where
## the device or the renderer has none).
static func _temporal_upscale_range() -> Vector2:
	var device := RenderingServer.get_rendering_device()
	if device == null or not device.has_feature(RenderingDevice.SUPPORTS_METALFX_TEMPORAL):
		return Vector2.ZERO
	return Vector2(device.limit_get(RenderingDevice.LIMIT_METALFX_TEMPORAL_SCALER_MIN_SCALE),
		device.limit_get(RenderingDevice.LIMIT_METALFX_TEMPORAL_SCALER_MAX_SCALE)) / 1e6
