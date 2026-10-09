shader_type spatial;
render_mode cull_disabled;

// The map's leaves: surface.gdshaderinc with a sway. The importer gives this
// shader to every surface of the map; the level moves those that do not sway
// to surface_still.gdshader (settle_map_surfaces in level.gd).
uniform float leaf_motion = 0.0;
#include "res://src/alpine/surface.gdshaderinc"

void vertex() {
	surface_position = VERTEX;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.x += sin(world.x * 0.9 + world.z * 0.6 + TIME * 1.2) * leaf_motion;
}
