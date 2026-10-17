class_name Interaction
extends RefCounted
## What E would do to one thing the player looks at: the thing, how far it is,
## the prompt it shows and the act. A source of targets hands one to
## TavernInteractions (add_source); the nearest wins. A state that takes E
## whole (the boat under way, a brewery's station) hands one as a hold
## (add_hold).
##
## A node of the group GROUP is a target of its own: it has
## `interaction(best: float, eye: TavernInteractions) -> Interaction`, its
## nearest target nearer than `best` (TavernInteractions.target_distance) or
## null. TavernInteractions asks every such node; it names none of them.

const GROUP := &"interactable"

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
