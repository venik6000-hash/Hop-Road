class_name Interaction
extends RefCounted
## What E would do to one thing the player looks at: the thing, how far it is,
## the prompt it shows and the act. A source of targets hands one to
## TavernInteractions (add_source); the nearest wins.

## The thing itself, as TavernInteractions.selected shows it to others.
var subject: Variant
var distance := INF
## () -> String: the prompt, asked only for the target that wins.
var describe: Callable
## () -> void (any return is dropped): what E does.
var act: Callable

static func of(thing: Variant, at: float, text: Callable, action: Callable) -> Interaction:
	var found := Interaction.new()
	found.subject = thing
	found.distance = at
	found.describe = text
	found.act = action
	return found
