extends Node
## What happens in the game, told to whoever listens (autoload GameEvents).
## A system emits a signal here instead of calling another system only to tell
## it the news; a system that needs an answer calls the other one directly.
## Each signal names who emits it and who listens to it now (docs/LOOP.md,
## «События»). A change that must not be lost is not news: its system asks
## SaveService.save_soon() itself.

# Others emit these signals: none is emitted here.
@warning_ignore_start("unused_signal")

## The game has gone from state `previous` to `state` (GameFlow.BOOT, MENU,
## LOADING, PLAYING, PAUSED): GameFlow. MusicService plays what the state
## asks for; SaveNotice lets its line's time run in the game and the menu.
signal game_state_changed(state: StringName, previous: StringName)
## The player has lain down in a bed; the eyes close: ValleyLoop. CampSystem
## sends the companions home.
signal sleep_started
## The night has passed behind closed eyes, `hours` of game time; the clock
## stands at the morning already, the brewery has lived the hours
## (GameClock.advanced): ValleyLoop. VillagerPresence puts everybody where the
## morning has them.
signal night_slept(hours: float)
## The game has been written to the save of `slot` ("" for a file of a tool):
## SaveService. SaveNotice takes away its line of a save not written.
signal game_saved(slot: String)
## The save of `slot` ("" for a file of a tool) has a trouble the player must
## know of (SaveService.FROM_BACKUP, STARTED_ANEW, NOT_SAVED): SaveService.
## SaveNotice shows it.
signal save_trouble(trouble: StringName, slot: String)
## The player has walked into a way out of the region (RegionDef.exits):
## RegionDoors. GameFlow takes them into the region it leads to.
signal region_exit_reached(exit: RegionExit)
