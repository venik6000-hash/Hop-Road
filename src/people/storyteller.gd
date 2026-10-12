class_name Storyteller
extends RefCounted
## One person's talk while the player keeps them company: the remarks of a
## stranger, the hooks that name a story, the story itself beat by beat, and
## the pauses between. The scene feeds it frames, sips and askings and shows
## the lines it returns. The words are the sheet's (PersonSheet); what was
## named and told is kept in the bond (Acquaintance).
##
## A moment is {day, zone, part, weather (ValleyLoop.moment), activity ("fire"
## by a campfire, "table" at a seat of the tavern, "bar" at its counter,
## "stand" or "walk"), listening (the player has stopped beside the person),
## halt (a number that changes with every new halt)}. It may also carry
## company (the ids of the villagers near the teller; nobody when left out),
## gift (Acquaintance.gift: what the player brought the person today) and
## can_guide (the person may lead to the place they love and has not yet).
##
## A line is {text, kind}; the kinds are "introduce", "beat", "hook_after",
## "hook_before", "echo", "later", "offer" and "idle". {} is silence. A beat
## also has `last`: the story ends with it. A beat of a shared story
## (PersonSheet) has `by`, the id of the one of the two who says it, and
## `with`, the id of the other teller.
##
## A story is told to a listener who has stopped. A sip or an asking brings
## the next beat at once; without them it comes by itself after BEAT_PAUSE.
## A person tells one story in a halt and STORIES_A_DAY in a day. A story the
## listener walked away from goes on, when they are back where it fits, from
## the beat they left at.

## Seconds of an outing before the person first speaks unasked.
const FIRST_PAUSE := 10.0
## Seconds between remarks that are not a story.
const WORD_PAUSE := 32.0
## The least and the most seconds before the next beat comes by itself: the
## time its caption stays (caption_seconds) and BEAT_READING on top.
const BEAT_PAUSE := Vector2(20.0, 30.0)
const BEAT_READING := 15.0
## Seconds after a caption has gone before a line that follows from it: the
## closing hook after the last beat, the first words after the name.
const NEXT_PAUSE := 3.0
## Seconds the listener may be away before the story breaks off.
const AWAY_SECONDS := 6.0
## The most seconds a name that is due is kept back, and the most one who has
## stopped to listen, or settled into a new halt, waits for a story to begin
## or to go on.
const RESUME_PAUSE := 4.0
## Seconds a line stays before a sip or an asking may bring the next.
const MIN_BEAT_SECONDS := 3.0
const STORIES_A_DAY := 2
## The circle from which the person no longer fills a silence with remarks.
const QUIET_CIRCLE := 3

var sheet: PersonSheet
var bond: Acquaintance
## The sheet whose remarks and lines fill in for what `sheet` lacks.
var common: PersonSheet
## The story being told, "" for none.
var telling := ""

var _wait := FIRST_PAUSE
var _away := 0.0
var _listening := false
var _seen_halt := -1
var _since := MIN_BEAT_SECONDS
## The halt the last story was told in, and that story.
var _halt := -1
var _halt_story := ""
## The halts an unasked hook and an echo were last said in.
var _hook_halt := -1
var _echo_halt := -1
var _asked := 0
## The person has offered, in this outing, to lead to the place they love.
var _offered := false
## Remarks said unasked in this outing.
var _said: Dictionary = {}

func _init(of_sheet: PersonSheet, of_bond: Acquaintance, of_common: PersonSheet) -> void:
	sheet = of_sheet
	bond = of_bond
	common = of_common

## The person sets out with the player, or the player comes up to the person
## at their place: an outing's own memory starts anew.
func begin_outing() -> void:
	telling = ""
	_wait = FIRST_PAUSE
	_away = 0.0
	_listening = false
	_seen_halt = -1
	_since = MIN_BEAT_SECONDS
	_halt = -1
	_halt_story = ""
	_hook_halt = -1
	_echo_halt = -1
	_asked = 0
	_offered = false
	_said.clear()

## A frame of the outing. `has_floor`: nobody else is telling a story;
## `can_speak`: the player is near and no caption is up. Returns the line the
## person says by themselves now.
func advance(delta: float, moment: Dictionary, has_floor: bool, can_speak: bool) -> Dictionary:
	_since += delta
	# One who has just stopped to listen, or settled into a new halt, is not
	# kept waiting for a story; nor is a name the first circle has made due.
	var settled: bool = moment.listening and (not _listening or moment.halt != _seen_halt)
	if _name_is_due() or (settled and telling.is_empty() and not _ready_story(moment).is_empty()):
		_wait = minf(_wait, RESUME_PAUSE)
	_listening = moment.listening
	_seen_halt = moment.halt
	if not telling.is_empty():
		if moment.listening:
			_away = 0.0
		else:
			_away += delta
			if _away > AWAY_SECONDS:
				telling = ""
				_away = 0.0
				_wait = RESUME_PAUSE
			return {}
	_wait -= delta
	if _wait > 0.0 or not has_floor or not can_speak:
		return {}
	var line := _spoken(_next(moment, has_floor, false))
	if line.is_empty():
		# Nothing to say: the person looks for words again after a pause, so
		# that what turns up next does not come on the heels of another line.
		_wait = WORD_PAUSE
	return line

## The player took a sip beside the person: the story goes on by a beat, or
## begins. {} when there is no story to move.
func sip(moment: Dictionary, has_floor: bool) -> Dictionary:
	if _since < MIN_BEAT_SECONDS:
		return {}
	var line := introduce()
	if line.is_empty():
		line = _story_line(moment, has_floor)
	return _spoken(line)

## The player asked the person to talk: a story if one may be told, else
## what stands in its way, a hook or a remark.
func ask(moment: Dictionary, has_floor: bool) -> Dictionary:
	if not telling.is_empty() and _since < MIN_BEAT_SECONDS:
		return {}
	return _spoken(_next(moment, has_floor, true))

## The person tells their name, once: when the first circle has opened.
func introduce() -> Dictionary:
	if not _name_is_due():
		return {}
	bond.introduced = true
	return {"text": sheet.line("introduce"), "kind": "introduce"}

func _name_is_due() -> bool:
	return not bond.introduced and bond.circle >= 1 and not sheet.line("introduce").is_empty()

## Seconds a caption with `text` stays on the screen.
static func caption_seconds(text: String) -> float:
	return maxf(5.0, float(text.length()) / 14.0)

## Seconds after a beat before the next one comes by itself.
static func pause_after(text: String) -> float:
	return clampf(caption_seconds(text) + BEAT_READING, BEAT_PAUSE.x, BEAT_PAUSE.y)

func _next(moment: Dictionary, has_floor: bool, asked: bool) -> Dictionary:
	var line := introduce()
	if line.is_empty():
		line = _story_line(moment, has_floor)
	if line.is_empty():
		line = _small_talk(moment, asked)
	return line

## The closing hook still owed, else the next beat of the story being told,
## else the first beat of one that may begin.
func _story_line(moment: Dictionary, has_floor: bool) -> Dictionary:
	if not bond.owed.is_empty():
		var hook: String = sheet.story(bond.owed).get("hook_after", "")
		bond.owed = ""
		if not hook.is_empty():
			return {"text": hook, "kind": "hook_after"}
	if not moment.listening or not has_floor:
		return {}
	var story := sheet.story(telling)
	var beat := bond.heard(telling) + 1
	if story.is_empty():
		story = _ready_story(moment)
		if story.is_empty():
			return {}
		# A story broken off goes on from the beat the listener left at.
		beat = maxi(0, bond.heard(story.id))
	var beats: Array = story.beats
	beat = mini(beat, beats.size() - 1)
	telling = story.id
	_halt = moment.halt
	_halt_story = story.id
	bond.hear(story.id, beat)
	if beat == beats.size() - 1:
		bond.finish(story.id, moment.day, not story.hook_after.is_empty())
		telling = ""
	var line: Dictionary = {"text": beats[beat], "kind": "beat", "last": beat == beats.size() - 1}
	var partner: String = story.get("with", "")
	if not partner.is_empty():
		var voices: Array = story.get("voices", [])
		var by: String = sheet.id
		if beat < voices.size():
			by = voices[beat]
		line["by"] = by
		line["with"] = partner
	return line

## The story that may begin at the moment, {} for none.
func _ready_story(moment: Dictionary) -> Dictionary:
	var story := StoryRules.choose(sheet.stories, bond, moment)
	if story.is_empty() or not _held_back(story, moment).is_empty():
		return {}
	return story

## The line that says why `story` cannot begin now: "later_day" after the
## day's stories, "later_halt" after this halt's; "" when it can.
func _held_back(story: Dictionary, moment: Dictionary) -> String:
	if bond.told_on(moment.day) >= STORIES_A_DAY:
		return "later_day"
	if _halt == moment.halt and _halt_story != story.id:
		return "later_halt"
	return ""

## What is said when no story is: to one who asked, what holds a fitting
## story back; a hook to a story not yet named (unasked, one in a halt); an
## echo of a story told here (one in a halt); unasked, the offer to lead to
## the place they love (once an outing); then, to one who asked, the named
## hooks and the remarks in turn, and unasked each remark once, unless the
## circle is one of quiet.
func _small_talk(moment: Dictionary, asked: bool) -> Dictionary:
	if asked and moment.listening:
		var fitting := StoryRules.choose(sheet.stories, bond, moment)
		if not fitting.is_empty():
			var later := _line(_held_back(fitting, moment))
			if not later.is_empty():
				return {"text": later, "kind": "later"}
	var turn: Array[String] = []
	for story: Dictionary in sheet.stories:
		if story.circle > bond.circle or story.hook_before.is_empty() or StoryRules.fits(story, moment):
			continue
		if bond.state(story.id).is_empty() and (asked or _hook_halt != moment.halt):
			bond.name_story(story.id)
			_hook_halt = moment.halt
			return {"text": story.hook_before, "kind": "hook_before"}
		if bond.state(story.id) == Acquaintance.NAMED:
			turn.append(story.hook_before)
	if _echo_halt != moment.halt:
		for story: Dictionary in sheet.stories:
			var told_now: bool = _halt == moment.halt and _halt_story == story.id
			if bond.state(story.id) == Acquaintance.TOLD and not story.echo.is_empty() and not told_now \
					and StoryRules.matches(story.context, moment):
				_echo_halt = moment.halt
				return {"text": story.echo, "kind": "echo"}
	var may_guide: bool = moment.get("can_guide", false)
	if not asked and may_guide and bond.circle >= 1 and not _offered:
		_offered = true
		var offer := _line("offer_guide")
		if not offer.is_empty():
			return {"text": offer, "kind": "offer"}
	var remarks := _remarks(moment)
	if asked:
		turn.append_array(remarks)
		if turn.is_empty():
			return {}
		_asked += 1
		return {"text": turn[(_asked - 1) % turn.size()], "kind": "idle"}
	if bond.circle >= QUIET_CIRCLE:
		return {}
	for remark: String in remarks:
		if not _said.has(remark):
			_said[remark] = true
			return {"text": remark, "kind": "idle"}
	return {}

## The remarks for the moment: those for a fire, for a table and the bar, or
## a stranger's; the person's own, else the common ones. One without remarks
## for a table says a stranger's there.
func _remarks(moment: Dictionary) -> Array[String]:
	if moment.activity == "fire":
		return sheet.idle_fire if not sheet.idle_fire.is_empty() else common.idle_fire
	if moment.activity == "table" or moment.activity == "bar":
		if not sheet.idle_table.is_empty():
			return sheet.idle_table
		if sheet.idle.is_empty() and not common.idle_table.is_empty():
			return common.idle_table
	return sheet.idle if not sheet.idle.is_empty() else common.idle

## The line for `key` at the bond's circle (PersonSheet.line_at): the
## person's own, else the common one.
func _line(key: String) -> String:
	if key.is_empty():
		return ""
	var own := sheet.line_at(key, bond.circle)
	return own if not own.is_empty() else common.line_at(key, bond.circle)

## Sets the pause that follows the line.
func _spoken(line: Dictionary) -> Dictionary:
	if line.is_empty():
		return line
	_since = 0.0
	var text: String = line.text
	if line.kind == "beat" and not telling.is_empty():
		_wait = pause_after(text)
	elif line.kind == "introduce" or not bond.owed.is_empty():
		_wait = caption_seconds(text) + NEXT_PAUSE
	else:
		_wait = WORD_PAUSE
	return line
