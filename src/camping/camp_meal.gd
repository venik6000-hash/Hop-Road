class_name CampMeal
extends RefCounted
## One potato in the coals, then two halves in the player's hands.
const COOK_SECONDS := 35.0
var cooking := false
var cooked_seconds := 0.0
var portions := 0

func put_in_coals() -> bool:
	if cooking or portions > 0:
		return false
	cooking = true
	cooked_seconds = 0.0
	return true

func advance(seconds: float, burning: bool) -> void:
	if cooking and burning:
		cooked_seconds = minf(COOK_SECONDS, cooked_seconds + maxf(0.0, seconds))

func ready() -> bool:
	return cooking and cooked_seconds >= COOK_SECONDS

func take() -> bool:
	if not ready():
		return false
	cooking = false
	portions = 2
	return true

func consume() -> bool:
	if portions <= 0:
		return false
	portions -= 1
	return true
