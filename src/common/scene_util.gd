extends RefCounted
## Lookups into imported model scenes.

## The AnimationPlayer anywhere under `model` (an imported glTF scene), or null.
static func animation_player(model: Node) -> AnimationPlayer:
	return model.find_child("AnimationPlayer", true, false) as AnimationPlayer
