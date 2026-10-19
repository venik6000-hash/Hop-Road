extends NpcJob
## A walker of the village road: the round is the road (NpcRounds), with a
## stop at each point. A kerb or a stair that holds the walker is stepped onto
## (VillageNPC.step_onto).

func _init() -> void:
	walks = true
