extends Node
## The game's save (autoload SaveService): one file per slot, written whole
## or not at all, the previous one kept as .bak and read when the file is not,
## an unreadable one set aside and never overwritten, older versions carried
## over by MIGRATIONS (docs/LOOP.md, «Сохранение»). The player hears of each
## trouble through GameEvents.save_trouble.
##
## The file is one JSON object. Each system that keeps something gives the
## service a section: a key and two callables, `save` () -> Dictionary and
## `restore` (Dictionary) -> void. The section of key ROOT gives the top-level
## fields; every other section is the object under its key. A section of a
## region (add_section with a region id) is the object under
## REGIONS/<region id>/<key>: what keeps places in the world coordinates of
## one region, such as the fires and the brewery. The sections of the other
## regions are kept as they were read. Systems do not write files of their own.
##
## A game opens a slot (open) or a tool a file of its own (open_path); the
## level's loop then adds the sections and calls load_save(). Without an open
## file nothing is read or written.
##
## The service also keeps where the game goes on between levels: the region
## the player is in and the spawn they came in at (region, spawn, the fields
## "region" and "spawn" of the file). It reads them when a file opens; a new
## game has neither. GameFlow reads them to load the level and sets them when
## the player goes into another region (travel).

const V1_TO_V2 = preload("res://src/save/migrations/v1_to_v2.gd")
const V2_TO_V3 = preload("res://src/save/migrations/v2_to_v3.gd")
const V3_TO_V4 = preload("res://src/save/migrations/v3_to_v4.gd")
## The version of the file this game writes.
const VERSION := 4
## Steps that carry an older save over to VERSION: a save of version N goes
## through MIGRATIONS[N].apply(save, path it was read from), which returns it
## as version N + 1. Add a step with each VERSION bump; never change the file
## format without one.
const MIGRATIONS: Dictionary[int, GDScript] = {1: V1_TO_V2, 2: V2_TO_V3, 3: V3_TO_V4}
## The slots: FOLDER/<slot>/FILE.
const FOLDER := "user://saves"
const FILE := "valley.json"
const DEFAULT_SLOT := "1"
## Where the one save lay before the slots; the default slot reads it while
## the slot has no file of its own. The file is left where it is.
const LEGACY_PATH := "user://valley.json"
## The key of the section whose fields stand at the top of the file.
const ROOT := ""
## The key of the object that holds the sections of each region by its id.
const REGIONS := "regions"
## Seconds between saves while a file is open, and seconds within which a
## change that should not be lost is written (save_soon).
const SAVE_SECONDS := 20.0
const SOON_SECONDS := 2.0
## The troubles of GameEvents.save_trouble: the file did not read and its
## .bak was read; neither read and the game starts anew; a save was not written.
const FROM_BACKUP := &"from_backup"
const STARTED_ANEW := &"started_anew"
const NOT_SAVED := &"not_saved"

## Where the slots lie, and the save of before the slots (tests move both).
var folder := FOLDER
var legacy_path := LEGACY_PATH
## The open slot; "" for a file a tool opened, or none.
var slot := ""
## The file saves go to; "" keeps nothing.
var path := ""
## The id of the region the player is in (RegionDef.id); "" for the first
## region of the game's list.
var region := &""
## The spawn the player came into the region at (RegionSpawn.id), until they
## have stood on their feet in it: then "", and the loop's place of the player
## holds where they are (ValleyLoop). While it is set, that place is not
## written or read.
var spawn := &""
## The file load_save() reads: `path`, or the save of before the slots.
var _read_from := ""
## {key, region (&"" for none), save: Callable, restore: Callable}, in the
## order they are restored.
var _sections: Array[Dictionary] = []
## The object REGIONS of the save last read: the sections of every region,
## the open level's among them.
var _regions: Dictionary = {}
var _save_in := SAVE_SECONDS
## The file at `path` holds a save read or written since it was opened; only
## then is it kept as the .bak before the next save.
var _good_on_disk := false
## The file at `path` could not be read and could not be set aside: no save
## may overwrite it.
var _keep_off := false
## The last save was not written: the player has been told once.
var _failing := false

func _ready() -> void:
	listen()

## Saves soon on the news that should not be lost (GameEvents): an order
## taken, given up or delivered, a new stage of the batch.
func listen() -> void:
	GameEvents.order_taken.connect(save_soon.unbind(1))
	GameEvents.order_dropped.connect(save_soon.unbind(1))
	GameEvents.order_delivered.connect(save_soon.unbind(2))
	GameEvents.brew_stage_changed.connect(save_soon.unbind(1))

func _process(delta: float) -> void:
	if path.is_empty():
		return
	_save_in -= delta
	if _save_in <= 0.0:
		save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()

## The file of slot `slot_id`.
func slot_path(slot_id: String) -> String:
	return folder.path_join(slot_id).path_join(FILE)

## The slots that hold a save or its .bak, sorted.
func slots() -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for slot_id: String in DirAccess.get_directories_at(folder):
		if kept(slot_path(slot_id)):
			found.append(slot_id)
	found.sort()
	return found

## The file a game in slot `slot_id` reads: the slot's own, or for the
## default slot without one the save of before the slots; "" for none. The
## file may be gone while its .bak is there (kept).
func slot_file(slot_id: String) -> String:
	if kept(slot_path(slot_id)):
		return slot_path(slot_id)
	if slot_id == DEFAULT_SLOT and kept(legacy_path):
		return legacy_path
	return ""

## The save a game in slot `slot_id` would read (read_kept); {} for none.
func read_slot(slot_id: String) -> Dictionary:
	var file := slot_file(slot_id)
	return {} if file.is_empty() else read_kept(file)

## The slot written last: the one to go on with; "" when no slot holds a save.
func last_slot() -> String:
	var found := ""
	var newest := -1
	for slot_id: String in slots():
		var file := slot_path(slot_id)
		var written := maxi(FileAccess.get_modified_time(file), FileAccess.get_modified_time(file + ".bak"))
		if written > newest:
			found = slot_id
			newest = written
	if found.is_empty() and not slot_file(DEFAULT_SLOT).is_empty():
		return DEFAULT_SLOT
	return found

## Opens slot `slot_id` (a plain file name: "1", "2"...) for the game that
## starts; the sections of the last one are dropped. A `fresh` game reads
## nothing; its first save keeps the slot's old file as the .bak when that
## file is a save this game reads. An old file that does not read is set aside.
func open(slot_id: String, fresh := false) -> void:
	if slot_id.is_empty() or not slot_id.is_valid_filename():
		push_error("SaveService: %s is no slot name" % slot_id)
		open_path("")
		return
	open_path(slot_path(slot_id))
	slot = slot_id
	if not fresh:
		_read_from = slot_file(slot_id)
		_take_where(read_kept(_read_from) if not _read_from.is_empty() else {})
		return
	_read_from = ""
	_take_where({})
	if not FileAccess.file_exists(path):
		return
	_good_on_disk = not read(path).is_empty()
	if not _good_on_disk:
		_keep_off = set_aside(path).is_empty()

## Opens the file `file_path` for a tool's game ("" keeps nothing); the
## sections of the last one are dropped.
func open_path(file_path: String) -> void:
	slot = ""
	path = file_path
	_read_from = file_path
	_sections.clear()
	_regions = {}
	_save_in = SAVE_SECONDS
	_good_on_disk = false
	_keep_off = false
	_failing = false
	_take_where(read_kept(file_path) if not file_path.is_empty() else {})

## The player goes into the region `region_id` at its spawn `spawn_id`: the
## next save holds them there.
func travel(region_id: StringName, spawn_id: StringName) -> void:
	region = region_id
	spawn = spawn_id

## Where the save `saved` holds the player: its region and spawn ("" for none).
func _take_where(saved: Dictionary) -> void:
	region = StringName(_text(saved.get("region")))
	spawn = StringName(_text(saved.get("spawn")))

## The game goes on, but nothing more is written: the file stays as it is.
func forget_file() -> void:
	path = ""
	_read_from = ""

## Saves and lets the file go: the level that held the sections leaves.
func close() -> void:
	save()
	open_path("")

## Adds the section `key` (ROOT for the top-level fields): `save` gives its
## data, `restore` takes it back. With `region_id` the section is of that
## region (RegionDef.id) and lies under REGIONS. Sections are restored in the
## order added.
func add_section(key: String, save_section: Callable, restore_section: Callable, region_id := &"") -> void:
	_sections.append({"key": key, "region": region_id, "save": save_section, "restore": restore_section})

## Saves within SOON_SECONDS: something the player would not want to lose
## has changed.
func save_soon() -> void:
	_save_in = minf(_save_in, SOON_SECONDS)

## Reads the open file and gives each section its part. A file that is not
## a save this game reads (or is gone) is set aside and never overwritten;
## its .bak is read in its place (FROM_BACKUP). False when there is nothing to
## read, or the .bak does not read either: then it is set aside too and the
## game starts anew (STARTED_ANEW).
func load_save() -> bool:
	if _read_from.is_empty() or not kept(_read_from):
		return false
	var saved := read(_read_from)
	if not saved.is_empty():
		_good_on_disk = _read_from == path
		restore(saved)
		return true
	var copy := set_aside(_read_from)
	if _read_from == path:
		# The .bak stays as it is until a save of this game is on disk.
		_keep_off = FileAccess.file_exists(path) and copy.is_empty()
	push_warning("The save %s cannot be read; %s." % [_read_from,
		"it is kept as " + copy if not copy.is_empty() else "it is left as it is"])
	var backup := read(_read_from + ".bak")
	if not backup.is_empty():
		restore(backup)
		_tell(FROM_BACKUP)
		return true
	set_aside(_read_from + ".bak")
	_tell(STARTED_ANEW)
	return false

## Gives each section its part of `saved` (a save of VERSION), in order.
func restore(saved: Dictionary) -> void:
	_regions = part(saved, REGIONS).duplicate(true)
	for section: Dictionary in _sections:
		var restore_section: Callable = section.restore
		var key: String = section.key
		var region_id: StringName = section.region
		if not region_id.is_empty():
			restore_section.call(region_part(saved, region_id, key))
		else:
			restore_section.call(saved if key == ROOT else part(saved, key))

## The save as it is written: every section's data, the sections of the
## other regions as they were read, and the version.
func document() -> Dictionary:
	var result := {}
	var regions := _regions.duplicate(true)
	for section: Dictionary in _sections:
		var save_section: Callable = section.save
		var key: String = section.key
		var region_id: StringName = section.region
		var data: Dictionary = save_section.call()
		if not region_id.is_empty():
			var held := part(regions, region_id)
			held[key] = data
			regions[String(region_id)] = held
		elif key == ROOT:
			result.merge(data, true)
		else:
			result[key] = data
	if not regions.is_empty():
		result[REGIONS] = regions
	if not region.is_empty():
		result["region"] = String(region)
	if not spawn.is_empty():
		result["spawn"] = String(spawn)
	result["version"] = VERSION
	return result

## Writes the sections to the open file. False when nothing is written: no
## file is open, a section's system is gone, or the file must be kept or did
## not write (NOT_SAVED, told once till a save is written again).
func save() -> bool:
	_save_in = SAVE_SECONDS
	if path.is_empty() or _sections.is_empty():
		return false
	for section: Dictionary in _sections:
		var save_section: Callable = section.save
		var restore_section: Callable = section.restore
		if not save_section.is_valid() or not restore_section.is_valid():
			return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if _keep_off or not write(path, JSON.stringify(document()), _good_on_disk):
		push_warning("The save %s is not written; the file on disk is left as it was." % path)
		if not _failing:
			_failing = true
			_tell(NOT_SAVED)
		return false
	_failing = false
	_good_on_disk = true
	GameEvents.game_saved.emit(slot)
	return true

func _tell(trouble: StringName) -> void:
	GameEvents.save_trouble.emit(trouble, slot)

## `value` when it is a text; "" otherwise.
static func _text(value: Variant) -> String:
	return value if value is String else ""

## The section `key` of `saved`; {} when it holds none.
static func part(saved: Dictionary, key: String) -> Dictionary:
	var value: Variant = saved.get(key)
	return value if value is Dictionary else {}

## The section `key` of the region `region_id` in `saved`; {} when it holds none.
static func region_part(saved: Dictionary, region_id: StringName, key: String) -> Dictionary:
	return part(part(part(saved, REGIONS), region_id), key)

## The save in the file `file_path`, brought up to VERSION; {} when there is
## none or it is not one this game reads.
static func read(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	return unpack(JSON.parse_string(FileAccess.get_file_as_string(file_path)), file_path)

## The save in `file_path`, or in its .bak when the file does not read (read).
static func read_kept(file_path: String) -> Dictionary:
	var saved := read(file_path)
	return saved if not saved.is_empty() else read(file_path + ".bak")

## A save lies at `file_path`, or its .bak beside it.
static func kept(file_path: String) -> bool:
	return FileAccess.file_exists(file_path) or FileAccess.file_exists(file_path + ".bak")

## A save as parsed from the file at `file_path` ("" for none), brought up to
## VERSION; {} when it is not a save of VERSION after the steps.
static func unpack(data: Variant, file_path := "") -> Dictionary:
	var current: Variant = migrate(data, file_path)
	if not current is Dictionary:
		return {}
	var saved: Dictionary = current
	return saved if _version(saved) == VERSION else {}

## A save as parsed, brought up to VERSION by MIGRATIONS; what is not a save of
## an older version comes back as it is. `file_path` is where it was read,
## for steps that read the files beside it ("" for none).
static func migrate(data: Variant, file_path := "") -> Variant:
	var steps: Dictionary[int, Callable] = {}
	for from: int in MIGRATIONS:
		steps[from] = Callable(MIGRATIONS[from], &"apply").bind(file_path)
	return migrate_by(data, steps, VERSION)

## migrate() with the given `steps` (version -> Callable that takes a save of
## that version and returns it as the next) up to version `target`. The data
## given is not changed.
static func migrate_by(data: Variant, steps: Dictionary[int, Callable], target: int) -> Variant:
	if not data is Dictionary:
		return data
	var saved: Dictionary = data
	var at := _version(saved)
	if at < 0:
		return data
	while at < target and steps.has(at):
		saved = steps[at].call(saved.duplicate(true))
		at += 1
		saved["version"] = at
	return saved

## The version a save names; -1 when it names none.
static func _version(saved: Dictionary) -> int:
	var value: Variant = saved.get("version")
	if not (value is float or value is int):
		return -1
	var number: float = value
	return int(minf(number, 1e6)) if is_finite(number) and number >= 0.0 else -1

## Writes `text` to `file_path` whole or not at all: first to `file_path`.tmp,
## then put in place (place). False when the file is not written; the files
## on disk then stay as they were.
static func write(file_path: String, text: String, keep_previous: bool) -> bool:
	var draft := file_path + ".tmp"
	var file := FileAccess.open(draft, FileAccess.WRITE)
	if file == null:
		return false
	if not file.store_string(text):
		file.close()
		DirAccess.remove_absolute(draft)
		return false
	file.close()
	return place(file_path, text, keep_previous)

## Renames the draft `file_path`.tmp over `file_path` when it reads back as
## `text`. A full disk cuts a draft short: such a draft is deleted, and the
## files on disk stay as they were. With `keep_previous`, the file that was
## there is renamed to `file_path`.bak first. False when the draft is not put
## in place.
static func place(file_path: String, text: String, keep_previous: bool) -> bool:
	var draft := file_path + ".tmp"
	if FileAccess.get_file_as_string(draft) != text:
		DirAccess.remove_absolute(draft)
		return false
	if keep_previous and FileAccess.file_exists(file_path):
		DirAccess.rename_absolute(file_path, file_path + ".bak")
	return DirAccess.rename_absolute(draft, file_path) == OK

## Copies a save that cannot be read to `file_path`.unreadable-<unix time>, so
## that a newer game can still read it or a person can mend it. Returns the
## copy's path, "" when the copy fails.
static func set_aside(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var copy := "%s.unreadable-%d" % [file_path, int(Time.get_unix_time_from_system())]
	return copy if DirAccess.copy_absolute(file_path, copy) == OK else ""
