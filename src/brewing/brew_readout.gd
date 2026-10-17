class_name BrewReadout
extends Node
## The line by the crosshair at the brewery (BrewHouse): the number of the
## instrument looked at (a thermometer, the dipstick, the hourglass, the
## balance, the steelyard), the vessel the held instrument is pointed into,
## the maltings', the cellar's and the trade's things read off; a word said
## for a while (say) in place of it.

const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")
## Seconds a word stays by the crosshair.
const SAY_SECONDS := 2.5

var house: BrewHouse
var label: Label
var _eye: BrewEye
var _said := 0.0

## The line under the crosshair, read with the player's eye.
func attach(eye: BrewEye) -> void:
	_eye = eye
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -300.0
	label.offset_right = 300.0
	label.offset_top = 22.0
	label.offset_bottom = 52.0
	# A stall's price board or the order board is a long line: it wraps downwards.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.grow_vertical = Control.GROW_DIRECTION_END
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LEVEL_HUD.style_label(label)
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)

## A word by the crosshair for a while: a key of the table or words translated.
func say(text: String) -> void:
	if label != null:
		label.text = InputActions.hint(tr(text))
		_said = SAY_SECONDS

## The line of this frame: what is said, else what the eye reads.
func update(delta: float) -> void:
	if label == null:
		return
	_said -= delta
	if _said <= 0.0:
		label.text = InputActions.hint(tr(reading()))

## The number of the instrument looked at, or of the vessel the held
## thermometer or dipstick is pointed into; "" for none.
func reading() -> String:
	var camera := _eye.camera
	var work := house.work
	if camera == null or not camera.current or (work.busy() and work.station == null):
		return ""
	var trade_text := house.market.reading()
	if trade_text != "" or not work.near():
		return trade_text
	var malt_text := _malt_reading()
	if malt_text != "":
		return malt_text
	var layout := house.layout
	var day := house.day
	var held := house.carry.held
	if held == "thermometer" or held == "dipstick":
		var best := BrewEye.REACH
		var found := ""
		# An instrument goes into the vessel: its surface lies behind the rim
		# or the copper's walls. A fermenting tun is read only when the tun
		# itself is in sight: the cellar has a wall to the brewhouse.
		for id: String in BrewLayout.VESSELS + ["fermenting_tun_1_wort", "fermenting_tun_2_wort"]:
			var distance := _eye.aimed(house.to_global(layout.surface_point(id)))
			if id.begins_with("fermenting_tun_"):
				var look := house.to_global(layout.look("fermenter_" + id.get_slice("_", 2)))
				distance = distance if _eye.clear(look) else INF
			if distance < best:
				best = distance
				found = id
		if found.begins_with("fermenting_tun_"):
			return _tun_reading(held, int(found.get_slice("_", 2)))
		return BrewGauges.reading(day, held, found) if found != "" else ""
	var marks := {"hourglass": layout.moving_point("hourglass"), "balance": layout.moving_point("hop_balance_beam")}
	if held != "thermometer" and layout.utensils.has("thermometer"):
		marks.thermometer = layout.grip("thermometer")
	if BrewDay.SACKS.has(held) or BrewIds.BARLEY_SACKS.has(held):
		marks.steelyard = layout.moving_point("steelyard")
	var best := BrewEye.REACH
	var shown := ""
	for mark: String in marks:
		var point: Vector3 = marks[mark]
		var distance := _eye.read_at(point)
		if distance < best:
			best = distance
			shown = mark
	var cellar_text := ""
	var cellar_marks := _cellar_marks()
	for point: Vector3 in cellar_marks:
		var distance := _eye.read_at(point)
		if distance < best:
			best = distance
			cellar_text = str(cellar_marks[point])
	if cellar_text != "":
		return cellar_text
	if shown == "":
		return ""
	if shown == "steelyard" and BrewIds.BARLEY_SACKS.has(held):
		return tr("Безмен: %.1f кг") % (house.maltings.load_kg(held) + float(BrewCarry.WEIGHTS.sack))
	return BrewGauges.reading(day, shown, held if shown == "steelyard" else "")

## What the eye reads off the maltings looked at: the tub, the floor, the
## kiln, the quern ("" when none is looked at).
func _malt_reading() -> String:
	var best := BrewEye.REACH
	var shown := ""
	for place: String in ["steep", "floor", "kiln", "mill"]:
		var distance := _eye.read_at(house.to_global(house.layout.look(place)))
		if distance < best:
			best = distance
			shown = place
	return house.maltings.reading(shown, house.carry.held, house.day.fine_thermometer) if shown != "" else ""

## The thermometer or the dipstick in fermenting tun `number`.
func _tun_reading(instrument: String, number: int) -> String:
	var cellar := house.cellar
	var batch := cellar.tun_batch(number)
	if batch == null:
		return "Бродильный чан пуст"
	if instrument == "dipstick":
		return tr("Бродильный чан: %.0f л") % cellar.tun_l(number)
	var cooling := batch.stage == BrewIds.STAGE_COOLED or (batch.stage == BrewIds.STAGE_PITCHED and batch.ferment_days == 0)
	return tr("Бродильный чан: %s") % BrewGauges.degrees(batch.wort_temp if cooling else BrewCellar.TEMP, house.day.fine_thermometer)

## What the eye reads off the cellar's things looked at: world point -> words.
func _cellar_marks() -> Dictionary:
	var layout := house.layout
	var cellar := house.cellar
	var held := house.carry.held
	var marks := {}
	for number in range(1, BrewCellar.TUNS + 1):
		marks[house.to_global(layout.look("fermenter_%d" % number))] = _tun_words(number)
	for number in range(1, BrewCellar.CASKS + 1):
		marks[house.to_global(layout.look("lager_%d" % number) + Vector3.UP * 0.35)] = _cask_words(number)
	for id: String in BrewKegRack.KEGS:
		if id != held and not house.market.away(id):
			marks[layout.grip(id)] = _keg_words(id)
	marks[layout.grip("yeast_crock")] = tr("Горшок с дрожжами: %.1f л") % cellar.crock_l
	for id: String in BrewTrade.WOOD_CAP:
		if id != held and layout.utensils.has(id):
			var logs := tr("Буковые поленья: %d шт.") if id == "beech_log" else tr("Еловые поленья: %d шт.")
			marks[layout.grip(id)] = logs % Values.whole(house.trade.wood[id])
	return marks

func _tun_words(number: int) -> String:
	var cellar := house.cellar
	if not cellar.sound_tun(number):
		return "Бродильный чан рассохся: нужен бондарь"
	var batch := cellar.tun_batch(number)
	if batch == null:
		return "Бродильный чан пуст"
	var liters := cellar.tun_l(number)
	match batch.stage:
		BrewIds.STAGE_COOLED:
			return tr("Бродильный чан: %.0f л сусла · ждёт дрожжей") % liters
		BrewIds.STAGE_PITCHED:
			if batch.ferment_days == 0:
				return tr("Бродильный чан: %.0f л · дрожжи в сусле") % liters
			if batch.ferment >= 1.0:
				return tr("Бродильный чан: %.0f л · брожение кончилось") % liters
			if BrewYeast.head(cellar, number):
				return tr("Бродильный чан: %.0f л · бродит, день %d · шапка пены") % [liters, batch.ferment_days]
			return tr("Бродильный чан: %.0f л · бродит, день %d") % [liters, batch.ferment_days]
	return tr("Бродильный чан: %.0f л пива") % liters

func _cask_words(number: int) -> String:
	var cellar := house.cellar
	if not cellar.sound_cask(number):
		return "Лагерная бочка рассохлась: нужен бондарь"
	var cask: Dictionary = cellar.casks[number - 1]
	var batch: BrewBatch = cask.batch
	if batch == null:
		return "Лагерная бочка пуста · ошпарена" if cellar.scalded(number) else "Лагерная бочка пуста"
	var aged := tr("Лагерная бочка: %.0f л · выдержка %d из %d дн. · под пробкой") if cask.bunged \
		else tr("Лагерная бочка: %.0f л · выдержка %d из %d дн. · без пробки")
	return aged % [Values.real(cask.liters), batch.age_days, batch.ready_days()]

func _keg_words(id: String) -> String:
	var keg: Dictionary = house.cellar.rack.kegs[id]
	if Values.real(keg.liters) < 0.5:
		return "Бочонок пуст"
	var words := tr("Бочонок: %.0f л · %s · под пробкой") if keg.bunged else tr("Бочонок: %.0f л · %s")
	return words % [Values.real(keg.liters), tr(str(house.book.name_beer(Values.table(keg.beer)).get("name", "")))]

## What a taste says by the crosshair: green while the cask ages, else the
## beer the book names and its flaws.
static func taste_words(taste: Dictionary, brew_book: BrewBook) -> String:
	var flaws: Array = taste.get("flaws", [])
	if flaws.has(BrewIds.FLAW_GREEN):
		var days := Values.whole(taste.get("days_left", 0))
		return TranslationServer.translate_plural("Зелёное и резкое: бочке стоять ещё %d день.",
			"Зелёное и резкое: бочке стоять ещё %d дня.", days) % days
	var words: String = "%s, %.1f %%" % [TranslationServer.translate(str(brew_book.name_beer(taste).get("name", ""))),
		Values.real(taste.get("strength", 0.0))]
	var names := PackedStringArray()
	for id: Variant in flaws:
		var flaw: Dictionary = brew_book.flaws.get(id, {})
		names.append(TranslationServer.translate(str(flaw.get("name", id))))
	if not names.is_empty():
		words += " · " + ", ".join(names)
	return words
