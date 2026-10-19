// The lake's level, m: the region's terrain.json, which terrain_material.gd writes
// as the global. The lake's own shader (water.gdshader) keeps its uniform.
#ifndef LAKE_LEVEL_GDSHADERINC
#define LAKE_LEVEL_GDSHADERINC

global uniform float lake_level;

#endif
