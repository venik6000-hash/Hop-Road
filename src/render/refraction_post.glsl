#[compute]
#version 450
// Bends the finished picture where light is bent on its way to the eye and
// no material can say so (RefractionPost):
//  - the hot air over a fire, which shows what is behind it shimmering;
//  - the rings rain drops leave on the lake, which tilt its mirror. The lake's
//    own shader is not touched: a tilted patch of a level lake shows what the
//    level lake shows a few pixels away, with another share of mirror and
//    depth, and both are taken from the picture. Each drop also throws up a
//    speck of spray; and where the rings are too small for a pixel, far out,
//    they only blur the mirror.
// `job` 0 writes the bent picture of a rectangle into a scratch image, 1
// copies the rectangle back: a pass cannot read its neighbours' pixels from
// the image it writes.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform Params {
	mat4 inv_projection;  // NDC of the image (y down, as its rows run) -> view
	mat4 projection;      // view -> NDC of the image
	mat4 camera;          // view -> world
	vec4 size;            // xy: image size; view depth (m) = z / (raw depth + w)
	vec4 rain;            // x: share of the drops that fall 0..1, y: the rings' clock (s), z: lake level (m), w: how far the rings are drawn (m)
	vec4 air;             // x: the shimmer's clock (s), y: fires, z: how high the lake's waves reach (m), w: frame noise 0..1
	vec4 tune;            // x: debug view
	vec4 fires[16];       // a fire is two rows. xyz: the foot of its column of hot air (m), w: its radius there (m);
	                      // x: the column's height (m), y: its strength
} p;
layout(set = 0, binding = 1) uniform sampler2D source;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D target;

layout(push_constant, std430) uniform Job {
	ivec4 rect;  // x, y of the rectangle's corner, its width and height (pixels)
	ivec4 what;  // x: the job, y: 1 with the fires' air, z: 1 with the rain's rings
} job;

const int MAX_FIRES = 8;
// The angle (radians) the hottest air swings what is far behind it by.
const float SHIMMER = 0.0055;
// The light the lake sends up from its depth, against what it mirrors.
const float LAKE_BODY = 0.25;
// The farthest (in the picture's heights) a ring may fetch its mirror from.
const float RING_FETCH = 0.014;
// A ring's wave is 9 cm long: a pixel that covers more of the lake than the
// second number (m, along the view) cannot draw it, one under the first can.
const vec2 RING_PIXEL = vec2(0.02, 0.045);
// Pixels the unseen rings blur the mirror by.
const float RING_BLUR = 1.6;
// The spray a drop throws up: its radius (m), the share of a turn it lasts,
// and its light against the sky the lake mirrors.
const float SPRAY_RADIUS = 0.03;
const float SPRAY_LIFE = 0.14;
const float SPRAY_LIGHT = 0.5;

float hash(vec2 at) {
	vec3 q = fract(vec3(at.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec3 hash3(vec2 at) {
	vec3 q = fract(vec3(at.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yxx) * q.zyx);
}

float value_noise(vec2 at) {
	vec2 cell = floor(at);
	vec2 f = fract(at);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

// Metres to what the picture shows at `uv`, along that pixel's own ray.
float scene_distance(vec2 uv, out vec3 dir) {
	vec4 view_h = p.inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 view_dir = normalize(view_h.xyz / view_h.w);
	dir = normalize(mat3(p.camera) * view_dir);
	float raw = textureLod(depth_texture, uv, 0.0).r;
	// Reversed depth: 0 is the sky.
	return raw > 0.0 ? p.size.z / (raw + p.size.w) / max(-view_dir.z, 1e-4) : 1e9;
}

// Where in the picture the eye looks along `dir` (world space).
vec2 uv_along(vec3 dir) {
	vec4 clip = p.projection * vec4(transpose(mat3(p.camera)) * dir, 0.0);
	// Behind the eye: nowhere in the picture.
	if (clip.w <= 1e-5) {
		return vec2(-10.0);
	}
	return clip.xy / clip.w * 0.5 + 0.5;
}

// Interleaved gradient noise, a new pattern each frame for TAA to resolve.
float frame_noise(vec2 pixel) {
	pixel += p.air.w * vec2(47.0, 17.0) * 64.0;
	return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// The slopes (dh/dx, dh/dz) of the rings the drops leave on still water at
// `xz`: each cell of two grids takes a drop now and then, and its ring runs
// out and dies in about a second. The puddles' rings are the same
// (src/weather/wetness.gdshaderinc: rain_rings). `spray` is how much of the
// point the spray of a drop that has just landed covers; `speck` is the
// least radius (m) a speck is drawn with, its light thinned to match.
vec2 rain_rings(vec2 xz, float speck, out float spray) {
	vec2 slope = vec2(0.0);
	spray = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float size = layer == 0 ? 0.45 : 0.75;
		float period = layer == 0 ? 0.9 : 1.2;
		vec2 grid = xz / size + float(layer) * 17.3;
		vec2 cell = floor(grid);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 here = cell + vec2(float(i), float(j));
				vec3 chance = hash3(here);
				float turn = p.rain.y / period + chance.z;
				float age = fract(turn);
				// A new place, and a new chance to fall at all, each turn.
				vec3 drop = hash3(here + floor(turn) * 7.13);
				if (drop.z > p.rain.x) {
					continue;
				}
				vec2 from = grid - (here + 0.2 + drop.xy * 0.6);
				float away = length(from) * size;
				float offset = away - age * size * 0.7;
				float fade = (1.0 - age) * (1.0 - age);
				slope += from / max(length(from), 1e-4) * sin(offset * 70.0) * exp(-offset * offset * 260.0) * fade;
				if (age < SPRAY_LIFE) {
					float radius = max(SPRAY_RADIUS, speck);
					float thin = SPRAY_RADIUS / radius;
					spray += (1.0 - smoothstep(0.5 * radius, radius, away)) * (1.0 - age / SPRAY_LIFE) * thin * thin;
				}
			}
		}
	}
	return slope * 0.3;
}

float water_fresnel(float cosine) {
	return 0.02 + 0.98 * pow(1.0 - clamp(cosine, 0.0, 1.0), 5.0);
}

// How far (in uv) the hot air over the fires moves what the pixel at `uv`
// shows, looking along `dir` at a scene `scene` metres away.
vec2 air_shift(vec3 eye, vec3 dir, float scene, out float front) {
	vec2 shift = vec2(0.0);
	front = 0.0;
	int count = min(int(p.air.y + 0.5), MAX_FIRES);
	vec3 right = normalize(p.camera[0].xyz);
	for (int index = 0; index < count; index++) {
		vec4 foot = p.fires[index * 2];
		vec4 column = p.fires[index * 2 + 1];
		// Where the ray passes the column's upright axis nearest.
		vec3 from = eye - foot.xyz;
		float lean = dir.y;
		float along = dot(dir, from);
		float apart = 1.0 - lean * lean;
		if (apart < 1e-4) {
			continue;
		}
		float t = (lean * from.y - along) / apart;
		float rise = (from.y - lean * along) / apart;
		if (t <= 0.05 || rise < 0.0 || rise > column.x) {
			continue;
		}
		vec3 across = eye + dir * t - (foot.xyz + vec3(0.0, rise, 0.0));
		float up = rise / column.x;
		// The column widens as it rises and cools.
		float width = foot.w * (1.0 + 1.3 * up);
		float aside = length(across) / width;
		if (aside >= 1.0) {
			continue;
		}
		float body = 1.0 - aside * aside;
		// Hidden by what stands before it; a wall close behind it hardly moves.
		float seen = clamp((scene - (t - width)) / (2.0 * width), 0.0, 1.0);
		float behind = mix(0.35, 1.0, clamp((scene - t) / 4.0, 0.0, 1.0));
		float amount = column.y * body * body * smoothstep(0.0, 0.1, up) * pow(1.0 - up, 1.3) * seen * behind;
		if (amount <= 0.0) {
			continue;
		}
		// Cells of hot air drift up through the column, small ones faster.
		vec2 cell = vec2(dot(across, right) * 7.0 + float(index) * 13.0, rise * 5.0 - p.air.x * 2.6);
		vec2 swing = vec2(value_noise(cell) + 0.5 * value_noise(cell * 2.3 + vec2(7.1, -p.air.x * 1.9)),
			value_noise(cell + 31.7) + 0.5 * value_noise(cell * 2.3 + vec2(-11.3, -p.air.x * 1.9))) / 1.5 - 0.5;
		shift += swing * amount * SHIMMER * 0.5 * vec2(p.projection[0][0], abs(p.projection[1][1]));
		front = max(front, t - width);
	}
	return shift;
}

void main() {
	ivec2 pixel = job.rect.xy + ivec2(gl_GlobalInvocationID.xy);
	if (gl_GlobalInvocationID.x >= uint(job.rect.z) || gl_GlobalInvocationID.y >= uint(job.rect.w)) {
		return;
	}
	if (job.what.x == 1) {
		imageStore(target, pixel, texelFetch(source, pixel, 0));
		return;
	}
	vec2 uv = (vec2(pixel) + 0.5) / p.size.xy;
	vec3 eye = p.camera[3].xyz;
	vec3 dir;
	float scene = scene_distance(uv, dir);
	vec4 color = texelFetch(source, pixel, 0);

	if (job.what.y == 1) {
		float front;
		vec2 shift = air_shift(eye, dir, scene, front);
		if (shift != vec2(0.0)) {
			// Not what stands before the hot air.
			vec3 there;
			if (scene_distance(uv + shift, there) > front) {
				color.rgb = textureLod(source, uv + shift, 0.0).rgb;
			}
			if (p.tune.x > 0.5) {
				// How far the air moves the picture, in pixels: red across, green up and down.
				color.rgb = vec3(abs(shift) * p.size.xy * 0.5, 0.0);
			}
		}
	}

	float level = p.rain.z;
	float waves = p.air.z;
	if (job.what.z == 1 && dir.y < -1e-4 && eye.y > level) {
		float surface = (eye.y - level) / -dir.y;
		float seen_at = eye.y + dir.y * scene;
		if (surface < p.rain.w && seen_at < level + waves) {
			// The lake's surface is in the depth; under it lies the bed.
			float lake = seen_at > level - waves ? scene : surface;
			float fade = 1.0 - smoothstep(0.6 * p.rain.w, p.rain.w, surface);
			// What a pixel covers of the lake along the view, m.
			float covers = surface * surface / (0.5 * p.size.y * abs(p.projection[1][1]) * (eye.y - level));
			float sharp = 1.0 - smoothstep(RING_PIXEL.x, RING_PIXEL.y, covers);
			float spray;
			vec2 slope = rain_rings(eye.xz + dir.xz * lake, 0.7 * covers, spray) * sharp * fade;
			vec3 normal = normalize(vec3(-slope.x, 1.0, -slope.y));
			// The level lake shows the tilted patch's mirror image at the pixel
			// that looks along the mirrored ray, turned down again.
			vec3 mirrored = reflect(dir, normal);
			vec2 fetch = uv_along(vec3(mirrored.x, -mirrored.y, mirrored.z)) - uv;
			fetch *= min(1.0, RING_FETCH / max(length(fetch), 1e-6));
			// Rings too small to draw only roughen the mirror.
			fetch += (vec2(frame_noise(vec2(pixel)), frame_noise(vec2(pixel.yx) + 19.0)) - 0.5) * 2.0 * RING_BLUR / p.size.xy
				* p.rain.x * (1.0 - sharp) * fade;
			if (fetch != vec2(0.0)) {
				vec3 there;
				float beyond = scene_distance(uv + fetch, there);
				if (there.y < 0.0 && eye.y + there.y * beyond < level + waves) {
					color.rgb = textureLod(source, uv + fetch, 0.0).rgb;
				}
			}
			// A patch tilted toward the eye mirrors less and shows more of the
			// dark water; one tilted away mirrors more.
			float flat_share = water_fresnel(max(-dir.y, 0.1));
			float lit = flat_share + LAKE_BODY * (1.0 - flat_share);
			float tilted = water_fresnel(max(dot(-dir, normal), 0.1));
			color.rgb *= max(1.0 + (tilted - flat_share) * (1.0 - LAKE_BODY) / lit, 0.0);
			// The spray is lit by the sky the lake mirrors.
			color.rgb += color.rgb * (min(spray, 1.0) * fade * SPRAY_LIGHT / lit);
			if (p.tune.x > 0.5) {
				// Blue the rings' slope, green the spray, red the pixels fetched from.
				color.rgb = vec3(length(fetch * p.size.xy) * 0.25, min(spray, 1.0), length(slope) * 4.0);
			}
		}
	}
	imageStore(target, pixel, color);
}
