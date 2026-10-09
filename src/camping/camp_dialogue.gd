extends RefCounted
## What companions say at the camp: the talk lines and the favourite places.

## The lines a companion picks from on "T", by mood and by who it is.
static func talk_lines(actor: VillageNPC, outing: NpcOuting) -> Array[String]:
	var lines: Array[String]
	if outing.mode == "rest":
		lines = ["Послушай, как трещат дрова. В таверне за голосами этого не слышно.",
			"Старики говорили: наша вода помнит всё. Поэтому у каждого родника свой вкус пива.",
			"По этим дорогам странники когда-то носили вести между деревнями. Теперь они всё больше зарастают.",
			"Не обязательно всё время говорить. Давай просто посидим и посмотрим на воду."]
	elif actor.model_path.ends_with("monk.glb"):
		lines = ["Дорога кажется длинной, когда идёшь один. С хорошим собеседником даже горы становятся ближе.",
			"Я собираю истории о родниках. Один и тот же рассказ в каждой деревне звучит по-своему."]
	else:
		lines = ["Живу здесь давно, а всё равно иногда останавливаюсь смотреть на горы.",
			"Здесь есть хорошее место для привала. Попросишь — покажу."]
	return lines

static func favorite_index(actor: VillageNPC) -> int:
	if actor.model_path.ends_with("monk.glb"):
		return actor.route.size() - 1
	return 0 if actor.model_path.ends_with("civilian_1.glb") else mini(7, actor.route.size() - 1)

static func favorite_line(actor: VillageNPC) -> String:
	if actor.model_path.ends_with("monk.glb"):
		return "Вот мой любимый поворот. Здесь чувствуешь, какая большая долина. Можно остановиться и выпить."
	if actor.model_path.ends_with("civilian_1.glb"):
		return "Здесь люблю смотреть на воду. Когда был маленьким, казалось, за горами заканчивается весь мир."
	return "Видишь таверну отсюда? Вечером её огни помогают найти дорогу домой. Давай немного постоим."
