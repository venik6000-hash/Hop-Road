class_name QualityShadows
extends QualityGroup
## The shadows' share of a QualityProfile: the sun's cascades (SkySystem.
## apply_shadows) and the lamps' shadow atlas. All of the sun's take effect
## at once.

## Reach of the sun's shadow cascades, m (outdoors; an eye in a room takes
## less, WorldContext.set_shadow_reach).
@export var distance := 160.0
## The sun's shadow atlas, px.
@export var size := 4096
@export var blend := true
## Where the first three of the four cascades end, as shares of the reach:
## the nearest cascade holds the most texels per metre.
@export var splits := Vector3(0.06, 0.18, 0.45)
## The share of the reach at which the shadow starts to fade out.
@export var fade_start := 0.85
## Depth and normal bias of the sun's and the moon's shadow.
@export var bias := 0.03
@export var normal_bias := 1.2
## The lamps' shadow atlas, px, and the subdivision of each of its four
## quadrants (Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_*; 4 is 64 maps). They
## cost about 96 MB on every profile and stay so: a smaller atlas or quadrants
## divided unlike redraw every lamp's shadow in every frame after the first
## swing of a door (Godot 4.7.2; docs/PERFORMANCE.md, rule 4). The engine
## reads them from project.godot when it starts; tests/test_shadow_atlas.gd
## checks that every level holds the same numbers.
@export var lamp_atlas := 8192
@export var lamp_atlas_subdiv := 4
