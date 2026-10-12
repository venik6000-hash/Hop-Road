class_name RealismEnvironment
extends RefCounted
## One place for the look: ACES filmic tonemapping, ambient occlusion, bloom and
## aerial perspective fog driven by the physical sky. Used by the playable
## level and by every lookdev probe so both render the same picture.

## The share of the sky's light that falls into the shade (0..1). With all of
## it the shadows of an open day stood pale and the picture flat; with none the
## sun alone lit the land and the shade was black: nothing could be made out
## in it by day, and under a closed sky, whose light is all the sky's, the land
## was close to black. This much leaves the shade deep and what stands in it
## to be seen.
const SKY_FILL := 0.3

static func build(sky: Sky) -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color.BLACK
	environment.ambient_light_sky_contribution = SKY_FILL
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.92
	environment.tonemap_white = 8.0

	environment.ssao_enabled = true
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 1.6
	environment.ssao_power = 1.4
	environment.ssao_detail = 0.6
	environment.ssao_horizon = 0.06
	environment.ssao_sharpness = 0.96
	environment.ssao_light_affect = 0.12
	environment.ssao_ao_channel_affect = 0.4

	environment.glow_enabled = true
	environment.glow_normalized = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.012
	environment.glow_hdr_threshold = 1.4
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.set_glow_level(0, 0.0)
	environment.set_glow_level(1, 0.6)
	environment.set_glow_level(2, 0.9)
	environment.set_glow_level(3, 0.7)
	environment.set_glow_level(4, 0.4)

	# Aerial perspective: distant slopes take the colour of the sky behind
	# them, as air does over kilometres.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.00005
	environment.fog_aerial_perspective = 1.0
	environment.fog_sky_affect = 0.0
	environment.fog_light_color = Color(0.62, 0.72, 0.86)
	environment.fog_sun_scatter = 0.12
	environment.fog_height = 380.0
	environment.fog_height_density = 0.0001

	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06
	environment.adjustment_contrast = 1.02
	return environment
