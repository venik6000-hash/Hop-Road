shader_type canvas_item;
// Sharpens the finished picture (SharpenPost): the 3D image as the upscaler
// left it, at the window's resolution, before the HUD and the hand are drawn
// over it. A pixel is pushed away from the mean of its four neighbours, the
// less the more contrast there is round it already, so that an edge does not
// ring and nothing leaves the range of the display (AMD's CAS).
render_mode unshaded, blend_disabled;

uniform sampler2D picture : hint_screen_texture, filter_nearest, repeat_disable;
// 0: the picture as it is; 1: as sharp as it gets.
uniform float sharpness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec3 here = texture(picture, SCREEN_UV).rgb;
	vec3 above = texture(picture, SCREEN_UV - vec2(0.0, pixel.y)).rgb;
	vec3 below = texture(picture, SCREEN_UV + vec2(0.0, pixel.y)).rgb;
	vec3 before = texture(picture, SCREEN_UV - vec2(pixel.x, 0.0)).rgb;
	vec3 after = texture(picture, SCREEN_UV + vec2(pixel.x, 0.0)).rgb;
	vec3 darkest = min(here, min(min(above, below), min(before, after)));
	vec3 brightest = max(here, max(max(above, below), max(before, after)));
	// How far the pixel can move before it clips, against how far apart its
	// neighbourhood stands already.
	vec3 room = sqrt(clamp(min(darkest, 1.0 - brightest) / max(brightest, vec3(1e-4)), 0.0, 1.0));
	vec3 weight = -room * (0.2 * sharpness);
	COLOR = vec4((here + (above + below + before + after) * weight) / (1.0 + 4.0 * weight), 1.0);
}
