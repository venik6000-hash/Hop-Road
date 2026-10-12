// The colours of a sward, shared by the grass's cards (grass.gdshader) and by
// the ground they stand on (terrain.gdshader): where the cards thin out with
// distance the ground carries the meadow's colours on, and between a poor
// sward's tussocks it is the same dry turf.
//
// A sward's tone runs 0..1 (b of a clump's custom data, GrassScatter). Its
// first half is the green of growth, from old and deep to young and sunlit;
// its second half dries the grass on the stalk: it keeps its light and takes
// the colour of straw. grass_tile_job.gd says where which tone grows.
//
// The uniforms are each material's own: to try other colours, set them on the
// grass's material and on the terrain's alike.

// The tints of old growth and of young.
uniform vec3 sward_deep = vec3(0.84, 0.94, 0.86);
uniform vec3 sward_fresh = vec3(1.1, 1.06, 0.9);
// Straw, as a tint of the plant's own light, and how far the driest sward
// goes over to it.
uniform vec3 sward_straw = vec3(1.45, 1.1, 0.3);
uniform float sward_driest : hint_range(0.0, 1.0) = 0.75;
// The tone of a plain sward (GrassTileJob.PLAIN_TONE): the ground's scans are
// graded to it.
const float SWARD_PLAIN = 0.45;

// The tint of the green of a sward of this tone.
vec3 sward_tint(float tone) {
	return mix(sward_deep, sward_fresh, clamp(tone * 2.0, 0.0, 1.0));
}

// 0..sward_driest, how far a sward of this tone has dried.
float sward_dried(float tone) {
	return clamp(tone * 2.0 - 1.0, 0.0, 1.0) * sward_driest;
}

// A plant's colour, `share` of the way to straw of the same light.
vec3 dried_grass(vec3 green, float share) {
	return mix(green, dot(green, vec3(0.2126, 0.7152, 0.0722)) * sward_straw, share);
}
