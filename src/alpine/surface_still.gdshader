shader_type spatial;
render_mode cull_disabled;

// The map's surfaces that stand still. A material whose vertex function reads
// TIME is animated to the renderer even with a sway of zero, and a lamp draws
// its shadow map again in every frame an animated caster is in it.
#include "res://src/alpine/surface.gdshaderinc"

void vertex() {
	surface_position = VERTEX;
}
