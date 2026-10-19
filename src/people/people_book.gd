class_name PeopleBook
extends RefCounted
## The valley's people: the sheets of the villagers, what has grown between
## each of them and the player, their voices (Storyteller), and the common
## sheet. Who the villagers are is the folder's: every sheet in it but the
## common one is a villager, by the stem of its file (roster). A passer-by
## without a sheet of their own speaks by the common one, and so does a
## villager where their own sheet has no line.

const FOLDER := "res://assets/loop/people/"

## Id -> PersonSheet, id -> Acquaintance and id -> Storyteller of the villagers.
var sheets: Dictionary = {}
var bonds: Dictionary = {}
var tellers: Dictionary = {}
var common := PersonSheet.new()

static func load_folder(folder := FOLDER) -> PeopleBook:
	var book := PeopleBook.new()
	book.common = PersonSheet.load_file(sheet_path(PeopleIds.COMMON, folder), PeopleIds.COMMON)
	for id in roster(folder):
		book.add(PersonSheet.load_file(sheet_path(id, folder), id))
	return book

## The ids of the villagers whose sheets lie in `folder`: the stems of its
## *.json files but the common sheet's, in the order of their names.
static func roster(folder := FOLDER) -> Array[StringName]:
	var ids: Array[StringName] = []
	var names := DirAccess.get_files_at(folder)
	names.sort()
	for file_name in names:
		if file_name.get_extension() == "json" and file_name.get_basename() != String(PeopleIds.COMMON):
			ids.append(StringName(file_name.get_basename()))
	return ids

## The file of the sheet of `id` in `folder`.
static func sheet_path(id: StringName, folder := FOLDER) -> String:
	return folder + String(id) + ".json"

func add(page: PersonSheet) -> void:
	sheets[page.id] = page
	var grown := Acquaintance.new()
	grown.thresholds = page.circles
	bonds[page.id] = grown
	tellers[page.id] = Storyteller.new(page, grown, common)

## Whether `id` is a villager with a sheet; "" and a passer-by are not.
func knows(id: String) -> bool:
	return sheets.has(id)

## The villager's sheet, the common one for anyone else.
func sheet(id: String) -> PersonSheet:
	return sheets.get(id, common)

## What has grown with the villager; null for anyone else.
func bond(id: String) -> Acquaintance:
	return bonds.get(id)

## The villager's voice; null for anyone else.
func teller(id: String) -> Storyteller:
	return tellers.get(id)

## A voice for a passer-by: the common remarks, no stories and no warmth.
func passerby() -> Storyteller:
	return Storyteller.new(common, Acquaintance.new(), common)

## What a villager is called: the role until they tell their name.
func label(id: String) -> String:
	if not knows(id):
		return ""
	return sheet(id).name if bond(id).introduced else sheet(id).role

## The person's line for `key`: their own, else the common one, else "".
func line(id: String, key: String) -> String:
	var own := sheet(id).line(key)
	return own if not own.is_empty() else common.line(key)

## The person's line for `key` at the circle the player has reached with them
## (PersonSheet.line_at): their own, else the common one, else "".
func line_at(id: String, key: String) -> String:
	var grown := bond(id)
	var circle: int = grown.circle if grown != null else 0
	var own := sheet(id).line_at(key, circle)
	return own if not own.is_empty() else common.line_at(key, circle)

func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for id: String in bonds:
		result[id] = bond(id).to_dict()
	return result

func restore(data: Variant) -> void:
	if not data is Dictionary:
		return
	var saved: Dictionary = data
	for id: String in bonds:
		bond(id).restore(saved.get(id))
