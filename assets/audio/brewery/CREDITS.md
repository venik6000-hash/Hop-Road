# Audio credits

Every sound in this folder is a real recording from [Freesound](https://freesound.org), released under
**Creative Commons 0** (public domain dedication: no attribution required; credited here anyway).
Nothing is synthesised. The licence was read on each sound's own page.

`tools/pipeline/brewery/prepare_audio.py` downloads the Freesound HQ previews named in `SOURCES.json`,
checks their SHA-256 and cuts them into the mono WAV files below (excerpt, fades, normalisation; a
loop crossfades its end into its start). `SOURCES.json` holds the links, the hashes and the slices.
A name ending in `_loop` is a seamless loop, numbered files are one-shot variations. `BrewSounds`
plays them.

| File | Use | Source | Author | Licence |
|---|---|---|---|---|
| `pour_loop.wav` | water running from a tap or a bucket into a vessel — loop | [R27-10-Water Pours into Tub.wav](https://freesound.org/people/craigsmith/sounds/480850/) | craigsmith | CC0 1.0 |
| `grain_loop.wav` | grain poured from a sack — loop | [Rice Pour](https://freesound.org/people/thedapperdan/sounds/199930/) | thedapperdan | CC0 1.0 |
| `boil_loop.wav` | the copper boiling — loop | [Boiling Pot.wav](https://freesound.org/people/Uzbazur/sounds/370933/) | Uzbazur | CC0 1.0 |
| `pump_0.wav` … `pump_3.wav` | pump strokes, the liquor pump and the wort pump | [Old hand pump](https://freesound.org/people/AudioPapkin/sounds/815126/) | AudioPapkin | CC0 1.0 |
| `tap_0.wav` … `tap_2.wav` | a tap key or a cock turned | [Squeak Rusty Metal Water Tap](https://freesound.org/people/brunoboselli/sounds/441096/) | brunoboselli | CC0 1.0 |
| `clank_0.wav` … `clank_3.wav` | the copper's hatch, the dampers | [stove antique iron in log cabin open close little door creak latch metal hatch various.flac](https://freesound.org/people/kyles/sounds/635748/) | kyles | CC0 1.0 |
| `stir_loop.wav` | the paddle in the mash or the copper — loop | [Stirring with Wooden Spoon and Wet Smacking](https://freesound.org/people/fordps3/sounds/336697/) | fordps3 | CC0 1.0 |
| `windlass_loop.wav` | the windlass wound — loop, rate follows the crank | [Wooden Crank, Handle with rope, winding.wav](https://freesound.org/people/aUREa/sounds/491705/) | aUREa | CC0 1.0 |
| `quern_loop.wav` | the quern turned — loop (high-passed 150 Hz against the mill's motor hum) | [FX_Mill_stone_corn_grain_Arilje_circular_mouvement_slow.wav](https://freesound.org/people/PLukx/sounds/430589/) | PLukx | CC0 1.0 |
| `scrape_0.wav` … `scrape_4.wav` | a shovel or a rake through grain, a skimmer pass | [Gravels lifting with a Shovel](https://freesound.org/people/Zeinel-2-and-Hope-sounds-3/sounds/787858/) | Zeinel-2-and-Hope-sounds-3 | CC0 1.0 |
| `knock_0.wav` … `knock_2.wav` | the mallet on a bung | [Wooden-Barrel_One-Hit_5](https://freesound.org/people/cwmcnutt/sounds/520146/) | cwmcnutt | CC0 1.0 |
| `log_0.wav` … `log_2.wav` | a log thrown into the firebox or the kiln | [Wood Burning Stove](https://freesound.org/people/richwise/sounds/455132/) | richwise | CC0 1.0 |
| `rustle_0.wav` | hops or linden flowers thrown into the copper | [29 Tirar Hojas.wav](https://freesound.org/people/checholio/sounds/443633/) | checholio | CC0 1.0 |
| `fire_loop.wav` | the fire under the copper and in the kiln — loop | [Wood burning stove fire](https://freesound.org/people/snds_good/sounds/554855/) | snds_good | CC0 1.0 |
