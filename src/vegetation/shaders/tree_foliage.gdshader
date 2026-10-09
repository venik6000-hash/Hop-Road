shader_type spatial;
// Needle and leaf cards of the tree mesh LODs; see tree.gdshaderinc.
render_mode cull_disabled, depth_draw_opaque;

#define FOLIAGE
#include "res://src/vegetation/shaders/tree.gdshaderinc"
