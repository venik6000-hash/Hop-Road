class_name BrewKegRack
extends RefCounted
## The cellar's kegs (BrewCellar): what each holds, where each stands (under
## a lager cask's tap, with the funnel in its bung hole), and the keg on the
## tavern's counter that Borr pours from and the guests drink.

## Litres a keg holds.
const KEG_L := 40.0
## Without the funnel in its bung hole this part of a tap's stream misses a keg.
const NO_FUNNEL_MISS := 0.5
## Litres the tavern's guests drink an hour of the day.
const GUESTS_L := 1.5
## The kegs of the rack (brewery.json's utensils).
const KEGS: Array[String] = ["keg_1", "keg_2", "keg_3", "keg_4", "keg_5", "keg_6"]

## Each keg: {liters, beer (the batch's profile when it was filled), bunged, blows}.
var kegs := {}
## The keg standing under each cask's tap ("" for none), the keg the funnel
## stands in, the keg on the tavern's counter.
var keg_under: Array[String] = []
var funnel_on := ""
var tap := ""
## The keg the counter has just emptied, for the world to take back to the
## rack (take_emptied).
var emptied := ""

func _init() -> void:
	for _cask in BrewCellar.CASKS:
		keg_under.append("")
	for id: String in KEGS:
		kegs[id] = _empty_keg()

static func _empty_keg() -> Dictionary:
	return {"liters": 0.0, "beer": {}, "bunged": false, "blows": 0}

## `liters` of `batch` from the tap of cask `number` onto the keg under it:
## an open keg takes what its funnel aims in and it has room for. Returns
## the litres it took.
func catch_stream(number: int, liters: float, batch: BrewBatch) -> float:
	var id := keg_under[number - 1]
	if id == "" or kegs[id].bunged:
		return 0.0
	var keg: Dictionary = kegs[id]
	var aimed := liters * (1.0 if funnel_on == id else 1.0 - NO_FUNNEL_MISS)
	var into := minf(aimed, KEG_L - Values.real(keg.liters))
	keg.liters = Values.real(keg.liters) + into
	keg.beer = BrewTaste.profile(batch)
	return into

## Keg `id` put where it stands: under the tap of cask `number` (0 for none).
func stand_keg(id: String, number: int) -> void:
	for index in BrewCellar.CASKS:
		if keg_under[index] == id:
			keg_under[index] = ""
	if number >= 1 and number <= BrewCellar.CASKS:
		keg_under[number - 1] = id
	if funnel_on == id and number == 0:
		funnel_on = ""

## Keg `id` set on the tavern's counter: "" when it is set, else why not:
## "busy" (another keg is there), "not_ready" (open or empty), "ruined".
func set_tap(id: String) -> String:
	if tap != "" and tap != id:
		return "busy"
	var keg: Dictionary = kegs[id]
	if not keg.bunged or Values.real(keg.liters) < BrewCellar.MUG_L:
		return "not_ready"
	if Values.table(keg.beer).get("ruined", false):
		return "ruined"
	tap = id
	return ""

## Keg `id` emptied and unbunged: it went away with its beer.
func empty_keg(id: String) -> void:
	if kegs.has(id):
		kegs[id] = _empty_keg()
		stand_keg(id, 0)
		take_tap(id)

func take_tap(id: String) -> void:
	if tap == id:
		tap = ""

## A mug drawn from the keg on the counter: its beer's profile; {} when no keg
## stands there, and Borr pours the old beer.
func pour_mug() -> Dictionary:
	if tap == "":
		return {}
	var keg: Dictionary = kegs[tap]
	keg.liters = Values.real(keg.liters) - BrewCellar.MUG_L
	var beer: Dictionary = keg.beer
	_settle_tap()
	return beer

## The tavern's guests drink from the keg on the counter for `minutes` of
## the day.
func serve_guests(minutes: float) -> void:
	if tap == "":
		return
	kegs[tap].liters = Values.real(kegs[tap].liters) - GUESTS_L * minutes / 60.0
	_settle_tap()

## The keg on the counter run dry goes back to the rack empty.
func _settle_tap() -> void:
	if tap != "" and Values.real(kegs[tap].liters) < BrewCellar.MUG_L:
		kegs[tap] = _empty_keg()
		emptied = tap
		tap = ""

func take_emptied() -> String:
	var id := emptied
	emptied = ""
	return id
