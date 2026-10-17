extends Node
## The player's settings (config_path): the language, the quality profile,
## the hand with the mug, the window, the field of view, the size of the
## interface, the volumes of the sound buses and the controls. The file is
## written as the save is (SaveService.write): whole or not at all, the
## previous one kept as .bak; one that does not read is set aside, and its
## .bak or the defaults are taken. Installed before
## the main scene and before InputActions: imported materials resolve the
## texture set of the profile directly, without retaining the
## full-resolution originals, and the map of controls holds the player's
## bindings from the first frame.
signal hand_visibility_changed(shown: bool)
signal hand_resolution_changed(mode: String)
signal quality_changed(profile: QualityProfile)
signal sharpness_changed(strength: float)
## The bindings or the look settings changed (the map is rebuilt already).
signal controls_changed
## The camera of the player takes the field of view `degrees`.
signal fov_changed(degrees: float)
const INPUT_ACTIONS = preload("res://src/core/input_actions.gd")
const SAVE_SERVICE = preload("res://src/save/save_service.gd")
const MANIFEST := "res://assets/generated/texture_quality/manifest.json"
const HAND_RESOLUTIONS := ["native", "maximum"]
const DEFAULT_HAND_RESOLUTION := "native"
## Limits of the look settings: the mouse's multiple of CameraRig.sensitivity,
## the stick's turn at full tilt (degrees a second), the sticks' dead zone.
const MOUSE_SENSITIVITY := Vector2(0.25, 3.0)
const PAD_LOOK_SPEED := Vector2(60.0, 360.0)
const STICK_DEADZONE := Vector2(0.05, 0.5)
const DEFAULT_PAD_LOOK_SPEED := 150.0
const WINDOWED := "windowed"
const FULLSCREEN := "fullscreen"
const WINDOW_MODES: Array[String] = [WINDOWED, FULLSCREEN]
## The sizes of the window the player can choose, px.
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2400, 1350), Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160)]
## The window of the project (project.godot, window_*_override).
const DEFAULT_WINDOW_SIZE := Vector2i(2400, 1350)
## The vertical field of view of the player's camera, degrees: the limits
## and the one of scenes/player/player.tscn.
const FOV := Vector2(50.0, 85.0)
const DEFAULT_FOV := 62.0
## The sizes of the interface the player can choose (Window.content_scale_factor).
const UI_SCALES: Array[float] = [0.75, 0.9, 1.0, 1.15, 1.3, 1.5]

## QualityProfile.IDS; the textures of a new one take effect after a restart.
var quality := QualityProfile.DEFAULT
var profile := QualityProfile.named(QualityProfile.DEFAULT)
## The profile the game started with: its textures and its forest are what
## the running game shows. Null in a copy that never entered the tree.
var started: QualityProfile
## The texture set installed at the start.
var active_textures := "maximum"
var show_hand := true
var hand_resolution := DEFAULT_HAND_RESOLUTION
## How far the finished picture is sharpened (SharpenPost), 0..1; 0: not at
## all. Takes effect at once.
var sharpness := 0.0
## WINDOW_MODES.
var window_mode := WINDOWED
var vsync := true
## The size of the window when it is not full screen: one of WINDOW_SIZES.
var window_size := DEFAULT_WINDOW_SIZE
var fov := DEFAULT_FOV
## One of UI_SCALES.
var ui_scale := 1.0
## Bus (AudioBuses.VOLUMES) -> volume 0..1.
var volumes: Dictionary[StringName, float] = {}
## The player's own bindings: InputActions.binding_key -> codes. A slot
## that is not here has its defaults.
var bindings: Dictionary = {}
var mouse_sensitivity := 1.0
var invert_y := false
var pad_look_speed := DEFAULT_PAD_LOOK_SPEED
var stick_deadzone := INPUT_ACTIONS.DEADZONE
## Languages.IDS; a file without one takes the system's (Languages.system_default).
var language := Languages.SOURCE
var config_path := "user://graphics.cfg"
var texture_error := ""
var _textures: Array[Texture2D] = []
## The file at config_path holds settings read or written by this game: only
## then is it kept as the .bak before the next write.
var _good_on_disk := false

func _enter_tree() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-file="):
			config_path = arg.trim_prefix("--settings-file=")
	load_preferences()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			quality = QualityProfile.valid(arg.trim_prefix("--quality="))
			profile = QualityProfile.named(quality)
		if arg.begins_with("--hand-resolution="):
			hand_resolution = valid_hand_resolution(arg.trim_prefix("--hand-resolution="))
		if arg.begins_with("--sharpness="):
			sharpness = clampf(arg.trim_prefix("--sharpness=").to_float(), 0.0, 1.0)
		if arg.begins_with("--language="):
			language = Languages.valid(arg.trim_prefix("--language="))
	Languages.apply(language)
	started = profile
	install_textures()
	apply_volumes()
	apply_controls()

static func valid_hand_resolution(value: String) -> String:
	return value if value in HAND_RESOLUTIONS else DEFAULT_HAND_RESOLUTION

## Reads config_path; what it lacks or holds broken keeps its default. A file
## that does not read is set aside (SaveService.set_aside), and its .bak is
## read in its place; without one the defaults stand.
func load_preferences() -> void:
	_reset_values()
	var config := ConfigFile.new()
	_good_on_disk = config.load(config_path) == OK
	if _good_on_disk:
		_read(config)
	elif FileAccess.file_exists(config_path):
		var copy := SAVE_SERVICE.set_aside(config_path)
		var backup := ConfigFile.new()
		var from_backup := backup.load(config_path + ".bak") == OK
		if from_backup:
			_read(backup)
		push_warning("The settings file %s cannot be read; %s, and %s." % [config_path,
			"it is kept as " + copy if not copy.is_empty() else "it is left as it is",
			"its .bak is taken" if from_backup else "the defaults are taken"])
	profile = QualityProfile.named(quality)

func _reset_values() -> void:
	language = Languages.system_default()
	quality = QualityProfile.DEFAULT
	show_hand = true
	hand_resolution = DEFAULT_HAND_RESOLUTION
	sharpness = 0.0
	window_mode = WINDOWED
	vsync = true
	window_size = DEFAULT_WINDOW_SIZE
	fov = DEFAULT_FOV
	ui_scale = 1.0
	for bus: StringName in AudioBuses.VOLUMES:
		volumes[bus] = 1.0
	_reset_controls()

func _reset_controls() -> void:
	bindings = {}
	mouse_sensitivity = 1.0
	invert_y = false
	pad_look_speed = DEFAULT_PAD_LOOK_SPEED
	stick_deadzone = INPUT_ACTIONS.DEADZONE

func _read(config: ConfigFile) -> void:
	if config.has_section_key("interface", "language"):
		language = Languages.valid(str(config.get_value("interface", "language")))
	if config.has_section_key("graphics", "quality"):
		quality = QualityProfile.valid(str(config.get_value("graphics", "quality")))
	else:
		# Preferences saved before profiles: a render tier and a texture set.
		quality = QualityProfile.from_tiers(str(config.get_value("graphics", "render", "balanced")),
			str(config.get_value("graphics", "textures", "maximum")))
	show_hand = _bool(config.get_value("graphics", "show_hand", true), true)
	hand_resolution = valid_hand_resolution(str(config.get_value("graphics", "hand_resolution", DEFAULT_HAND_RESOLUTION)))
	sharpness = Values.number(config.get_value("graphics", "sharpness", 0.0), 0.0, 0.0, 1.0)
	var mode := str(config.get_value("display", "window_mode", WINDOWED))
	window_mode = mode if mode in WINDOW_MODES else WINDOWED
	vsync = _bool(config.get_value("display", "vsync", true), true)
	var size: Variant = config.get_value("display", "window_size", DEFAULT_WINDOW_SIZE)
	window_size = size if size is Vector2i and WINDOW_SIZES.has(size) else DEFAULT_WINDOW_SIZE
	fov = Values.number(config.get_value("display", "fov", DEFAULT_FOV), DEFAULT_FOV, FOV.x, FOV.y)
	var scale := Values.number(config.get_value("display", "ui_scale", 1.0), 1.0, UI_SCALES[0], UI_SCALES[-1])
	ui_scale = scale if UI_SCALES.has(scale) else 1.0
	for bus: StringName in AudioBuses.VOLUMES:
		volumes[bus] = Values.number(config.get_value("sound", String(bus), 1.0), 1.0, 0.0, 1.0)
	if config.has_section("bindings"):
		for key: String in config.get_section_keys("bindings"):
			var codes: Variant = config.get_value("bindings", key)
			if codes is PackedStringArray:
				bindings[key] = codes
	mouse_sensitivity = Values.number(config.get_value("controls", "mouse_sensitivity", 1.0), 1.0,
		MOUSE_SENSITIVITY.x, MOUSE_SENSITIVITY.y)
	invert_y = _bool(config.get_value("controls", "invert_y", false), false)
	pad_look_speed = Values.number(config.get_value("controls", "pad_look_speed", DEFAULT_PAD_LOOK_SPEED),
		DEFAULT_PAD_LOOK_SPEED, PAD_LOOK_SPEED.x, PAD_LOOK_SPEED.y)
	stick_deadzone = Values.number(config.get_value("controls", "stick_deadzone", INPUT_ACTIONS.DEADZONE),
		INPUT_ACTIONS.DEADZONE, STICK_DEADZONE.x, STICK_DEADZONE.y)

static func _bool(value: Variant, fallback: bool) -> bool:
	return value if value is bool else fallback

## Writes the settings to config_path (SaveService.write). ERR_FILE_CANT_WRITE
## when they are not written: the files on disk then stay as they were.
func save_preferences() -> Error:
	var config := ConfigFile.new()
	config.set_value("interface", "language", language)
	config.set_value("graphics", "quality", String(quality))
	config.set_value("graphics", "show_hand", show_hand)
	config.set_value("graphics", "hand_resolution", hand_resolution)
	config.set_value("graphics", "sharpness", sharpness)
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "vsync", vsync)
	config.set_value("display", "window_size", window_size)
	config.set_value("display", "fov", fov)
	config.set_value("display", "ui_scale", ui_scale)
	for bus: StringName in volumes:
		config.set_value("sound", String(bus), volumes[bus])
	for key: String in bindings:
		config.set_value("bindings", key, bindings[key])
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	config.set_value("controls", "pad_look_speed", pad_look_speed)
	config.set_value("controls", "stick_deadzone", stick_deadzone)
	if not SAVE_SERVICE.write(config_path, config.encode_to_text(), _good_on_disk):
		push_warning("The settings file %s is not written; the file on disk is left as it was." % config_path)
		return ERR_FILE_CANT_WRITE
	_good_on_disk = true
	return OK


# --- language -----------------------------------------------------------------

## Every text of the game takes `id` (Languages.IDS) at once.
func set_language(id: String) -> Error:
	language = Languages.valid(id)
	Languages.apply(language)
	return save_preferences()

# --- graphics -----------------------------------------------------------------

func set_hand_visible(shown: bool) -> Error:
	show_hand = shown
	hand_visibility_changed.emit(shown)
	return save_preferences()

func set_hand_resolution(mode: String) -> Error:
	hand_resolution = valid_hand_resolution(mode)
	hand_resolution_changed.emit(hand_resolution)
	return save_preferences()

## The picture, the shadows and the grass take `id` at once; the textures and
## the forest after a restart (restart_required).
func set_quality(id: StringName) -> Error:
	quality = QualityProfile.valid(id)
	profile = QualityProfile.named(quality)
	quality_changed.emit(profile)
	return save_preferences()

func set_sharpness(strength: float) -> Error:
	sharpness = clampf(strength, 0.0, 1.0)
	sharpness_changed.emit(sharpness)
	return save_preferences()

func restart_required() -> bool:
	return profile.textures != active_textures or (started != null and profile.needs_restart(started))

func install_textures() -> void:
	var tier := profile.textures
	if tier == "maximum":
		return
	var parsed: Variant = DataFile.read(MANIFEST, WorldSchemas.texture_quality())
	var manifest: Dictionary = parsed if parsed is Dictionary else {}
	if not manifest.get("textures") is Array:
		texture_error = "Нет подготовленных текстур. Используются оригиналы."
		return
	var entries: Array = manifest.textures
	if entries.is_empty():
		texture_error = "Набор текстур пуст. Используются оригиналы."
		return
	# Validate the complete set first; never silently mix sets after a missing file.
	for entry: Dictionary in entries:
		if not entry.has(tier) or not ResourceLoader.exists(str(entry[tier].path)):
			texture_error = "Набор текстур неполный. Используются оригиналы."
			return
	for entry: Dictionary in entries:
		var texture := load(str(entry[tier].path)) as Texture2D
		if texture == null:
			_textures.clear()
			texture_error = "Не удалось загрузить текстуры. Требуется перезапуск."
			return
		_textures.append(texture)
	# Keep just the selected resources alive: later dynamic scene loads use them too.
	for i in entries.size():
		_textures[i].take_over_path(str(entries[i].source))
	active_textures = tier
	print("TEXTURE_QUALITY tier=%s textures=%d" % [active_textures, _textures.size()])

# --- display ------------------------------------------------------------------

## The window goes full screen or back into a window (WINDOW_MODES) at once.
func set_window_mode(mode: String) -> Error:
	window_mode = mode if mode in WINDOW_MODES else WINDOWED
	_apply_window()
	return save_preferences()

func set_vsync(enabled: bool) -> Error:
	vsync = enabled
	_apply_window()
	return save_preferences()

## The window takes `size` (WINDOW_SIZES) at once when it is not full screen,
## and in the middle of the screen.
func set_window_size(size: Vector2i) -> Error:
	window_size = size if WINDOW_SIZES.has(size) else DEFAULT_WINDOW_SIZE
	_apply_window()
	return save_preferences()

## The player's camera takes `degrees` at once (fov_changed).
func set_fov(degrees: float) -> Error:
	fov = clampf(degrees, FOV.x, FOV.y)
	fov_changed.emit(fov)
	return save_preferences()

## Every text and panel takes the size `scale` (UI_SCALES) at once.
func set_ui_scale(scale: float) -> Error:
	ui_scale = scale if UI_SCALES.has(scale) else 1.0
	_apply_ui_scale()
	return save_preferences()

## The window and the interface as the player set them. GameFlow calls it
## when the game starts from its main menu: a tool keeps its own window.
func apply_display() -> void:
	_apply_window()
	_apply_ui_scale()

## The sizes of WINDOW_SIZES that fit on the screen of the window; all of
## them without a screen (headless).
static func fitting_sizes() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var fitting: Array[Vector2i] = []
	for size: Vector2i in WINDOW_SIZES:
		if screen.x <= 0 or (size.x <= screen.x and size.y <= screen.y):
			fitting.append(size)
	return fitting

func _apply_window() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	# The movie writer (showreel) keeps the size of its project override.
	if OS.has_feature("movie"):
		return
	if window_mode == FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(window_size)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if screen.size.x > 0:
		DisplayServer.window_set_position(screen.position + (screen.size - window_size) / 2)

func _apply_ui_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.content_scale_factor = ui_scale

# --- sound --------------------------------------------------------------------

## Sets the volume of `bus` (AudioBuses.VOLUMES), 0..1, at once.
func set_volume(bus: StringName, linear: float) -> Error:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	AudioBuses.set_volume(bus, volumes[bus])
	return save_preferences()

func apply_volumes() -> void:
	for bus: StringName in volumes:
		AudioBuses.set_volume(bus, volumes[bus])

# --- controls -----------------------------------------------------------------

## Gives `action` the input `code` (InputActions.code_of) in its slot; an
## action that had the code takes the old one of `action`.
## ERR_ALREADY_IN_USE: another action would be left with no binding in that
## slot (InputActions.stranded); nothing changes.
func set_binding(action: String, code: String) -> Error:
	if not INPUT_ACTIONS.stranded(bindings, action, code).is_empty():
		return ERR_ALREADY_IN_USE
	bindings = INPUT_ACTIONS.rebind(bindings, action, code)
	return _controls_changed()

func set_mouse_sensitivity(value: float) -> Error:
	mouse_sensitivity = clampf(value, MOUSE_SENSITIVITY.x, MOUSE_SENSITIVITY.y)
	return _controls_changed()

func set_invert_y(inverted: bool) -> Error:
	invert_y = inverted
	return _controls_changed()

func set_pad_look_speed(value: float) -> Error:
	pad_look_speed = clampf(value, PAD_LOOK_SPEED.x, PAD_LOOK_SPEED.y)
	return _controls_changed()

func set_stick_deadzone(value: float) -> Error:
	stick_deadzone = clampf(value, STICK_DEADZONE.x, STICK_DEADZONE.y)
	return _controls_changed()

## Every binding and look setting back to its default.
func reset_controls() -> Error:
	_reset_controls()
	return _controls_changed()

## Builds the map of controls from the bindings.
func apply_controls() -> void:
	INPUT_ACTIONS.setup(bindings, stick_deadzone)

func _controls_changed() -> Error:
	apply_controls()
	controls_changed.emit()
	return save_preferences()
