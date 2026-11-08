extends Node
## Sound manager. Add as an AUTOLOAD called "Sound" (Project > Project Settings > Globals > Autoload),
## then from any script:   Sound.play("fold")
##
## Files live in res://music/. Each sound lists a few possible file names, so small spelling
## differences (bet_rasie / bet_raise) still work.

const DIR := "res://music/"
const FILES := {
	"raise":        ["bet_raise.mp3", "bet_rasie.mp3"],
	"check":        ["check_sound.mp3", "check.mp3"],
	"fold":         ["fold.mp3"],
	"time_reverse": ["time_reverse.mp3"],
	"heartbeat":    ["heartbeat.mp3", "heartbeat.mpa"],
	"music":        ["hotel_music.mp3"],
	"white_noise":  ["white_noise.mp3"],
	"draw":         ["draw_card.mp3"],
	"cig":          ["sig_sound.mp3", "cig_sound.mp3"],
	"flip":         ["cardflip.mp3", "card_flip.mp3"],
	"click":        ["button_click.mp3"],
	"exhale":       ["exhale.mp3"],
	"woodbreak":    ["woodbreak.mp3", "wood_break.mp3"],
	"shuffle":      ["shuffle.mp3", "card_shuffle.mp3", "draw_card.mp3"],   # falls back to the draw sound
}

## Extra loudness for particular sounds, in dB (+6 = about twice as loud, max about +24).
const BOOST := {
	"heartbeat": 12.0,
	"exhale": 18.0,
	"woodbreak": 6.0,
	"flip": 4.0,
	"click" : 6.0
}

@export var music_volume_db := -14.0        ## background music (0 = full, -80 = silent)
@export var sfx_volume_db := -4.0           ## all one-off sound effects
@export var white_noise_volume_db := -12.0
@export var cig_min_gap := 25.0             ## seconds between random cigarette sounds (shortest)
@export var cig_max_gap := 70.0             ## (longest)

var _streams := {}
var _music: AudioStreamPlayer
var _noise: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # keeps playing if you ever pause the game
	for key in FILES:
		_streams[key] = _load(key)

	_music = _looping("music", music_volume_db)
	_music.play()
	_noise = _looping("white_noise", -80.0)       # starts silent, faded in during the past view
	_cig_loop()


## Play a one-off sound effect. pitch_wobble makes repeats sound less robotic.
func play(key: String, volume_offset_db := 0.0, pitch_wobble := 0.06) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = sfx_volume_db + volume_offset_db + BOOST.get(key, 0.0)
	p.pitch_scale = randf_range(1.0 - pitch_wobble, 1.0 + pitch_wobble)
	p.set_meta("sound_key", key)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Fade out and stop a sound that's still playing (e.g. the heartbeat after the showdown).
func stop(key: String, fade_time := 0.6) -> void:
	for p in get_children():
		if p is AudioStreamPlayer and p.get_meta("sound_key", "") == key:
			var t := create_tween()
			t.tween_property(p, "volume_db", -60.0, fade_time)
			t.tween_callback(p.queue_free)


## Into the past: music dips, white noise fades in.
func enter_past() -> void:
	play("time_reverse")
	_fade(_music, music_volume_db - 14.0, 0.8)
	if _noise.stream:
		if not _noise.playing:
			_noise.play()
		_fade(_noise, white_noise_volume_db, 1.0)


## Back to the present: white noise fades out, music comes back.
func leave_past() -> void:
	_fade(_noise, -80.0, 0.8)
	_fade(_music, music_volume_db, 1.2)


# ---------------------------------------------------------------- internals

func _load(key: String) -> AudioStream:
	for name in FILES[key]:
		var path: String = DIR + name
		if ResourceLoader.exists(path):
			return load(path)
	push_warning("Sound missing: %s (looked for %s in %s)" % [key, FILES[key], DIR])
	return null


func _looping(key: String, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s: AudioStream = _streams.get(key)
	if s:
		s = s.duplicate()
		if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
			s.loop = true
		elif s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		p.stream = s
	p.volume_db = vol
	add_child(p)
	return p


func _fade(p: AudioStreamPlayer, to_db: float, time: float) -> void:
	if p == null:
		return
	create_tween().tween_property(p, "volume_db", to_db, time).set_trans(Tween.TRANS_SINE)


func _cig_loop() -> void:
	while true:
		await get_tree().create_timer(randf_range(cig_min_gap, cig_max_gap)).timeout
		play("cig", -6.0, 0.1)
