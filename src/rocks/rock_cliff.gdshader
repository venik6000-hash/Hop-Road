shader_type spatial;
// The faces of the waterfall cliff (RockField.CLIFF_FACES): scans of a rock
// wall, shells open at the back. Drawn from both sides, so that an eye that
// gets behind a flake of one sees rock, not through it.
render_mode cull_disabled, depth_draw_opaque;

#include "res://src/rocks/rock.gdshaderinc"
