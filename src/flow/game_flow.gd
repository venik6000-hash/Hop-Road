extends Node
## The states of the game and the one place that moves between them
## (autoload GameFlow; docs/LOOP.md, «Состояния игры»): the start, the main
## menu, the loading of a level, the game and its pause. Only the flow
## changes the scene; GameEvents hears of each move (game_state_changed).
## The way out of a region takes the game through the loading screen into
## another region (travel): the level leaves whole, as on the way to the menu.
##
## The pause is the tree's (SceneTree.paused), and only the flow sets it, with
## its context of the input on top (InputActions.MENU): the
## level stops whole, its clock, villagers, brewery, physics and sounds. What
## runs in the pause has its own process_mode: the flow with its pause menu,
## the settings panel. The settings (F10) open over the pause menu; from the
## game they pause it first and go back to it when they close. The flow also
## owns the line that tells of a trouble with the save (SaveNotice), the
## music (MusicService), which follows each move, and the sounds of the
## menus (UiSounds).

const PAUSE_MENU = preload("res://src/flow/pause_menu.gd")
const SAVE_NOTICE = preload("res://src/flow/save_notice.gd")
const MAIN_MENU = preload("res://src/flow/main_menu.gd")
const MUSIC_SERVICE = preload("res://src/flow/music_service.gd")
const UI_SOUNDS = preload("res://src/flow/ui_sounds.gd")

const BOOT := &"boot"
const MENU := &"menu"
const LOADING := &"loading"
const PLAYING := &"playing"
const PAUSED := &"paused"
## The states each state may go to.
const MOVES: Dictionary[StringName, Array] = {
	BOOT: [MENU],
	MENU: [LOADING],
	LOADING: [PLAYING, MENU],
	PLAYING: [PAUSED, LOADING],
	PAUSED: [PLAYING, MENU],
}
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
## The loading screen (src/loading/world_loader.gd): it builds the level
## under itself, then says so by its signal `finished(ok)`; `world` is the
## level, `error` why it failed.
const LOADING_SCENE := "res://scenes/alpine/loading.tscn"

var state := BOOT
## The scenes the flow changes to (tests give stand-ins).
var menu_path := MENU_SCENE
var loading_path := LOADING_SCENE
## The regions the game goes between, by id (RegionDef.LIST; tests give theirs).
var region_list := RegionDef.LIST
var pause_menu: PAUSE_MENU
var save_notice: SAVE_NOTICE
var music: MUSIC_SERVICE
var ui_sounds: UI_SOUNDS
## The scene the flow has changed to: the menu or the loading screen with
## its level.
var scene: Node
## The pointer as the game had it before the pause.
var _mouse_mode := Input.MOUSE_MODE_VISIBLE

## The first line of the launch log: the game version, the engine and the build kind.
static func launch_line() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", "unknown"))
	return "GAME_VERSION %s godot=%s build=%s" % [version, Engine.get_version_info().string, "debug" if OS.is_debug_build() else "release"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu = PAUSE_MENU.new()
	pause_menu.name = "PauseMenu"
	pause_menu.resume.connect(resume)
	pause_menu.leave.connect(open_menu)
	pause_menu.quit.connect(quit_game)
	add_child(pause_menu)
	save_notice = SAVE_NOTICE.new()
	save_notice.name = "SaveNotice"
	add_child(save_notice)
	music = MUSIC_SERVICE.new()
	music.name = "Music"
	add_child(music)
	ui_sounds = UI_SOUNDS.new()
	ui_sounds.name = "UiSounds"
	add_child(ui_sounds)
	GameEvents.region_exit_reached.connect(travel)
	_adopt_main_scene.call_deferred()

## The game starts in the main menu (run/main_scene): the flow takes it for
## its own and puts the window as the player set it. A tool or a test that
## runs a script of its own leaves the flow at BOOT and the window as it is.
func _adopt_main_scene() -> void:
	var menu := get_tree().current_scene as MAIN_MENU
	if menu == null or state != BOOT:
		return
	print(launch_line())
	GameSettings.apply_display()
	_take_menu(menu)
	scene = menu
	_move(MENU)

## Goes to the main menu: the level is saved, the slot let go, and the
## level leaves whole. The flow alone lets the file go (SaveService.close);
## the level's loop does not. `notice` tells the player why ("" for nothing).
func open_menu(notice := "") -> void:
	if not _can(MENU):
		return
	get_tree().paused = false
	pause_menu.hide()
	InputActions.pop(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Saved while the level still stands; the slot is let go.
	SaveService.close()
	var menu: MAIN_MENU = (load(menu_path) as PackedScene).instantiate()
	menu.notice = notice
	_take_menu(menu)
	_change_to(menu)
	_move(MENU)

## Loads the level for a game in slot `slot`: anew (`fresh`) or from its
## save, in the region and at the spawn the save holds.
func play(slot: String, fresh := false) -> void:
	if state != MENU:
		return
	SaveService.open(slot, fresh)
	_load(SaveService.region, SaveService.spawn)

## Takes the player through the way out `exit` into its region, at its
## spawn. The save holds them there first; then the level leaves whole and
## the loading screen builds the other region. A way out to a region the
## game has not leads nowhere.
func travel(exit: RegionExit) -> void:
	if state != PLAYING:
		return
	if not _listed(exit.to):
		push_error("GameFlow: no region %s for the way out" % exit.to)
		return
	SaveService.travel(exit.to, exit.spawn)
	var slot := SaveService.slot
	# Saved while the level still stands; the file is let go.
	SaveService.close()
	_load(exit.to, exit.spawn)
	# The slot is opened again for the level that loads: its loop adds its
	# sections and reads the file. The way holds where the player is even
	# when the save above was not written.
	if not slot.is_empty():
		SaveService.open(slot)
	SaveService.travel(exit.to, exit.spawn)

## The region `region_id` is in the flow's list.
func _listed(region_id: StringName) -> bool:
	for entry: Dictionary in RegionDef.entries(region_list):
		if StringName(str(entry.id)) == region_id:
			return true
	return false

## The loading screen for the region `region_id` ("" or not listed: the first
## one), the player coming in at `spawn_id`.
func _load(region_id: StringName, spawn_id: StringName) -> void:
	var loader := (load(loading_path) as PackedScene).instantiate()
	loader.set(&"region_path", RegionDef.path_of(region_id, region_list))
	loader.set(&"spawn", spawn_id)
	loader.connect(&"finished", _loaded.bind(loader), CONNECT_ONE_SHOT)
	_change_to(loader)
	_move(LOADING)

func _loaded(ok: bool, loader: Node) -> void:
	if loader != scene or state != LOADING:
		return
	if ok:
		_move(PLAYING)
	else:
		# A level that did not stand is not saved over the slot.
		SaveService.forget_file()
		open_menu(str(loader.get(&"error")))

## Stops the game and shows the pause menu.
func pause() -> void:
	if not _can(PAUSED):
		return
	_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	InputActions.push(InputActions.MENU, self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.open(_settings_panel())
	_move(PAUSED)

## The action "settings": opens the settings panel of the menu or of the
## level, or shuts it. From the game it stops the game first, and the game
## goes on when the panel shuts.
func toggle_settings() -> void:
	if state == MENU:
		var menu := scene as MAIN_MENU
		if menu.settings.visible:
			menu.settings.close()
		else:
			menu.settings.open()
	elif state == PLAYING and _settings_panel() != null:
		pause()
		pause_menu.open_settings(true)
	elif state == PAUSED and pause_menu.settings != null:
		if pause_menu.settings.visible:
			pause_menu.settings.close()
		else:
			pause_menu.open_settings()

func resume() -> void:
	if state != PAUSED:
		return
	if pause_menu.visible:
		UI_SOUNDS.play(UI_SOUNDS.CLOSE)
	pause_menu.hide()
	get_tree().paused = false
	InputActions.pop(self)
	Input.mouse_mode = _mouse_mode
	_move(PLAYING)

## Saves the game that runs and closes the program.
func quit_game() -> void:
	SaveService.save()
	get_tree().quit()

## The level's settings panel; null for a level without one.
func _settings_panel() -> SettingsPanel:
	var found: Variant = scene.get(&"world")
	var world: Node = found if found is Node else null
	return world.get_node_or_null("Shared/Settings") as SettingsPanel if world != null else null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if InputActions.pressed(event, &"settings") and state in [MENU, PLAYING, PAUSED]:
		toggle_settings()
	elif InputActions.pressed(event, &"pause") and state in [PLAYING, PAUSED]:
		if state == PLAYING:
			pause()
		else:
			resume()
	else:
		return
	get_viewport().set_input_as_handled()

func _take_menu(menu: MAIN_MENU) -> void:
	menu.play.connect(play)
	menu.quit.connect(quit_game)

## The scene leaves the tree now (SceneTree.change_scene_to_node) and is
## freed at the end of the frame; `next` comes in its place.
func _change_to(next: Node) -> void:
	scene = next
	get_tree().change_scene_to_node(next)

func _can(to: StringName) -> bool:
	return MOVES[state].has(to)

func _move(to: StringName) -> void:
	var previous := state
	state = to
	GameEvents.game_state_changed.emit(to, previous)
