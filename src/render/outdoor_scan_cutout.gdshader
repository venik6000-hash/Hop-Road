shader_type spatial;
// Outdoor cards cut out by their alpha, such as hay, seen from both sides
// (outdoor_scan.gdshaderinc).
render_mode cull_disabled, depth_draw_opaque;

#define OUTDOOR_CUTOUT
#include "res://src/render/outdoor_scan.gdshaderinc"
