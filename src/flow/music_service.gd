extends Node
## The music of the game (docs/LOOP.md, «Музыка»), on the bus Music: the
## player sets its volume (GameSettings). GameFlow owns the service; it
## hears each move of the game (GameEvents.game_state_changed, follow). The menu's track plays round and
## round in the main menu; in the game the valley's tracks take turns, each
## once, with a silence between them. A loading screen is silent. The pause
## turns the music down, and the game turns it back up. A change of track
## cross-fades over `fade` seconds. The music plays on in the pause.

const GAME_FLOW = preload("res://src/flow/game_flow.gd")
const MENU_TRACK := "res://assets/audio/music/bards_tale.ogg"
const VALLEY_TRACKS: Array[String] = [
	"res://assets/audio/music/old_tower_inn.ogg",
	"res://assets/audio/music/kings_feast.ogg",
]
## Seconds of a cross-fade.
const FADE := 2.5
## Seconds of silence between two tracks of the valley, the least and the most.
const VALLEY_GAP := Vector2(40.0, 120.0)
## The music in the pause, dB under its full loudness.
const PAUSED_DB := -8.0
const SILENT_DB := -60.0

## Seconds of a cross-fade; 0 changes the track at once (tests).
var fade := FADE
## Seconds of silence between two tracks of the valley; tests give zero.
var valley_gap := VALLEY_GAP
## The track that plays or fades in; "" for silence.
var track := ""
## The two players the cross-fade passes between; `players[playing]` holds `track`.
var players: Array[AudioStreamPlayer] = []
var playing := 0
## The valley's track that comes next (VALLEY_TRACKS index).
var next_valley := 0
## The silence between the valley's tracks; it waits while the game stands.
var gap: Timer
var _state := &""
var _tweens: Array[Tween] = [null, null]

func _ready() -> void:
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Player%d" % index
		player.bus = AudioBuses.MUSIC
		player.volume_db = SILENT_DB
		player.finished.connect(_finished.bind(player))
		add_child(player)
		players.append(player)
	gap = Timer.new()
	gap.name = "Gap"
	gap.one_shot = true
	gap.process_mode = Node.PROCESS_MODE_PAUSABLE
	gap.timeout.connect(_play_valley)
	add_child(gap)
	GameEvents.game_state_changed.connect(follow)

## The game moved to `state` (a state of GameFlow).
func follow(state: StringName, _previous := &"") -> void:
	var previous := _state
	_state = state
	match state:
		GAME_FLOW.MENU:
			gap.stop()
			_play(MENU_TRACK)
		GAME_FLOW.LOADING:
			gap.stop()
			_play("")
		GAME_FLOW.PLAYING:
			if previous == GAME_FLOW.PAUSED:
				_fade_to(players[playing], _loudness())
			elif track.is_empty() and gap.is_stopped():
				_play_valley()
		GAME_FLOW.PAUSED:
			_fade_to(players[playing], _loudness())

## The track that plays now, at full loudness or in the pause.
func _loudness() -> float:
	return PAUSED_DB if _state == GAME_FLOW.PAUSED else 0.0

func _play_valley() -> void:
	if _state != GAME_FLOW.PLAYING and _state != GAME_FLOW.PAUSED:
		return
	_play(VALLEY_TRACKS[next_valley])
	next_valley = (next_valley + 1) % VALLEY_TRACKS.size()

## Cross-fades from the track that plays to `path` ("" for silence).
func _play(path: String) -> void:
	if path == track:
		return
	track = path
	_fade_to(players[playing], SILENT_DB, true)
	if path.is_empty():
		return
	playing = 1 - playing
	var player := players[playing]
	var stream := load(path) as AudioStreamOggVorbis
	stream.loop = path == MENU_TRACK
	player.stream = stream
	player.volume_db = SILENT_DB
	player.play()
	_fade_to(player, _loudness())

## Takes `player` to `volume_db` over `fade` seconds; `then_stop` stops it there.
func _fade_to(player: AudioStreamPlayer, volume_db: float, then_stop := false) -> void:
	var index := players.find(player)
	if _tweens[index] != null:
		_tweens[index].kill()
		_tweens[index] = null
	if fade <= 0.0 or not player.playing:
		player.volume_db = volume_db
		if then_stop:
			player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", volume_db, fade)
	if then_stop:
		tween.tween_callback(player.stop)
	_tweens[index] = tween

## A track of the valley came to its end: a silence, then the next one.
func _finished(player: AudioStreamPlayer) -> void:
	if player != players[playing] or track == MENU_TRACK or track.is_empty():
		return
	track = ""
	var seconds := randf_range(valley_gap.x, valley_gap.y)
	if seconds <= 0.0:
		_play_valley()
	else:
		gap.start(seconds)
