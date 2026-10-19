// The moss of the region's buildings, trees and stones: its terrain's layer
// array (terrain_albedo.jpg of RegionDef.terrain_dir), whose mossy rock scan
// they lay on (`moss_layer`). TerrainMaterial writes the global once.
#ifndef MOSS_GDSHADERINC
#define MOSS_GDSHADERINC

global uniform sampler2DArray moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

#endif
