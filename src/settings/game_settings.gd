extends Node
## Installed before the main scene: imported materials resolve the selected
## texture resources directly, without retaining the full-resolution originals.
signal hand_visibility_changed(shown: bool)
signal hand_resolution_changed(mode: String)
signal render_quality_changed(tier: String)
const RenderQuality = preload("res://src/render/render_quality.gd")
const MANIFEST := "res://assets/generated/texture_quality/manifest.json"
const TIERS := ["maximum", "medium", "low"]
const HAND_RESOLUTIONS := ["native", "maximum"]
const DEFAULT_HAND_RESOLUTION := "native"
var texture_quality := "maximum"
var active_texture_quality := "maximum"
var show_hand := true
var hand_resolution := DEFAULT_HAND_RESOLUTION
## Render budget (RenderQuality.TIERS); takes effect at once.
var render_quality := RenderQuality.DEFAULT
var config_path := "user://graphics.cfg"
var texture_error := ""
var _textures: Array[Texture2D] = []

func _enter_tree() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-file="):
			config_path = arg.trim_prefix("--settings-file=")
	load_preferences()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--texture-quality="):
			texture_quality = valid_tier(arg.trim_prefix("--texture-quality="))
		if arg.begins_with("--hand-resolution="):
			hand_resolution = valid_hand_resolution(arg.trim_prefix("--hand-resolution="))
		if arg.begins_with("--render-quality="):
			render_quality = RenderQuality.valid(arg.trim_prefix("--render-quality="))
	install_textures()

static func valid_tier(value: String) -> String:
	return value if value in TIERS else "maximum"

static func valid_hand_resolution(value: String) -> String:
	return value if value in HAND_RESOLUTIONS else DEFAULT_HAND_RESOLUTION

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	texture_quality = valid_tier(str(config.get_value("graphics", "textures", "maximum")))
	var saved_hand: Variant = config.get_value("graphics", "show_hand", true)
	show_hand = saved_hand if saved_hand is bool else true
	hand_resolution = valid_hand_resolution(str(config.get_value("graphics", "hand_resolution", DEFAULT_HAND_RESOLUTION)))
	render_quality = RenderQuality.valid(str(config.get_value("graphics", "render", RenderQuality.DEFAULT)))

func save_preferences() -> Error:
	var config := ConfigFile.new()
	config.set_value("graphics", "textures", texture_quality)
	config.set_value("graphics", "show_hand", show_hand)
	config.set_value("graphics", "hand_resolution", hand_resolution)
	config.set_value("graphics", "render", render_quality)
	return config.save(config_path)

func set_hand_visible(shown: bool) -> Error:
	show_hand = shown
	hand_visibility_changed.emit(shown)
	return save_preferences()

func set_hand_resolution(mode: String) -> Error:
	hand_resolution = valid_hand_resolution(mode)
	hand_resolution_changed.emit(hand_resolution)
	return save_preferences()

func set_render_quality(tier: String) -> Error:
	render_quality = RenderQuality.valid(tier)
	render_quality_changed.emit(render_quality)
	return save_preferences()

func set_texture_quality(tier: String) -> Error:
	texture_quality = valid_tier(tier)
	return save_preferences()

func restart_required() -> bool:
	return texture_quality != active_texture_quality

func install_textures() -> void:
	if texture_quality == "maximum":
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or not parsed.get("textures") is Array:
		texture_error = "Нет подготовленных текстур. Используются оригиналы."
		return
	var entries: Array = parsed.textures
	if entries.is_empty():
		texture_error = "Набор текстур пуст. Используются оригиналы."
		return
	# Validate the complete tier first; never silently mix tiers after a missing file.
	for entry: Dictionary in entries:
		if not entry.has(texture_quality) or not ResourceLoader.exists(entry[texture_quality].path):
			texture_error = "Набор текстур неполный. Используются оригиналы."
			return
	for entry: Dictionary in entries:
		var texture := load(entry[texture_quality].path) as Texture2D
		if texture == null:
			_textures.clear()
			texture_error = "Не удалось загрузить текстуры. Требуется перезапуск."
			return
		_textures.append(texture)
	# Keep just the selected resources alive: later dynamic scene loads use them too.
	for i in entries.size():
		_textures[i].take_over_path(entries[i].source)
	active_texture_quality = texture_quality
	print("TEXTURE_QUALITY tier=%s textures=%d" % [active_texture_quality, _textures.size()])
