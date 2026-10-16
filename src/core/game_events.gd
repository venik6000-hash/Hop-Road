extends Node
## What happens in the game, told to whoever listens (autoload GameEvents).
## A system emits a signal here instead of calling another system only to tell
## it the news; a system that needs an answer calls the other one directly.
## Each signal names who emits it and who listens to it now (docs/LOOP.md,
## «События»).

# Others emit these signals: none is emitted here.
@warning_ignore_start("unused_signal")

## The game has gone from state `previous` to `state` (GameFlow.BOOT, MENU,
## LOADING, PLAYING, PAUSED): GameFlow.
signal game_state_changed(state: StringName, previous: StringName)
## A game day has begun at dawn (DayClock.DAY_START): ValleyLoop.
signal day_started(day: int)
## The part of the day has turned (DayClock.part): ValleyLoop.
signal part_of_day_changed(part: String)
## The player has lain down in a bed; the eyes close: ValleyLoop. CampSystem
## sends the companions home.
signal sleep_started
## The night has passed behind closed eyes, `hours` of game time; the clock
## stands at the morning already: ValleyLoop. BrewHouse lets the hours go by.
signal night_slept(hours: float)
## The game has been written to the save of `slot` ("" for a file of a tool):
## SaveService.
signal game_saved(slot: String)
## An order of the board is taken, given up or delivered (`coins` paid):
## BrewHouse. SaveService saves soon.
signal order_taken(order_id: String)
signal order_dropped(order_id: String)
signal order_delivered(order_id: String, coins: int)
## The batch of the brewing day has come to another stage (BrewBatch.stage):
## BrewHouse. SaveService saves soon.
signal brew_stage_changed(stage: String)
## The player has walked into another zone (ValleyZones; "" for the open
## valley): ValleyLoop.
signal zone_changed(zone: String)
