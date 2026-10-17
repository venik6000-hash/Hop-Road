class_name BrewIds
extends RefCounted
## The names the brewing's code and data share: the sorts of beer, the stages
## of a batch, the notes of a profile, the flaws, the wares, the sacks and the
## kinds of grain.
## assets/brewing/*.json name them too; DataFiles checks both sides against
## each other, so a name that is new stands here and in the data, or nowhere.

# ---- Sorts of beer (recipes.json, trade.json) ---------------------------------

const SORT_TABLE_PALE := &"table_pale"
const SORT_CREAM := &"cream"
const SORT_CARAMEL := &"caramel"
const SORT_SMOKED := &"smoked"
const SORT_JUNIPER := &"juniper"
const SORT_LINDEN_HONEY := &"linden_honey"
const SORT_CHERRY_DARK := &"cherry_dark"
## What a batch is called that fits no recipe, and one that is ruined.
const SORT_NAMELESS := &"nameless"
const SORT_SPOILED := &"spoiled"
const SORTS: Array[StringName] = [SORT_TABLE_PALE, SORT_CREAM, SORT_CARAMEL, SORT_SMOKED, SORT_JUNIPER, SORT_LINDEN_HONEY,
	SORT_CHERRY_DARK, SORT_NAMELESS, SORT_SPOILED]

# ---- Stages of a batch (BrewBatch.stage), in their order ----------------------

const STAGE_NEW := &"new"
const STAGE_MASH := &"mash"
const STAGE_WORT := &"wort"
const STAGE_BOIL := &"boil"
const STAGE_COOLED := &"cooled"
const STAGE_PITCHED := &"pitched"
const STAGE_BARREL := &"barrel"
const STAGES: Array[StringName] = [STAGE_NEW, STAGE_MASH, STAGE_WORT, STAGE_BOIL, STAGE_COOLED, STAGE_PITCHED, STAGE_BARREL]

# ---- Notes of a profile (BrewTaste.profile) -----------------------------------

const NOTE_HOPS := &"hops"
const NOTE_OATS := &"oats"
const NOTE_CARAMEL := &"caramel"
const NOTE_SMOKE := &"smoke"
const NOTE_JUNIPER := &"juniper"
const NOTE_HONEY := &"honey"
const NOTE_LINDEN := &"linden"
const NOTE_CHERRY := &"cherry"
const NOTES: Array[StringName] = [NOTE_HOPS, NOTE_OATS, NOTE_CARAMEL, NOTE_SMOKE, NOTE_JUNIPER, NOTE_HONEY, NOTE_LINDEN,
	NOTE_CHERRY]

# ---- Flaws (flaws.json); those of RUINS spoil a batch --------------------------

const FLAW_SLEEPY_GRAIN := &"sleepy_grain"
const FLAW_MOULD := &"mould"
const FLAW_OVERGROWN := &"overgrown"
const FLAW_DAMP_MALT := &"damp_malt"
const FLAW_BURNT := &"burnt"
const FLAW_ACRID_SMOKE := &"acrid_smoke"
const FLAW_FLOUR := &"flour"
const FLAW_COARSE_GRIND := &"coarse_grind"
const FLAW_THIN := &"thin"
const FLAW_WATERY := &"watery"
const FLAW_CLUMPS := &"clumps"
const FLAW_MURKY := &"murky"
const FLAW_BOILOVER := &"boilover"
const FLAW_SCORCHED := &"scorched"
const FLAW_SOUR_WORT := &"sour_wort"
const FLAW_DEAD_YEAST := &"dead_yeast"
const FLAW_WARM_FERMENT := &"warm_ferment"
const FLAW_MUDDY_HEAD := &"muddy_head"
const FLAW_SOUR_BARREL := &"sour_barrel"
const FLAW_GREEN := &"green"
const FLAWS: Array[StringName] = [FLAW_SLEEPY_GRAIN, FLAW_MOULD, FLAW_OVERGROWN, FLAW_DAMP_MALT, FLAW_BURNT, FLAW_ACRID_SMOKE,
	FLAW_FLOUR, FLAW_COARSE_GRIND, FLAW_THIN, FLAW_WATERY, FLAW_CLUMPS, FLAW_MURKY, FLAW_BOILOVER, FLAW_SCORCHED,
	FLAW_SOUR_WORT, FLAW_DEAD_YEAST, FLAW_WARM_FERMENT, FLAW_MUDDY_HEAD, FLAW_SOUR_BARREL, FLAW_GREEN]
const RUINS: Array[StringName] = [FLAW_DEAD_YEAST, FLAW_SOUR_BARREL]

# ---- Wares of the stalls (trade.json) -----------------------------------------

const WARE_BARLEY_SACK := &"barley_sack"
const WARE_OATS_SACK := &"oats_sack"
const WARE_PALE_MALT_SACK := &"pale_malt_sack"
const WARE_HOPS := &"hops"
const WARE_KEG := &"keg"
const WARE_MEND_TUN_2 := &"mend_tun_2"
const WARE_MEND_CASK_3 := &"mend_cask_3"
const WARE_MEND_CASK_4 := &"mend_cask_4"
const WARE_YEAST := &"yeast"
const WARE_LOGS := &"logs"
const WARE_BEECH_LOGS := &"beech_logs"
const WARE_FINE_THERMOMETER := &"fine_thermometer"
const WARE_FULL_WEIGHTS := &"full_weights"
const WARE_HONEY := &"honey"
const WARE_LINDEN := &"linden"
const WARE_JUNIPER := &"juniper"
const WARE_CHERRIES := &"cherries"
const WARES: Array[StringName] = [WARE_BARLEY_SACK, WARE_OATS_SACK, WARE_PALE_MALT_SACK, WARE_HOPS, WARE_KEG, WARE_MEND_TUN_2,
	WARE_MEND_CASK_3, WARE_MEND_CASK_4, WARE_YEAST, WARE_LOGS, WARE_BEECH_LOGS, WARE_FINE_THERMOMETER, WARE_FULL_WEIGHTS,
	WARE_HONEY, WARE_LINDEN, WARE_JUNIPER, WARE_CHERRIES]

# ---- Sacks (utensils of brewery.json) -----------------------------------------

const SACK_PALE_MALT := &"pale_malt_sack"
const SACK_CARAMEL_MALT := &"caramel_malt_sack"
const SACK_OATS := &"oats_sack"
const SACK_DARK := &"dark_sack"
const SACK_SMOKED := &"smoked_sack"
## Sacks of malt and oats, which the mash tun takes (BrewDay.SACKS).
const SACKS: Array[StringName] = [SACK_PALE_MALT, SACK_CARAMEL_MALT, SACK_OATS, SACK_DARK, SACK_SMOKED]
## The sacks of barley the maltings steep (BrewMaltings).
const BARLEY_SACKS: Array[StringName] = [&"barley_sack_1", &"barley_sack_2", &"barley_sack_3"]
## Every sack whose grain the mash tun takes.
const GRIST_SACKS: Array[StringName] = [SACK_PALE_MALT, SACK_CARAMEL_MALT, SACK_OATS, SACK_DARK, SACK_SMOKED,
	&"barley_sack_1", &"barley_sack_2", &"barley_sack_3"]
## What BrewGuide counts as "had": raw stuff of the stalls and the sacks.
const STOCK: Array[StringName] = [WARE_HOPS, WARE_LOGS, WARE_YEAST, WARE_HONEY, WARE_LINDEN, WARE_JUNIPER, WARE_CHERRIES,
	SACK_PALE_MALT, SACK_CARAMEL_MALT, SACK_OATS, SACK_DARK, SACK_SMOKED]

# ---- Kinds of grain (malts.json, MaltLot.kind) --------------------------------

const MALT_BARLEY := &"barley"
const MALT_PALE := &"pale"
const MALT_CARAMEL := &"caramel"
const MALT_DARK := &"dark"
const MALT_SMOKED := &"smoked"
const MALT_OATS := &"oats"
const MALTS: Array[StringName] = [MALT_BARLEY, MALT_PALE, MALT_CARAMEL, MALT_DARK, MALT_SMOKED, MALT_OATS]

# ---- Keys of a profile (BrewTaste.profile) that are numbers -------------------

const PROFILE_KEYS: Array[StringName] = [&"strength", &"gravity", &"body", &"sweetness", &"bitterness", &"aroma", &"color",
	&"clarity", &"smoke", &"foam", &"quality"]
