#[compute]
#version 450
// Contact shadows in the tavern's rooms (TavernContactShadows): each pixel
// inside the building finds its place and its facing from the depth buffer,
// weighs the lamps of its room by the light each sends it, and walks a short
// ray on the screen toward the two shadow-casting lamps that weigh most. A
// lamp whose ray meets something loses its share of the pixel's light.
//
// Block of 312 floats (TavernContactShadows.PARAM_FLOATS).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform Params {
	mat4 inv_projection;  // NDC of the image (y down, as its rows run) -> view
	mat4 camera;          // view -> world
	mat4 to_clip;         // world -> clip of the image; w is the depth along the view, m
	vec4 size;            // xy: image size; view depth (m) = z / (raw depth + w)
	vec4 view;            // x: the metres a pixel spans a metre from the eye, y: frame noise 0..1
	vec4 ray;             // x: how far a ray is walked (m), y: how thick what is seen is taken to be (m),
	                      // z: the room's light without its lamps, w: the share of a hidden lamp's light taken
	vec4 scene;           // x: lamps, y: debug view
	vec4 bounds_min;      // the building, world space
	vec4 bounds_max;
	vec4 lamps[60];       // a lamp is five rows. xyz: where it is, w: where its light ends (m);
	                      // xyz: a spot's axis, w: the cosine of its cone's half angle (-2: no cone);
	                      // x: energy, y: decay with distance, z: decay toward the cone's rim, w: 1 when it casts shadows;
	                      // xyz: the low corner of the box it lights; xyz: the high corner
} p;
layout(rgba16f, set = 0, binding = 1) uniform restrict image2D color_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;

const int MAX_LAMPS = 12;
const int LAMP_ROWS = 5;
// Stops of a ray. They crowd toward its start, where the contact is.
const int STOPS = 8;
// Nearer the eye than this (m) nothing is shaded.
const float NEAREST = 0.15;
// A ray starts this many pixels' widths off the surface: half a pixel is what
// the depth read at a stop may be off by on a surface seen edge-on.
const float LIFT = 1.5;
// The depth of a stop must pass what is seen there by this share of itself.
const float SLACK = 0.001;
// A lamp that sends a pixel less than this share of its light is not walked to.
const float LEAST_SHARE = 0.04;
// A thing met in the last part of a ray shades less: from this share of the
// ray's length on, down to nothing at its end.
const float FADE_FROM = 0.6;

// Reversed depth of a perspective view to metres along the view.
float view_depth(float raw) {
	return p.size.z / (max(raw, 1e-6) + p.size.w);
}

float depth_at(vec2 uv) {
	return view_depth(textureLod(depth_texture, uv, 0.0).r);
}

// The world place of what is seen at `uv`, `depth` metres along the view. The
// ray is taken from the near plane, where the inverse projection is exact.
vec3 world_at(vec2 uv, float depth) {
	vec4 view_h = p.inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 view_dir = view_h.xyz / view_h.w;
	return (p.camera * vec4(view_dir * (depth / max(-view_dir.z, 1e-4)), 1.0)).xyz;
}

// The way the surface at `uv` faces, from its neighbours in the depth buffer:
// on each axis the neighbour that lies nearer in depth, so that an edge takes
// the surface it belongs to. Zero where none can be told.
vec3 facing_at(vec2 uv, vec3 here, float depth) {
	vec2 texel = 1.0 / p.size.xy;
	vec2 left_uv = uv - vec2(texel.x, 0.0);
	vec2 right_uv = uv + vec2(texel.x, 0.0);
	vec2 up_uv = uv - vec2(0.0, texel.y);
	vec2 down_uv = uv + vec2(0.0, texel.y);
	float left_depth = depth_at(left_uv);
	float right_depth = depth_at(right_uv);
	float up_depth = depth_at(up_uv);
	float down_depth = depth_at(down_uv);
	vec3 across = abs(left_depth - depth) < abs(right_depth - depth)
		? here - world_at(left_uv, left_depth) : world_at(right_uv, right_depth) - here;
	vec3 along = abs(up_depth - depth) < abs(down_depth - depth)
		? here - world_at(up_uv, up_depth) : world_at(down_uv, down_depth) - here;
	vec3 normal = cross(across, along);
	float length2 = dot(normal, normal);
	if (!(length2 > 1e-24)) {
		return vec3(0.0);
	}
	normal *= inversesqrt(length2);
	// Toward the eye.
	return dot(normal, here - p.camera[3].xyz) > 0.0 ? -normal : normal;
}

// The engine's falloff of a lamp's light with distance (get_omni_attenuation).
float omni_share(float away, float reach, float decay) {
	float edge = away / reach;
	edge *= edge;
	edge *= edge;
	edge = max(1.0 - edge, 0.0);
	return edge * edge * pow(max(away, 0.0001), -decay);
}

// What lamp `index` sends a white surface at `here` that faces along `normal`,
// shadows aside (TavernContactShadows.weight).
float lamp_weight(int index, vec3 here, vec3 normal) {
	int row = index * LAMP_ROWS;
	if (any(lessThan(here, p.lamps[row + 3].xyz)) || any(greaterThan(here, p.lamps[row + 4].xyz))) {
		return 0.0;
	}
	vec4 place = p.lamps[row];
	vec4 cone = p.lamps[row + 1];
	vec4 light = p.lamps[row + 2];
	vec3 to_lamp = place.xyz - here;
	float away = max(length(to_lamp), 0.0001);
	float facing = dot(normal, to_lamp) / away;
	if (facing <= 0.0) {
		return 0.0;
	}
	float share = omni_share(away, place.w, light.y);
	if (cone.w > -1.5) {
		float rim = max(0.0001, (1.0 - max(-dot(to_lamp, cone.xyz) / away, cone.w)) / (1.0 - cone.w));
		share *= 1.0 - pow(rim, light.z);
	}
	return light.x * share * facing;
}

// Interleaved gradient noise, a new pattern each frame for TAA to resolve.
float frame_noise(vec2 pixel) {
	pixel += p.view.y * vec2(47.0, 17.0) * 64.0;
	return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// How much of lamp `index` is hidden from `start` by what is seen on the
// screen within the ray's reach: 0 none .. 1 all.
float hidden_from(int index, vec3 start, float noise) {
	vec3 to_lamp = p.lamps[index * LAMP_ROWS].xyz - start;
	float away = length(to_lamp);
	// Not into the lamp itself: its flame and its candle stand there.
	float reach = min(p.ray.x, away * 0.9);
	if (reach <= 1e-4) {
		return 0.0;
	}
	vec3 toward = to_lamp / away;
	for (int stop = 0; stop < STOPS; stop++) {
		float part = (float(stop) + noise) / float(STOPS);
		float walked = reach * part * sqrt(part);
		vec4 clip = p.to_clip * vec4(start + toward * walked, 1.0);
		if (clip.w <= 1e-3) {
			break;
		}
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
			break;
		}
		// How far behind what is seen there the stop lies.
		float behind = clip.w - depth_at(uv);
		if (behind > clip.w * SLACK && behind < p.ray.y) {
			return 1.0 - smoothstep(FADE_FROM, 1.0, walked / p.ray.x);
		}
	}
	return 0.0;
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(p.size.x) || pixel.y >= int(p.size.y)) {
		return;
	}
	vec2 uv = (vec2(pixel) + 0.5) / p.size.xy;
	float raw = textureLod(depth_texture, uv, 0.0).r;
	// Reversed depth: 0 is the sky.
	if (raw <= 0.0) {
		return;
	}
	bool debug = p.scene.y > 0.5;
	float left = 1.0;
	float depth = view_depth(raw);
	vec3 here = world_at(uv, depth);
	bool indoors = depth >= NEAREST && all(greaterThan(here, p.bounds_min.xyz)) && all(lessThan(here, p.bounds_max.xyz));
	vec3 normal = indoors ? facing_at(uv, here, depth) : vec3(0.0);
	if (dot(normal, normal) > 0.5) {
		int count = min(int(p.scene.x + 0.5), MAX_LAMPS);
		float total = 0.0;
		float first = 0.0;
		float second = 0.0;
		int first_lamp = -1;
		int second_lamp = -1;
		for (int index = 0; index < count; index++) {
			float weight = lamp_weight(index, here, normal);
			total += weight;
			if (p.lamps[index * LAMP_ROWS + 2].w < 0.5) {
				continue;
			}
			if (weight > first) {
				second = first;
				second_lamp = first_lamp;
				first = weight;
				first_lamp = index;
			} else if (weight > second) {
				second = weight;
				second_lamp = index;
			}
		}
		float all_light = total + p.ray.z;
		float least = all_light * LEAST_SHARE;
		if (first_lamp >= 0 && first > least) {
			vec3 start = here + normal * (depth * p.view.x * LIFT);
			float noise = frame_noise(vec2(pixel));
			float hidden = first * hidden_from(first_lamp, start, noise);
			if (second_lamp >= 0 && second > least) {
				hidden += second * hidden_from(second_lamp, start, fract(noise + 0.5));
			}
			left = clamp(1.0 - p.ray.w * hidden / all_light, 0.0, 1.0);
		}
	}
	if (debug) {
		imageStore(color_image, pixel, vec4(vec3(left), 1.0));
	} else if (left < 1.0) {
		vec4 color = imageLoad(color_image, pixel);
		imageStore(color_image, pixel, vec4(color.rgb * left, color.a));
	}
}
