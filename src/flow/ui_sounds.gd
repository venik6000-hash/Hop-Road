extends Node
## The sounds of the menus and the settings panel, on the bus UI: a button
## under the pointer or the focus (HOVER), a press (CLICK), a menu or a panel
## that opens (OPEN) or shuts (CLOSE). GameFlow owns the one player of them
## (node UiSounds). A screen wires its buttons with wire(), tells of its
## opening and shutting with play() and gives the focus with focus(); they
## find the player by its path.

const HOVER := &"hover"
const CLICK := &"click"
const OPEN := &"open"
const CLOSE := &"close"
const SOUNDS: Dictionary[StringName, String] = {
	HOVER: "res://assets/audio/ui/hover.ogg",
	CLICK: "res://assets/audio/ui/click.ogg",
	OPEN: "res://assets/audio/ui/open.ogg",
	CLOSE: "res://assets/audio/ui/close.ogg",
}
## dB of each sound: the hover is the quietest, it comes the most often.
const VOLUMES: Dictionary[StringName, float] = {HOVER: -12.0, CLICK: -6.0, OPEN: -4.0, CLOSE: -4.0}
## The rank of each sound: in one frame, a sound of the rank of one played
## before it or lower stays silent. A button that opens a screen opens it
## before its click comes.
const RANKS: Dictionary[StringName, int] = {HOVER: 0, CLICK: 1, OPEN: 2, CLOSE: 2}
## The sounds heard last, the oldest first (tests).
const HEARD := 16
const PATH := "/root/GameFlow/UiSounds"

## A focus that the code gives (focus) makes no sound.
static var _quiet_focus := false

## The last HEARD sounds played.
var heard: Array[StringName] = []
var _players: Dictionary[StringName, AudioStreamPlayer] = {}
var _frame := -1
var _frame_rank := -1

func _ready() -> void:
	for kind: StringName in SOUNDS:
		var player := AudioStreamPlayer.new()
		player.name = String(kind).capitalize()
		player.stream = load(SOUNDS[kind]) as AudioStream
		player.bus = AudioBuses.UI
		player.volume_db = VOLUMES[kind]
		add_child(player)
		_players[kind] = player

## Plays `kind` (SOUNDS), unless a sound of its rank or higher has played in this frame.
func sound(kind: StringName) -> void:
	var frame := Engine.get_process_frames()
	if frame == _frame and RANKS[kind] <= _frame_rank:
		return
	_frame = frame
	_frame_rank = RANKS[kind]
	heard.append(kind)
	if heard.size() > HEARD:
		heard.pop_front()
	_players[kind].play()

## Plays `kind` on the game's player; nothing before GameFlow stands.
static func play(kind: StringName) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var player := tree.root.get_node_or_null(PATH) if tree != null else null
	if player != null:
		player.call(&"sound", kind)

## Gives every button under `root` (itself too) its sounds: HOVER when the
## pointer or the focus comes to it, CLICK when it is pressed. A tab bar
## or a tab container clicks when its tab changes.
static func wire(root: Node) -> void:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	for node: Node in nodes:
		var button := node as BaseButton
		if button != null:
			button.mouse_entered.connect(_hover.bind(button))
			button.focus_entered.connect(_hover.bind(button))
			button.pressed.connect(play.bind(CLICK))
		if node is TabContainer or node is TabBar:
			node.connect(&"tab_changed", _tab_changed)

## Gives `control` the focus without a sound: a screen that opens or comes back.
static func focus(control: Control) -> void:
	_quiet_focus = true
	control.grab_focus()
	_quiet_focus = false

static func _hover(button: BaseButton) -> void:
	if not button.disabled and not _quiet_focus:
		play(HOVER)

static func _tab_changed(_tab: int) -> void:
	play(CLICK)
