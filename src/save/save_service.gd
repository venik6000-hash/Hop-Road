extends Node
## The game's save (autoload SaveService): one file per slot, written whole
## or not at all, the previous one kept as .bak, an unreadable one set aside
## and never overwritten, older versions carried over by MIGRATIONS
## (docs/LOOP.md, «Сохранение»).
##
## The file is one JSON object. Each system that keeps something gives the
## service a section: a key and two callables, `save` () -> Dictionary and
## `restore` (Dictionary) -> void. The section of key ROOT gives the top-level
## fields; every other section is the object under its key. Systems do not
## write files of their own.
##
## A game opens a slot (open) or a tool a file of its own (open_path); the
## level's loop then adds the sections and calls load_save(). Without an open
## file nothing is read or written.

const V1_TO_V2 = preload("res://src/save/migrations/v1_to_v2.gd")
## The version of the file this game writes.
const VERSION := 2
## Steps that carry an older save over to VERSION: a save of version N goes
## through MIGRATIONS[N].apply(save, path it was read from), which returns it
## as version N + 1. Add a step with each VERSION bump; never change the file
## format without one.
const MIGRATIONS: Dictionary[int, GDScript] = {1: V1_TO_V2}
## The slots: FOLDER/<slot>/FILE.
const FOLDER := "user://saves"
const FILE := "valley.json"
const DEFAULT_SLOT := "1"
## Where the one save lay before the slots; the default slot reads it while
## the slot has no file of its own. The file is left where it is.
const LEGACY_PATH := "user://valley.json"
## The key of the section whose fields stand at the top of the file.
const ROOT := ""
## Seconds between saves while a file is open, and seconds within which a
## change that should not be lost is written (save_soon).
const SAVE_SECONDS := 20.0
const SOON_SECONDS := 2.0

## Where the slots lie, and the save of before the slots (tests move both).
var folder := FOLDER
var legacy_path := LEGACY_PATH
## The open slot; "" for a file a tool opened, or none.
var slot := ""
## The file saves go to; "" keeps nothing.
var path := ""
## The file load_save() reads: `path`, or the save of before the slots.
var _read_from := ""
## {key, save: Callable, restore: Callable}, in the order they are restored.
var _sections: Array[Dictionary] = []
var _save_in := SAVE_SECONDS
## The file at `path` holds a save read or written since it was opened; only
## then is it kept as the .bak before the next save.
var _good_on_disk := false
## The file at `path` could not be read and could not be set aside: no save
## may overwrite it.
var _keep_off := false

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

## The slots that hold a save, sorted.
func slots() -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for slot_id: String in DirAccess.get_directories_at(folder):
		if FileAccess.file_exists(slot_path(slot_id)):
			found.append(slot_id)
	found.sort()
	return found

## The file a game in slot `slot_id` reads: the slot's own, or for the
## default slot without one the save of before the slots; "" for none.
func slot_file(slot_id: String) -> String:
	if FileAccess.file_exists(slot_path(slot_id)):
		return slot_path(slot_id)
	if slot_id == DEFAULT_SLOT and FileAccess.file_exists(legacy_path):
		return legacy_path
	return ""

## The save a game in slot `slot_id` would read (read); {} for none.
func read_slot(slot_id: String) -> Dictionary:
	var file := slot_file(slot_id)
	return {} if file.is_empty() else read(file)

## The slot written last: the one to go on with; "" when no slot holds a save.
func last_slot() -> String:
	var found := ""
	var newest := -1
	for slot_id: String in slots():
		var written := FileAccess.get_modified_time(slot_path(slot_id))
		if written > newest:
			found = slot_id
			newest = written
	if found.is_empty() and not slot_file(DEFAULT_SLOT).is_empty():
		return DEFAULT_SLOT
	return found

## Opens slot `slot_id` (a plain file name: "1", "2"...) for the game that
## starts; the sections of the last one are dropped. A `fresh` game reads
## nothing; its first save keeps the slot's old file as the .bak.
func open(slot_id: String, fresh := false) -> void:
	if slot_id.is_empty() or not slot_id.is_valid_filename():
		push_error("SaveService: %s is no slot name" % slot_id)
		open_path("")
		return
	open_path(slot_path(slot_id))
	slot = slot_id
	if fresh:
		_read_from = ""
		_good_on_disk = FileAccess.file_exists(path)
	else:
		_read_from = slot_file(slot_id)

## Opens the file `file_path` for a tool's game ("" keeps nothing); the
## sections of the last one are dropped.
func open_path(file_path: String) -> void:
	slot = ""
	path = file_path
	_read_from = file_path
	_sections.clear()
	_save_in = SAVE_SECONDS
	_good_on_disk = false
	_keep_off = false

## The game goes on, but nothing more is written: the file stays as it is.
func forget_file() -> void:
	path = ""
	_read_from = ""

## Saves and lets the file go: the level that held the sections leaves.
func close() -> void:
	save()
	open_path("")

## Adds the section `key` (ROOT for the top-level fields): `save` gives its
## data, `restore` takes it back. Sections are restored in the order added.
func add_section(key: String, save_section: Callable, restore_section: Callable) -> void:
	_sections.append({"key": key, "save": save_section, "restore": restore_section})

## Saves within SOON_SECONDS: something the player would not want to lose
## has changed.
func save_soon() -> void:
	_save_in = minf(_save_in, SOON_SECONDS)

## Reads the open file and gives each section its part. False when there is
## nothing to read, or the file is not a save this game reads: then the game
## starts anew, and the file is copied aside and never overwritten.
func load_save() -> bool:
	if _read_from.is_empty() or not FileAccess.file_exists(_read_from):
		return false
	var saved := read(_read_from)
	if saved.is_empty():
		var copy := set_aside(_read_from)
		if _read_from == path:
			_keep_off = copy.is_empty()
		push_warning("The save %s cannot be read; %s." % [_read_from,
			"it is kept as " + copy if not copy.is_empty() else "it is left as it is and the game is not saved"])
		return false
	_good_on_disk = _read_from == path
	restore(saved)
	return true

## Gives each section its part of `saved` (a save of VERSION), in order.
func restore(saved: Dictionary) -> void:
	for section: Dictionary in _sections:
		var restore_section: Callable = section.restore
		var key: String = section.key
		restore_section.call(saved if key == ROOT else part(saved, key))

## The save as it is written: every section's data, and the version.
func document() -> Dictionary:
	var result := {}
	for section: Dictionary in _sections:
		var save_section: Callable = section.save
		var key: String = section.key
		var data: Dictionary = save_section.call()
		if key == ROOT:
			result.merge(data, true)
		else:
			result[key] = data
	result["version"] = VERSION
	return result

## Writes the sections to the open file. False when nothing is written: no
## file is open, the file must be kept, or a section's system is gone.
func save() -> bool:
	_save_in = SAVE_SECONDS
	if path.is_empty() or _keep_off or _sections.is_empty():
		return false
	for section: Dictionary in _sections:
		var save_section: Callable = section.save
		var restore_section: Callable = section.restore
		if not save_section.is_valid() or not restore_section.is_valid():
			return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if not write(path, JSON.stringify(document()), _good_on_disk):
		return false
	_good_on_disk = true
	GameEvents.game_saved.emit(slot)
	return true

## The section `key` of `saved`; {} when it holds none.
static func part(saved: Dictionary, key: String) -> Dictionary:
	var value: Variant = saved.get(key)
	return value if value is Dictionary else {}

## The save in the file `file_path`, brought up to VERSION; {} when there is
## none or it is not one this game reads.
static func read(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	return unpack(JSON.parse_string(FileAccess.get_file_as_string(file_path)), file_path)

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
	if (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0:
		return int(minf(float(value), 1e6))
	return -1

## Writes `text` to `file_path` whole or not at all: first to `file_path`.tmp,
## then renamed over it. With `keep_previous`, the file that was there stays
## as `file_path`.bak. False when the file is not written.
static func write(file_path: String, text: String, keep_previous: bool) -> bool:
	var file := FileAccess.open(file_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	if keep_previous and FileAccess.file_exists(file_path):
		DirAccess.copy_absolute(file_path, file_path + ".bak")
	return DirAccess.rename_absolute(file_path + ".tmp", file_path) == OK

## Copies a save that cannot be read to `file_path`.unreadable-<unix time>, so
## that a newer game can still read it or a person can mend it. Returns the
## copy's path, "" when the copy fails.
static func set_aside(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var copy := "%s.unreadable-%d" % [file_path, int(Time.get_unix_time_from_system())]
	return copy if DirAccess.copy_absolute(file_path, copy) == OK else ""
