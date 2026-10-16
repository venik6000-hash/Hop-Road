class_name Campfire
extends Node3D
## The last log has burnt: the fire is out.
signal burnt_out
var meal := CampMeal.new()
var fuel := CampFuel.new()
var burning := false
var seats: Array[Dictionary] = []
var flames: HearthFire
var glow: OmniLight3D
var embers: MeshInstance3D
var sparks: CPUParticles3D
var smoke: CPUParticles3D
var potato: Node3D
var crackle: AudioStreamPlayer3D
var _clock := 0.0

func _ready() -> void:
	for index in range(11):
		var angle := TAU * index / 11.0
		CampProps.stone(self, Vector3(cos(angle) * 0.57, 0.09, sin(angle) * 0.57),
			Vector3(0.28, 0.18, 0.23), index)
	for index in range(5):
		CampProps.log_mesh(self, Vector3(0, 0.14 + index * 0.025, (index % 2 - 0.5) * 0.15), 0.84, 0.075, index * 1.1)
	embers = NpcProps.mesh(self, NpcProps.cylinder(0.46, 0.035), Color("30241e"), Vector3.UP * 0.035)
	flames = HearthFire.new()
	flames.configure(Vector3(0, 0.15, 0), Vector3.RIGHT, 0.9, 0.8)
	add_child(flames)
	glow = OmniLight3D.new()
	glow.position.y = 0.65
	glow.light_color = Color("ffb667")
	glow.light_energy = 4.0
	glow.omni_range = 7.0
	glow.omni_attenuation = 1.7
	glow.shadow_enabled = true
	glow.shadow_caster_mask = 0xFFFFFFFF & ~VegetationSystem.VISUAL_LAYER
	glow.add_to_group(AtmosphereFog.LAMP_GROUP)
	add_child(glow)
	sparks = _particles(true)
	smoke = _particles(false)
	potato = CampProps.potato()
	potato.position = Vector3(0.29, 0.095, 0.21)
	potato.add_child(CampProps.steam())
	add_child(potato)
	crackle = AudioStreamPlayer3D.new()
	crackle.stream = load("res://assets/audio/camping/fire_crackle.wav")
	var sound := crackle.stream as AudioStreamWAV
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sound.loop_end = int(sound.get_length() * sound.mix_rate)
	crackle.unit_size = 2.0
	crackle.max_distance = 14.0
	crackle.volume_db = -13.0
	crackle.bus = AudioBuses.AMBIENCE
	add_child(crackle)
	# Low stones can be stepped over; the hot centre remains a physical object.
	var body := StaticBody3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.60
	shape.height = 0.25
	var solid := CollisionShape3D.new()
	solid.shape = shape
	solid.position.y = 0.125
	body.add_child(solid)
	add_child(body)
	for seat: Dictionary in seats:
		var at := TavernInteractions.vector(seat.position) - global_position
		var direction := -Vector3(at.x, 0, at.z).normalized()
		CampProps.log_mesh(self, at + Vector3.UP * 0.15, 0.85, 0.14, atan2(direction.x, direction.z) + PI / 2.0)
	var jug := NpcProps.jug()
	jug.position = Vector3(-0.85, 0.015, 0.4)
	add_child(jug)
	set_burning(false)
	_update_potato()

## A fire lit with no log in it (a tool's shot) burns on its kindling, a log long.
func set_burning(value: bool) -> void:
	if value and fuel.empty():
		fuel.add_log()
	burning = value
	flames.visible = value
	glow.visible = value
	sparks.emitting = value
	smoke.emitting = value
	var material := embers.material_override as StandardMaterial3D
	material.emission_enabled = value
	material.emission = Color("dd5422")
	material.emission_energy_multiplier = 2.8
	if value:
		crackle.play()
	else:
		crackle.stop()

func interaction_text(holding: bool, holding_log := false) -> String:
	if holding_log:
		if fuel.seconds > (CampFuel.MAX_LOGS - 1) * CampFuel.LOG_SECONDS:
			return "Костёр полон дров"
		return tr("{interact} — подбросить полено · дров: %d") % fuel.logs() if burning else tr("{interact} — подбросить полено")
	if not burning:
		return "{interact} — разжечь костёр" if not fuel.empty() else "Нужны дрова: принеси полено из поленницы"
	if meal.ready():
		return "Сначала доешь картошку в руках · {camp_secondary} — потушить" if holding else "{interact} — достать печёную картошку · {camp_secondary} — потушить"
	if meal.cooking:
		return "Картошка печётся в углях… · {camp_secondary} — потушить"
	if holding:
		return "{eat_potato} — есть картошку · {camp_secondary} — поделиться рядом со спутником"
	return "{interact} — положить картошку в угли · {camp_secondary} — потушить"

func _process(delta: float) -> void:
	_clock += delta
	meal.advance(delta, burning)
	if burning:
		if fuel.burn(delta):
			set_burning(false)
			burnt_out.emit()
			return
		glow.light_energy = (3.8 + sin(_clock * 7.3) * 0.22 + sin(_clock * 13.0) * 0.1) * fuel.strength()
	_update_potato()

func _update_potato() -> void:
	potato.visible = meal.cooking
	var skin := potato.get_node("Skin") as MeshInstance3D
	var material := skin.material_override as StandardMaterial3D
	material.albedo_color = Color("9f784d").lerp(Color("453025"), meal.cooked_seconds / CampMeal.COOK_SECONDS)
	(potato.get_node("Steam") as CPUParticles3D).emitting = meal.ready()

func _particles(is_sparks: bool) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.position.y = 0.26
	particles.amount = 16 if is_sparks else 10
	particles.lifetime = 1.8 if is_sparks else 3.2
	particles.direction = Vector3.UP
	particles.spread = 18
	particles.initial_velocity_min = 0.3 if is_sparks else 0.12
	particles.initial_velocity_max = 0.7 if is_sparks else 0.22
	particles.gravity = Vector3(0.03, -0.1 if is_sparks else 0.08, 0)
	particles.scale_amount_min = 0.006 if is_sparks else 0.06
	particles.scale_amount_max = 0.018 if is_sparks else 0.19
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := NpcProps.material(Color("ffc16e") if is_sparks else Color(0.22, 0.20, 0.18, 0.1))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = is_sparks
	material.emission = Color("ff932e")
	material.emission_energy_multiplier = 3.0
	sphere.material = material
	particles.mesh = sphere
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles
