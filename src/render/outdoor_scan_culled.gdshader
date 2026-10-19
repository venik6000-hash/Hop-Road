shader_type spatial;
// Outdoor props with closed shells, seen from the front only
// (outdoor_scan.gdshaderinc).
render_mode cull_back, depth_draw_opaque;

#include "res://src/render/outdoor_scan.gdshaderinc"
