extends CanvasLayer
## Sharpens the finished picture (sharpen_post.gdshader). The pass has to see
## the image the upscaler made, at the window's resolution: a compositor
## effect (LensPost) works on the smaller image the upscaler is yet to
## enlarge, so this is a canvas pass that reads the screen. It is the lowest
## canvas layer: the HUD, the panels and the hand, which is drawn by a
## viewport of its own in a layer above, go over it and stay as they are.
## It follows GameSettings.sharpness.

const SHADER := preload("res://src/render/sharpen_post.gdshader")
## Under every other canvas layer of the game.
const LAYER := -100

var _rect := ColorRect.new()
var _material := ShaderMaterial.new()

func _ready() -> void:
	layer = LAYER
	_material.shader = SHADER
	_rect.material = _material
	# Should the shader fail, the pass draws nothing instead of a blank screen.
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		set_strength(settings.get(&"sharpness"))
		settings.connect(&"sharpness_changed", set_strength)
	else:
		set_strength(0.0)

## `strength` 0..1; at 0 the pass is not drawn and the screen is not copied.
func set_strength(strength: float) -> void:
	_rect.visible = strength > 0.0
	_material.set_shader_parameter("sharpness", clampf(strength, 0.0, 1.0))
