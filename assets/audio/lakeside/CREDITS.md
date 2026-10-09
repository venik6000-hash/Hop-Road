# Audio credits

Every sound in this folder is a real recording from [Freesound](https://freesound.org), released under
**Creative Commons 0** (public domain dedication: no attribution required; credited here anyway).
Nothing is synthesised.

The recordings were edited for the Tidewater project (excerpt, high-pass on some, trim, fades,
equal-power crossfade at the loop point, loudness normalisation) and published there as Opus sprites.
`tools/pipeline/lakeside/prepare_audio.py` downloads the sprites this game uses at the pinned commit,
checks their SHA-256 and cuts them into the mono WAV files below; `SOURCES.json` holds the links, the
hashes and the slice table, `bank.json` the list `LakeSoundscape` loads. A name ending in `_loop` is a
seamless loop, numbered files are one-shot variations.

| File | Use | Source | Author | Licence |
|---|---|---|---|---|
| `step_grass_0.wav` … `step_grass_4.wav` | 5 steps, grass | [Footsteps_Grass_1.wav](https://freesound.org/people/SilentStrikeZ/sounds/389625/) | SilentStrikeZ | CC0 1.0 |
| `step_rock_0.wav` … `step_rock_4.wav` | 5 steps, stone | [Footsteps - Stone, Rock, Concrete, Cement](https://freesound.org/people/SecureSubset/sounds/813622/) | SecureSubset | CC0 1.0 |
| `step_sand_0.wav` … `step_sand_4.wav` | 5 steps, soft loose dry sand (foley, no surf) | [Soft sand steps.wav](https://freesound.org/people/200221-WeanBekker/sounds/543714/) | 200221-WeanBekker | CC0 1.0 |
| `step_wood_0.wav` … `step_wood_4.wav` | 5 steps, hollow wood | [Footsteps on hollow wood](https://freesound.org/people/florianreichelt/sounds/459970/) | florianreichelt | CC0 1.0 |
| `step_water_0.wav` … `step_water_4.wav` | 5 wading swishes (slowest-attack picks) | [Footsteps_Walk.wav](https://freesound.org/people/Nox_Sound/sounds/490951/), [Wading in Shallow Water.wav](https://freesound.org/people/ryansitz/sounds/342932/) | Nox_Sound, ryansitz | CC0 1.0, CC0 1.0 |
| `swim_0.wav` … `swim_3.wav` | 4 surface swim strokes | [POOL SWIMMING R-L](https://freesound.org/people/tbsounddesigns/sounds/530158/) | tbsounddesigns | CC0 1.0 |
| `uw_swim_0.wav` … `uw_swim_3.wav` | 4 underwater hand/arm movements (hydrophone) | [Underwater recording of aquatic movement, bubbles and drops.](https://freesound.org/people/felix.blume/sounds/384218/) | felix.blume | CC0 1.0 |
| `submerge_0.wav` … `submerge_1.wav` | 2 short underwater water-rushes (hydrophone) | [Underwater recording of aquatic movement, bubbles and drops.](https://freesound.org/people/felix.blume/sounds/384218/) | felix.blume | CC0 1.0 |
| `emerge_0.wav` | water settling / dripping (short) | [Water Splash](https://freesound.org/people/felix.blume/sounds/434978/) | felix.blume | CC0 1.0 |
| `pier_lap_loop.wav` | water lapping a dock — loop | [WavesOnTheShore.wav](https://freesound.org/people/richardemoore/sounds/260263/) | richardemoore | CC0 1.0 |
| `boat_lap_loop.wav` | water lapping a fibreglass hull — loop | [boat knocks fiberglass water laps on hull.flac](https://freesound.org/people/kyles/sounds/637206/) | kyles | CC0 1.0 |
| `splash_0.wav` … `splash_3.wav` | 4 splashes (body into water) | [SPLASH (by blaukreuz)](https://freesound.org/people/qubodup/sounds/212143/), [Foley_Natural_Water_Jump_Mono.wav](https://freesound.org/people/Nox_Sound/sounds/585744/) | qubodup, Nox_Sound | CC0 1.0, CC0 1.0 |
| `plop_0.wav` … `plop_1.wav` | 2 bobber / sinker landings | [Fishing Lure-Sinker Hitting water](https://freesound.org/people/JoelMcDaniel/sounds/849752/), [fishingreel_throw.wav](https://freesound.org/people/BranndyBottle/sounds/464697/) | JoelMcDaniel, BranndyBottle | CC0 1.0, CC0 1.0 |
| `rod_swish_0.wav` … `rod_swish_4.wav` | 5 rod swishes (the cast) | [Fishing Rod Swish Swoosh.wav](https://freesound.org/people/Mrthenoronha/sounds/371313/), [Fishing Rod Cast - Swoosh](https://freesound.org/people/mwchristian95/sounds/725426/) | Mrthenoronha, mwchristian95 | CC0 1.0, CC0 1.0 |
| `reel_wind_loop.wav` | spinning reel cranked steadily (gear ticking) — loop, rate follows the crank | [Spinning reel.wav](https://freesound.org/people/tosha73/sounds/509902/) | tosha73 | CC0 1.0 |
| `fish_splash_0.wav` … `fish_splash_4.wav` | 5 fish splashes / thrashing at the surface | [Fish Splashing Release 1.wav](https://freesound.org/people/paulprit/sounds/507094/), [Fish Splashing Release 2.wav](https://freesound.org/people/paulprit/sounds/507093/) | paulprit | CC0 1.0 |
| `fish_flop_0.wav` … `fish_flop_3.wav` | landed fish flapping / flopping | [FishFlappingTail.wav](https://freesound.org/people/ramattahatta/sounds/649003/), [Fish Flopping.wav](https://freesound.org/people/RatBird/sounds/570208/) | ramattahatta, RatBird | CC0 1.0, CC0 1.0 |
| `bird_forest_0.wav` … `bird_forest_12.wav` | 13 songbird calls / short songs (high-passed 1.1 kHz); sung in bouts from perches in the trees | [Birds in Rainforest - Volcanoes National Park (Hawaii) 2](https://freesound.org/people/coalcon/sounds/636071/), [Birds in Rainforest - Volcanoes National Park (Hawaii) 1](https://freesound.org/people/coalcon/sounds/636072/), [Tropical Birds.wav](https://freesound.org/people/dubminister/sounds/214676/) | coalcon, coalcon, dubminister | CC0 1.0, CC0 1.0, CC0 1.0 |
| `bird_dove_0.wav` … `bird_dove_4.wav` | 5 dove coo phrases | [mourning_dove _2017-06-06.wav](https://freesound.org/people/nathankwright/sounds/456930/) | nathankwright | CC0 1.0 |
| `crickets_loop.wav` | night crickets — loop | [Night Crickets Back Porch.aiff](https://freesound.org/people/hdfreema/sounds/333221/) | hdfreema | CC0 1.0 |
| `wind_loop.wav` | coastal wind through bushes — loop, gust-modulated | [strong wind on coastal path.wav](https://freesound.org/people/bruno.auzet/sounds/706471/) | bruno.auzet | CC0 1.0 |

Note: one of the `splash` recordings is qubodup's cleaned edit of blaukreuz's "130723_Brela_HarborJump_F_4824.wav" (also CC0).
