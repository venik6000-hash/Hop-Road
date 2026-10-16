extends Node
## The player's settings (config_path): the language, the quality profile,
## the hand with the mug, the volumes of the sound buses and the controls. Installed before
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
const INPUT_ACTIONS = preload("res://src/core/input_actions.gd")
const MANIFEST := "res://assets/generated/texture_quality/manifest.json"
const HAND_RESOLUTIONS := ["native", "maximum"]
const DEFAULT_HAND_RESOLUTION := "native"
## Limits of the look settings: the mouse's multiple of CameraRig.sensitivity,
## the stick's turn at full tilt (degrees a second), the sticks' dead zone.
const MOUSE_SENSITIVITY := Vector2(0.25, 3.0)
const PAD_LOOK_SPEED := Vector2(60.0, 360.0)
const STICK_DEADZONE := Vector2(0.05, 0.5)
const DEFAULT_PAD_LOOK_SPEED := 150.0

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

## Reads config_path; what it lacks or holds broken keeps its default.
func load_preferences() -> void:
	_reset_values()
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		_read(config)
	profile = QualityProfile.named(quality)

func _reset_values() -> void:
	language = Languages.system_default()
	quality = QualityProfile.DEFAULT
	show_hand = true
	hand_resolution = DEFAULT_HAND_RESOLUTION
	sharpness = 0.0
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
	sharpness = _number(config.get_value("graphics", "sharpness", 0.0), 0.0, Vector2(0.0, 1.0))
	for bus: StringName in AudioBuses.VOLUMES:
		volumes[bus] = _number(config.get_value("sound", String(bus), 1.0), 1.0, Vector2(0.0, 1.0))
	if config.has_section("bindings"):
		for key: String in config.get_section_keys("bindings"):
			var codes: Variant = config.get_value("bindings", key)
			if codes is PackedStringArray:
				bindings[key] = codes
	mouse_sensitivity = _number(config.get_value("controls", "mouse_sensitivity", 1.0), 1.0, MOUSE_SENSITIVITY)
	invert_y = _bool(config.get_value("controls", "invert_y", false), false)
	pad_look_speed = _number(config.get_value("controls", "pad_look_speed", DEFAULT_PAD_LOOK_SPEED),
		DEFAULT_PAD_LOOK_SPEED, PAD_LOOK_SPEED)
	stick_deadzone = _number(config.get_value("controls", "stick_deadzone", INPUT_ACTIONS.DEADZONE),
		INPUT_ACTIONS.DEADZONE, STICK_DEADZONE)

static func _bool(value: Variant, fallback: bool) -> bool:
	return value if value is bool else fallback

static func _number(value: Variant, fallback: float, limits: Vector2) -> float:
	var number: float = value if value is float or value is int else fallback
	return clampf(number, limits.x, limits.y)

func save_preferences() -> Error:
	var config := ConfigFile.new()
	config.set_value("interface", "language", language)
	config.set_value("graphics", "quality", String(quality))
	config.set_value("graphics", "show_hand", show_hand)
	config.set_value("graphics", "hand_resolution", hand_resolution)
	config.set_value("graphics", "sharpness", sharpness)
	for bus: StringName in volumes:
		config.set_value("sound", String(bus), volumes[bus])
	for key: String in bindings:
		config.set_value("bindings", key, bindings[key])
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	config.set_value("controls", "pad_look_speed", pad_look_speed)
	config.set_value("controls", "stick_deadzone", stick_deadzone)
	return config.save(config_path)

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
		if not entry.has(tier) or not ResourceLoader.exists(entry[tier].path):
			texture_error = "Набор текстур неполный. Используются оригиналы."
			return
	for entry: Dictionary in entries:
		var texture := load(entry[tier].path) as Texture2D
		if texture == null:
			_textures.clear()
			texture_error = "Не удалось загрузить текстуры. Требуется перезапуск."
			return
		_textures.append(texture)
	# Keep just the selected resources alive: later dynamic scene loads use them too.
	for i in entries.size():
		_textures[i].take_over_path(entries[i].source)
	active_textures = tier
	print("TEXTURE_QUALITY tier=%s textures=%d" % [active_textures, _textures.size()])

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
