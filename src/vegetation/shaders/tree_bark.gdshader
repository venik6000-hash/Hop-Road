shader_type spatial;
// Trunks and branches of the tree mesh LODs; see tree.gdshaderinc.
render_mode cull_back, depth_draw_opaque;

#define BARK
#include "res://src/vegetation/shaders/tree.gdshaderinc"
