extends SceneTree
## Scene routing, fade timing and underwater ambience lifecycle.
const SceneAudio = preload("res://scripts/scene_audio.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func run() -> void:
	var audio = SceneAudio.new()
	root.add_child(audio)
	audio.update_scene("dock", false, false, 0.0)
	var menu_stream: AudioStream = audio.music_player.stream
	check(audio.music_player.playing and menu_stream != null, "Main menu starts its own music player")
	check(menu_stream.loop, "Main menu music loops in the decoder")
	check(audio.music_player.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Music uses mixer streaming rather than Web ended-callback looping")
	check(not audio.underwater_player.playing, "No underwater ambience on shore")
	var normal_volume: float = audio.music_player.volume_linear
	audio.update_scene("restaurant", false, false, 0.25)
	check(audio.music_player.stream == menu_stream, "Outgoing track remains assigned during the fade")
	check(audio.music_player.volume_linear < normal_volume and audio.music_player.volume_linear > 0.0, "Music audibly fades before switching")
	audio.update_scene("restaurant", false, false, 0.24)
	check(audio.music_player.stream == menu_stream, "The fade does not end before half a second")
	audio.update_scene("restaurant", false, false, 0.011)
	var restaurant_stream: AudioStream = audio.music_player.stream
	check(restaurant_stream != menu_stream and audio.music_player.playing, "Restaurant music starts after the 0.5 second outgoing fade")
	check(restaurant_stream.loop, "Restaurant music loops in the decoder")
	for state: String in ["service", "service_paused", "restaurant"]:
		audio.update_scene(state, false, false, 1.0)
		check(audio.music_player.stream == restaurant_stream and audio.music_player.playing, "Restaurant music remains playing in "+state)
	audio.update_scene("dock", false, false, 0.501)
	check(audio.music_current == "dock" and audio.music_player.playing, "Returning to dock selects the main music after its outgoing fade")
	menu_stream = audio.music_player.stream
	audio.update_scene("dock", true, false, 0.0)
	check(audio.music_player.stream_paused, "Mute silences the current music immediately")
	audio.update_scene("dock", false, false, 0.0)
	check(not audio.music_player.stream_paused and audio.music_player.stream == menu_stream, "Unmute resumes the same menu stream")
	await test_repeated_mute(audio, audio.music_player, "dock", false)
	# A pending switch must never start a stale destination after another action.
	audio.update_scene("restaurant", false, false, 0.20)
	audio.update_scene("dive", false, false, 0.501)
	check(not audio.music_player.playing, "Rapid menu-to-restaurant-to-dive switching never leaves menu music playing")
	check(not audio.underwater_player.playing, "Starting a dive above water waits for immersion")
	audio.update_scene("dive", false, true, 0.0)
	check(audio.underwater_player.playing, "Immersion immediately starts the underwater loop")
	var sea_stream: AudioStream = audio.underwater_player.stream
	check(sea_stream != menu_stream and sea_stream != restaurant_stream, "Underwater ambience uses an independent audio stream")
	check(sea_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD if sea_stream is AudioStreamWAV else sea_stream.loop, "Underwater ambience uses direct decoder looping")
	check(audio.underwater_player.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Underwater ambience loops within the mixer without a Web source restart")
	check(sea_stream is AudioStreamWAV and sea_stream.loop_begin == 0 and sea_stream.loop_end == 1781328, "The full supplied underwater loop retains its exact 1781328 sample boundary")
	check(absf(sea_stream.get_length() - 37.111) < 0.00001, "Underwater conversion preserves the exact 37.111 second duration")
	for state: String in ["paused", "sketch", "dive"]:
		audio.update_scene(state, false, true, 0.1)
		check(audio.underwater_player.playing and audio.underwater_player.stream == sea_stream, "The existing underwater loop survives "+state)
	audio.update_scene("dive", true, true, 0.0)
	check(audio.underwater_player.stream_paused or not audio.underwater_player.playing, "Mute also silences underwater ambience")
	audio.update_scene("dive", false, true, 0.0)
	check(audio.underwater_player.playing and not audio.underwater_player.stream_paused, "Unmute restores underwater ambience")
	await test_repeated_mute(audio, audio.underwater_player, "dive", true)
	audio.update_scene("rescuing", false, false, 0.0)
	check(not audio.underwater_player.playing, "Leaving the dive for rescue stops underwater audio immediately")
	audio.update_scene("dive", false, true, 0.0)
	audio.update_scene("dock", false, false, 0.0)
	check(not audio.underwater_player.playing and audio.music_current == "dock", "Normal return stops underwater audio and restores menu music")
	audio.update_scene("restaurant", false, false, 0.1)
	audio.update_scene("dock", false, false, 0.501)
	check(audio.music_player.playing and audio.music_current == "dock", "Reversing a pending music switch does not play the abandoned destination")
	audio.free()
	await test_main_scene()
	await process_frame
	print("%s: Tide Diver scene audio (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func test_repeated_mute(audio: Node, player: AudioStreamPlayer, scene: String, submerged: bool) -> void:
	player.seek(4.0)
	await create_timer(0.06).timeout
	var stream: AudioStream = player.stream
	var playback: AudioStreamPlayback = player.get_stream_playback()
	audio.update_scene(scene, true, submerged, 0.0)
	await create_timer(0.06).timeout
	var paused_position: float = player.get_playback_position()
	for frame in range(120):
		audio.update_scene(scene, true, submerged, 1.0 / 60.0)
	check(player.stream == stream and player.get_stream_playback() == playback and player.stream_paused, "Repeated mute updates retain the active "+scene+" stream and playback object")
	check(paused_position >= 4.0 and absf(player.get_playback_position() - paused_position) < 0.01, "Repeated muted frames preserve the "+scene+" playhead")
	for frame in range(120):
		audio.update_scene(scene, false, submerged, 1.0 / 60.0)
	check(player.stream == stream and player.get_stream_playback() == playback and not player.stream_paused, "Repeated unmuted updates do not recreate "+scene+" playback")
	await create_timer(0.06).timeout
	check(player.get_playback_position() >= paused_position, "Resumed "+scene+" playback continues forward instead of restarting")

func test_main_scene() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	check(game.scene_audio.music_current == "dock", "Main scene setup starts menu music")
	game.open_bestiary()
	game._physics_process(0.1)
	check(game.scene_audio.music_current == "dock", "Menu encyclopedia retains menu music")
	game.close_bestiary()
	game.open_restaurant()
	game._physics_process(0.25)
	check(game.scene_audio.music_current == "dock", "Actual restaurant entry starts an outgoing fade")
	game._physics_process(0.251)
	check(game.scene_audio.music_current == "restaurant", "Actual restaurant entry completes the music switch")
	game.return_to_dock()
	game._physics_process(0.501)
	game.start_dive(true, false)
	game._physics_process(0.01)
	check(not game.scene_audio.underwater_player.playing, "The boat launch does not start underwater sound while above water")
	game._update_entry(2.0)
	game._physics_process(0.0)
	check(game.scene_audio.underwater_player.playing, "Animated water immersion starts the actual ambience")
	game._update_entry(3.2)
	game.toggle_pause()
	game._physics_process(0.0)
	check(game.scene_audio.underwater_player.playing, "Pausing a submerged dive keeps its environmental sound")
	game.toggle_pause()
	game.open_bestiary()
	game.muted = true
	game._physics_process(0.0)
	check(game.scene_audio.underwater_player.stream_paused, "Encyclopedia early return does not bypass audio mute")
	game.muted = false
	game._physics_process(0.0)
	game.close_bestiary()
	game.player.position.y = 0.1
	game._physics_process(0.0)
	check(game.scene_audio.underwater_player.playing, "Approaching the pickup boat does not restart or stop the underwater loop")
	game.finish_dive()
	game._physics_process(0.0)
	check(not game.scene_audio.underwater_player.playing, "Returning from a real dive stops underwater sound")
	game.start_dive(false, false)
	game._physics_process(0.0)
	check(game.scene_audio.underwater_player.playing, "Direct underwater testing starts ambience without an entry animation")
	game.oxygen = 0.0
	game.finish_dive(true)
	game._physics_process(0.0)
	check(not game.scene_audio.underwater_player.playing and not game.underwater_audio_started, "Rescue clears the underwater audio latch")
	game.free()
