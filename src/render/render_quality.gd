extends RefCounted
## Applies a QualityProfile (GameSettings.profile) while the game runs.
##
## The profile "maximum" is the picture as it was authored, 1280 x 720
## shaded pixels resolved by TAA, in a window of that size or smaller. Every
## profile shades a fixed number of pixels, whatever the window measures; a
## larger window gets them resolved by TAA and enlarged by FSR 1. (MetalFX's
## temporal upscaler left a grid of dots along every hard edge of a still
## picture, which flickered from frame to frame; FSR 2 costs more than it
## saves here.) The lighter profiles also shorten the work whose cost does
## not fall with the pixel count: the sun's shadow range, the cloud march,
## the ambient occlusion, the reach of the grass and of the tree meshes, and
## (after a restart) the grids, the counts and the waves of the systems that
## read their group when the level is built (QualityGroup.read_at_start).

const GAME_SETTINGS = preload("res://src/settings/game_settings.gd")

## The profile the settings hold (the default without them, as in tools that
## build the level alone).
static func selected(tree: SceneTree) -> QualityProfile:
	var settings: GAME_SETTINGS = tree.root.get_node_or_null("GameSettings")
	return settings.profile if settings != null else QualityProfile.named(QualityProfile.DEFAULT)

## Applies `profile` to the window `viewport`, to `sky`, and to the level of
## `world`: the shadows, and the systems that read world.quality.
static func apply(viewport: Viewport, sky: SkySystem, profile: QualityProfile, world: WorldContext) -> void:
	var scale := apply_resolution(viewport, profile)
	RenderingServer.environment_set_ssao_quality(profile.post.ssao, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.directional_shadow_atlas_set_size(profile.shadows.size, true)
	if sky != null:
		sky.apply_shadows(profile.shadows)
		sky.sky_material.set_shader_parameter("march_steps", profile.effects.cloud_steps)
	# The profile's reach of the shadows outdoors; an eye in the tavern's
	# rooms takes less.
	world.set_quality(sky, profile)
	print("RENDER_QUALITY profile=%s scale=%.3f internal=%s window=%s mode=%d" % [profile.id, scale,
		Vector2i(Vector2(_pixel_size(viewport)) * scale), _pixel_size(viewport), viewport.scaling_3d_mode])

## The size of `viewport` in pixels: the window's, or the SubViewport's.
static func _pixel_size(viewport: Viewport) -> Vector2i:
	var window := viewport as Window
	return window.size if window != null else (viewport as SubViewport).size

## Sets the 3D resolution of `viewport` for `profile` and returns its scale.
## Call again when the window changes size: the budget is in pixels.
static func apply_resolution(viewport: Viewport, profile: QualityProfile) -> float:
	var budget := profile.pixels
	var size := Vector2(_pixel_size(viewport))
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
