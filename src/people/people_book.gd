class_name PeopleBook
extends RefCounted
## The valley's people: the sheets of the seven villagers, what has grown
## between each of them and the player, their voices (Storyteller), and the
## common sheet. A passer-by without a sheet of their own speaks by the common
## one, and so does a villager where their own sheet has no line.

const IDS: Array[String] = ["borr", "kul", "tomas", "ivar", "marta", "lina", "savva"]
const COMMON := "passerby"
const FOLDER := "res://assets/loop/people/"

## Id -> PersonSheet, id -> Acquaintance and id -> Storyteller of the villagers.
var sheets: Dictionary = {}
var bonds: Dictionary = {}
var tellers: Dictionary = {}
var common := PersonSheet.new()

static func load_folder(folder := FOLDER) -> PeopleBook:
	var book := PeopleBook.new()
	book.common = PersonSheet.load_file(folder + COMMON + ".json", COMMON)
	for id: String in IDS:
		book.add(PersonSheet.load_file(folder + id + ".json", id))
	return book

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
	for id: String in bonds:
		bond(id).restore(data.get(id))
