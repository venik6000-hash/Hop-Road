shader_type spatial;
// A beam of the lighthouse seen in the air: a cone of faint light from the
// lens outward (LighthouseOptic). It burns when the lanterns do, by the same
// measure of dusk.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// How far the lamps are lit, 0 by day .. 1 at night (SkySystem.dusk_of).
global uniform float lamp_dusk;

uniform vec3 beam_color : source_color = vec3(1.0, 0.78, 0.46);
// The cone's length, m: its mesh is a cylinder along y, the lens at the top.
uniform float shaft_length = 120.0;
// The shaft's light at the lens; it thins away toward the far end.
uniform float strength = 0.05;

varying float along;

void vertex() {
	along = clamp(0.5 - VERTEX.y / shaft_length, 0.0, 1.0);
}

void fragment() {
	float dusk = lamp_dusk;
	// Seen through its edge the cone is thin air: the sides fade out.
	float body = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float thin = (1.0 - along) * (1.0 - along);
	ALBEDO = beam_color * (strength * dusk * thin * body * body);
}
