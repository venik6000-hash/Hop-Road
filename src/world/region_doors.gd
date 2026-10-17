extends Node
## The ways out of the region the level stands in (RegionDef.exits): the
## player who walks into one is told to GameEvents (region_exit_reached), and
## GameFlow takes them into the other region. A way out opens once the player
## has stood outside it: one who comes in at a spawn inside its area is not
## sent back at once.

var exits: Array[RegionExit] = []
var player: Node3D
## Per way out: the player has stood outside it since the level stood.
var _open: Array[bool] = []

func _ready() -> void:
	_open.resize(exits.size())
	_open.fill(false)

func _physics_process(_delta: float) -> void:
	var at := player.global_position
	for index in exits.size():
		var inside := exits[index].area.has_point(at)
		if not inside:
			_open[index] = true
		elif _open[index]:
			_open[index] = false
			GameEvents.region_exit_reached.emit(exits[index])
			return
