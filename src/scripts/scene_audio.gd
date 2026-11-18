extends Node

const FADE_SECONDS := 0.8
const MUSIC_VOLUME_DB := -10.0
const UNDERWATER_VOLUME_DB := -8.0
const MENU_MUSIC = preload("res://assets/audio/main_menu_bgm.mp3")
const RESTAURANT_MUSIC = preload("res://assets/audio/restaurant_bgm.mp3")
const UNDERWATER_LOOP = preload("res://assets/audio/underwater_loop.wav")

var music_player: AudioStreamPlayer
var underwater_player: AudioStreamPlayer
var music_current := ""
var music_target := ""
var fade_remaining := 0.0
var music_tracks: Dictionary = {}
var underwater_active := false

func _ready() -> void:
	for entry: Array in [["dock", MENU_MUSIC], ["restaurant", RESTAURANT_MUSIC]]:
		var track: AudioStreamMP3 = entry[1].duplicate()
		track.loop = true
		track.loop_offset = 0.0
		music_tracks[entry[0]] = track
	music_player = AudioStreamPlayer.new()
	music_player.name = "SceneMusic"
	# Browser-owned sample playback keeps mixing while UI/model rebuilds occupy
	# the single-threaded Web engine. The exporter enables native full-track loops.
	music_player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web") else AudioServer.PLAYBACK_TYPE_STREAM
	music_player.volume_db = MUSIC_VOLUME_DB
	add_child(music_player)
	underwater_player = AudioStreamPlayer.new()
	underwater_player.name = "UnderwaterAmbience"
	# Web Sample playback restarts its source from an ended callback. Streaming
	# loops inside the mixer instead, preserving the supplied seamless boundary.
	underwater_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	underwater_player.volume_db = UNDERWATER_VOLUME_DB
	var ambience: AudioStreamWAV = UNDERWATER_LOOP.duplicate()
	ambience.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ambience.loop_begin = 0
	ambience.loop_end = roundi(ambience.get_length() * ambience.mix_rate)
	underwater_player.stream = ambience
	add_child(underwater_player)

func update_scene(scene: String, muted: bool, submerged: bool, delta: float) -> void:
	var target := ""
	if scene == "dock":
		target = "dock"
	elif scene in ["restaurant", "service", "service_paused"]:
		target = "restaurant"
	if target != music_target:
		music_target = target
		if music_current != "" and music_current != music_target and fade_remaining <= 0.0:
			fade_remaining = FADE_SECONDS
	if music_current == music_target:
		fade_remaining = 0.0
		music_player.volume_db = MUSIC_VOLUME_DB
	elif music_current != "":
		fade_remaining = maxf(0.0, fade_remaining - delta)
		music_player.volume_linear = db_to_linear(MUSIC_VOLUME_DB) * fade_remaining / FADE_SECONDS
		if fade_remaining <= 0.00001:
			music_player.stop()
			music_current = ""
	if music_current == "" and music_target != "":
		music_current = music_target
		music_player.stream = music_tracks[music_current]
		music_player.volume_db = MUSIC_VOLUME_DB
		music_player.play()
	var underwater := submerged and scene in ["dive", "paused", "sketch"]
	if underwater:
		if not underwater_active:
			underwater_player.play()
	elif underwater_active:
		underwater_player.stop()
	underwater_active = underwater
	# Changing stream_paused repeatedly restarts Web sample playback. Only write
	# it on a real mute change, preserving the playhead and seamless loop.
	for player: AudioStreamPlayer in [music_player, underwater_player]:
		if player.stream_paused != muted:
			player.stream_paused = muted
