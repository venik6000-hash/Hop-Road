class_name BrewingSchemas
extends RefCounted
## The schemas of assets/brewing/*.json (docs/plans/brewing.md; docs/LOOP.md,
## «Данные содержимого»). The names they share with the code are BrewIds.

const D := preload("res://src/data/data_schema.gd")

## recipes.json: the recipes of the brewer's book and the two names for what
## fits none.
static func recipes() -> Dictionary:
	var other := D.object({"id": D.id(&"sort"), "name": D.text(), "taste": D.text()})
	return D.object({
		"recipes": D.list(D.object({
			"id": D.id(&"sort"),
			"name": D.text(),
			"taste": D.text(),
			"steps": D.list(D.text(), 1),
			"need": D.optional(D.list(D.ref(&"note"), 1)),
			"none_of": D.optional(D.list(D.ref(&"note"), 1)),
			"ranges": D.optional(D.table(D.vector(2), &"", &"profile_key")),
		}), 1),
		"nameless": other,
		"spoiled": other,
	})

## flaws.json: flaw id -> what it is called and what causes it.
static func flaws() -> Dictionary:
	return D.table(D.object({"name": D.text(), "cause": D.text()}), &"flaw")

## trade.json: the wares, the stalls, the order board and the cart, the
## prices of beer and the orders of the board.
static func trade() -> Dictionary:
	var place := {"title": D.text(), "at": D.vector(3), "face": D.vector(2)}
	var priced := D.checked(D.table(D.whole(0), &"", &"sort"), func(value: Variant) -> String:
		for sort: StringName in BrewIds.SORTS:
			if not Values.table(value).has(sort):
				return "no price for the sort '%s'" % sort
		return "")
	return D.object({
		"start_coins": D.whole(0),
		"start_kegs": D.whole(0),
		"start_wood": D.table(D.whole(0)),
		"wares": D.table(D.object({"title": D.text(), "price": D.whole(1)}), &"ware"),
		"stalls": D.list(D.object({
			"id": D.id(&"place"),
			"title": D.text(),
			"at": D.vector(3),
			"face": D.vector(2),
			"wares": D.list(D.ref(&"ware"), 1),
		}), 1),
		"order_board": D.object(place),
		"cart": D.object(place),
		"beer_prices": priced,
		"order_markup": D.number(1.0),
		"cart_share": D.number(0.0, 1.0),
		"open_orders": D.whole(1),
		"orders": D.list(D.object({
			"id": D.id(&"order"),
			"who": D.text(),
			"beer": D.ref(&"sort"),
			"kegs": D.whole(1),
			"days": D.whole(1),
		}), 1),
	})

## guide.json: the places the guide points at and its steps, from the purchase
## of the raw stuff to the keg at the board. `done` names how the step is
## known to be done (BrewGuide.passed); the steps of other sorts are left out
## by `sorts` and `except`.
static func guide() -> Dictionary:
	var count := [D.number(0.0)]
	return D.object({
		"places": D.table(D.object({"title": D.text(), "arrive": D.number(0.0)}), &"guide_place", &"place"),
		"steps": D.list(D.object({
			"text": D.text(),
			"place": D.ref(&"guide_place"),
			"mark": D.optional(D.ref(&"brewery_station")),
			"done": D.tagged({
				"have": [D.ref(&"stock"), D.number(0.0)],
				"arrive": [],
				"copper_l": count,
				"fire": [],
				"copper_temp": count,
				"juniper": [],
				"tun_water": count,
				"stage": [D.choice(BrewIds.STAGES)],
				"sack": [D.ref(&"sack")],
				"stirred": count,
				"converted": [],
				"wort_in_copper": [],
				"hops": [],
				"boiled": count,
				"fire_out": [],
				"honey_in": [],
				"linden_in": [],
				"knocked_out": [],
				"on_coolship": [],
				"in_tun": [],
				"cool": [],
				"pitched": [],
				"skimmed": [],
				"fermented": [],
				"scalded": [],
				"cherries_in_cask": [],
				"racked": [],
				"cask_bunged": [],
				"aged": [],
				"kegs": [],
				"delivered": [],
			}),
			"sorts": D.optional(D.list(D.ref(&"sort"), 1)),
			"except": D.optional(D.list(D.ref(&"sort"), 1)),
		}), 1),
	})

## works.json: what the hand does at each kind of station (BrewStation).
static func works() -> Dictionary:
	return D.object({"stations": D.table(D.list(D.object({
		"id": D.id(&"work"),
		"title": D.text(),
		"gesture": D.choice(BrewGesture.KINDS),
		"held": D.optional(D.list(D.ref(&"utensil"), 1)),
		"part": D.optional(D.text()),
		"weight": D.optional(D.number(0.0)),
		"along": D.optional(D.vector(2, 0.0, 1.0)),
	}), 1))})

## malts.json: what each kind of grain gives (MaltLot).
static func malts() -> Dictionary:
	return D.table(D.object({"color": D.number(0.0), "extract": D.number(0.0, 1.0), "smoke": D.number(0.0, 1.0)}), &"malt")

## lines.json: what the brewery says by the crosshair, by id (BrewHouse).
static func lines() -> Dictionary:
	return D.object({"lines": D.table(D.text(), &"brew_line")})
