# Brewery: sources and licences

The models (`brewery.glb`, `brewery_interior.glb`) are original work, modelled in Blender by `tools/pipeline/brewery/build.py` (utensils in `utensils.py`, on `craft.py`). Source: `assets/models/source/brewery/brewery.blend`.

The game's `brew_hands.glb` (the brewer's arms) is left out of this public copy: its hands come from a Sketchfab model whose licence forbids sharing the file. Here the arms are not drawn (`src/brewing/brew_arms.gd`).

The GLBs hold no images. Their surfaces name entries of the tavern's material table (`brewery.json`, key `materials`). Those entries use these scans, all CC0:

| Material | Scan | Address |
|---|---|---|
| `tav_board`, `tav_oak`, `tav_oak_end`, `tav_paint`, `tav_plank`, `tav_stem` | Poly Haven rough_wood | https://polyhaven.com/a/rough_wood |
| `tav_oak_smooth` | Poly Haven wood_table_worn | https://polyhaven.com/a/wood_table_worn |
| `tav_floor` | Poly Haven dark_wooden_planks | https://polyhaven.com/a/dark_wooden_planks |
| `tav_stone`, `tav_slate`, `tav_soil`, `tav_soot`, `brew_turf` | Poly Haven worn_rock_natural_01 | https://polyhaven.com/a/worn_rock_natural_01 |
| `tav_mortar`, `tav_clay`, `tav_candle`, `tav_foam`, `brew_mash`, `brew_cherry`, `brew_berry`, `brew_blossom` | Poly Haven rough_plaster_03 | https://polyhaven.com/a/rough_plaster_03 |
| `tav_limewash` | Poly Haven white_plaster_rough_01 | https://polyhaven.com/a/white_plaster_rough_01 |
| `tav_ceramic` | Poly Haven grey_plaster_03 | https://polyhaven.com/a/grey_plaster_03 |
| `tav_iron`, `tav_lead`, `tav_copper`, `tav_brass`, `brew_verdigris`, `brew_water`, `brew_wort` | Poly Haven rust_coarse_01 | https://polyhaven.com/a/rust_coarse_01 |
| `tav_bark`, `tav_herb`, `brew_beech_bark` | Poly Haven bark_brown_02 | https://polyhaven.com/a/bark_brown_02 |
| `tav_sack`, `tav_rope`, `tav_straw`, `brew_grain` | Poly Haven hessian_230 | https://polyhaven.com/a/hessian_230 |
| `tav_linen`, `tav_paper` | Poly Haven rough_linen | https://polyhaven.com/a/rough_linen |
| `tav_leather` | Poly Haven brown_leather | https://polyhaven.com/a/brown_leather |
| `brew_wicker` | Poly Haven wicker_basket_01 | https://polyhaven.com/a/wicker_basket_01 |
| `brew_juniper`, `brew_bark` | Poly Haven fir_tree_01 | https://polyhaven.com/a/fir_tree_01 |
| `brew_linden` | ambientCG LeafSet024 | https://ambientcg.com/a/LeafSet024 |

Poly Haven licence: https://polyhaven.com/license. ambientCG licence: https://docs.ambientcg.com/license/.

Three carried props use the scans as follows:

- Juniper bundle: twigs of fir_tree_01 with their needles and needle-spray cards. The needle picture is graded to juniper's grey blue-green (`brew_juniper_albedo.png`, `brew_juniper_normal.png`).
- Linden bunch: dead branches of fir_tree_01 as twigs. The bracts and leaves are LeafSet024 beech leaves, graded to dried straw (`brew_linden_albedo.png`).
- Cherry basket: willow rods modelled in Blender on strips of the wicker_basket_01 maps. The cherries are modelled in Blender. The heap under them is a picture that Blender renders from a modelled heap (`brew_cherries_albedo.png`, `brew_cherries_normal.png`, `brew_cherries_orm.png`).

The download lists are in `assets/external/polyhaven/SOURCES.json` and `assets/external/ambientcg/SOURCES.json`.
