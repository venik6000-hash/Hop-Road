#[compute]
#version 450
// Lays the fog of fog_volume.glsl over the HDR picture: each pixel looks the
// grid up at its own depth, with a dithered offset that TAA resolves (Bauer
// 2019), and takes the rainbow's light where sunlit drops lie on its way.
// Two things the grid does not hold are added here: the glow of the lamps
// that burn in the fog, and the fog that lies between the lake and what it
// mirrors.
//
// The import does not follow the include: after a change to the block in
// fog_params.glslinc this file must change too (or be imported again by
// hand), or it goes on reading the old layout. Block of 236 floats.
#include "fog_params.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 1) uniform restrict image2D color_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(set = 0, binding = 3) uniform sampler3D fog_volume;
layout(set = 0, binding = 4) uniform sampler3D bow_volume;
layout(set = 0, binding = 5) uniform sampler2D mirror_fog;

// The least distance (m) a ray is taken to pass a lamp at: its flame's size.
const float LAMP_CORE = 0.07;
// The light the lake sends up from its depth, against what it mirrors.
const float LAKE_BODY = 0.25;

// Violet (0) to red (1) through the colours between.
vec3 spectrum(float x) {
	float hue = (1.0 - clamp(x, 0.0, 1.0)) * 0.78;
	return clamp(abs(fract(hue + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

float band(float x) {
	return smoothstep(0.0, 0.2, x) * (1.0 - smoothstep(0.8, 1.0, x));
}

// The bows around the point opposite the sun: the primary at 40.6..42.4
// degrees with red outside, the fainter secondary at 50.4..53.6 with red
// inside, and the sky a little brighter within the primary.
vec3 rainbow(float cos_from_antisolar) {
	float angle = degrees(acos(clamp(cos_from_antisolar, -1.0, 1.0)));
	float first = (angle - 40.2) / 2.4;
	float second = (53.8 - angle) / 3.6;
	return spectrum(first) * band(first) + spectrum(second) * band(second) * 0.18
		+ vec3(0.05) * smoothstep(42.0, 37.0, angle);
}

// The glow of a lamp along the stretch t0..t1 of a ray that passes it `aside`
// metres away, `along` metres from the eye: its light falls off with the
// square of the distance, and this is the integral of 1 / d^2 over the stretch.
float lamp_glow(float along, float aside, float t0, float t1) {
	if (t1 <= t0) {
		return 0.0;
	}
	return (atan((t1 - along) / aside) - atan((t0 - along) / aside)) / aside;
}

// The light the fog around the lit lamps sends along a ray of `scene` metres:
// a halo round each. What stands before a lamp ends the ray and hides it.
vec3 lamp_halos(vec3 eye, vec3 dir, float scene) {
	vec3 glow = vec3(0.0);
	int count = min(int(p.lit.x + 0.5), MAX_LAMPS);
	for (int index = 0; index < count; index++) {
		vec4 place = p.lamps[index * 2];
		vec4 light = p.lamps[index * 2 + 1];
		vec3 to_lamp = place.xyz - eye;
		float along = dot(to_lamp, dir);
		float aside2 = dot(to_lamp, to_lamp) - along * along;
		float reach2 = light.a * light.a;
		if (aside2 >= reach2 || along < -light.a) {
			continue;
		}
		float aside = sqrt(max(aside2, LAMP_CORE * LAMP_CORE));
		// The ray's chord through the lamp's reach, as far as the scene.
		float half_chord = sqrt(reach2 - aside2);
		float t0 = max(along - half_chord, 0.0);
		float t1 = min(along + half_chord, scene);
		// Soft toward the edge of the reach, and dimmed by the fog on the way.
		float edge = 1.0 - aside2 / reach2;
		glow += light.rgb * (place.w * lamp_glow(along, aside, t0, t1) * edge * edge * exp(-place.w * max(along, 0.0)));
	}
	return glow;
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(p.size.x) || pixel.y >= int(p.size.y)) {
		return;
	}
	vec2 uv = (vec2(pixel) + 0.5) / p.size.xy;
	float raw = textureLod(depth_texture, uv, 0.0).r;
	// The ray from the near plane, where the inverse projection is exact; far
	// away its w runs out of bits.
	vec4 view_h = p.inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 view_dir = normalize(view_h.xyz / view_h.w);
	vec3 eye = p.camera[3].xyz;
	vec3 dir = normalize(mat3(p.camera) * view_dir);
	// Reversed depth, 1 at the near plane; 0 is the sky, with all the fog
	// there is before it.
	float scene = p.range.y;
	if (raw > 0.0) {
		scene = min(p.size.z / (raw + p.size.w) / max(-view_dir.z, 1e-4), p.range.y);
	}
	// The fog ends on the lake's surface, not on its bed. `mirror` is the share
	// of the pixel that is the lake's mirror, 0 where it shows something else.
	float mirror = 0.0;
	if (dir.y < -1e-5 && eye.y > p.sun.w) {
		float surface = (eye.y - p.sun.w) / -dir.y;
		// What the pixel shows is the lake while it lies no higher than its waves.
		if (surface < p.range.y && eye.y + dir.y * scene < p.sun.w + p.lit.z) {
			// Schlick for water; waves tilt toward the eye and keep a level
			// look from mirroring everything.
			float fresnel = 0.02 + 0.98 * pow(1.0 - max(-dir.y, 0.1), 5.0);
			mirror = fresnel / (fresnel + (1.0 - fresnel) * LAKE_BODY) * p.lit.y;
		}
		scene = min(scene, surface);
	}

	vec3 cells = vec3(textureSize(fog_volume, 0));
	float along = slice_of(scene);
	vec2 dither = vec2(frame_noise(vec2(pixel)), frame_noise(vec2(pixel.yx) + 19.0)) - 0.5;
	vec3 at = vec3(uv + dither / cells.xy, (max(along, 1.0) - 0.5) / cells.z);
	vec4 fog = mix(vec4(0.0, 0.0, 0.0, 1.0), textureLod(fog_volume, at, 0.0), min(along, 1.0));

	vec4 color = imageLoad(color_image, pixel);
	vec3 result = color.rgb;
	if (mirror > 0.0) {
		// What the lake mirrors comes through the fog beyond it, and that fog's
		// own light is mirrored with it.
		vec4 beyond = textureLod(mirror_fog, uv + dither / cells.xy, 0.0);
		float fresnel = 0.02 + 0.98 * pow(1.0 - max(-dir.y, 0.1), 5.0);
		result = result * (1.0 - mirror * (1.0 - beyond.a)) + beyond.rgb * fresnel;
	}
	result = result * fog.a + fog.rgb + lamp_halos(eye, dir, scene);
	if (p.rain.w > 0.0) {
		float drops = textureLod(bow_volume, at, 0.0).r * min(along, 1.0);
		result += p.sun_light.rgb * p.haze.w * (1.0 - exp(-drops)) * rainbow(-dot(dir, p.sun.xyz));
	}
	int debug = int(p.room_max.w + 0.5);
	if (debug == 1) {
		result = vec3(fog.a);
	} else if (debug == 2) {
		result = fog.rgb;
	} else if (debug == 3) {
		result = vec3(along / cells.z, fract(along), scene / p.range.y);
	} else if (debug == 4) {
		result = vec3(textureLod(bow_volume, at, 0.0).r);
	}
	imageStore(color_image, pixel, vec4(result, color.a));
}
