shader_type spatial;
// Outdoor scans and props seen from both sides (outdoor_scan.gdshaderinc).
render_mode cull_disabled, depth_draw_opaque;

#include "res://src/render/outdoor_scan.gdshaderinc"
