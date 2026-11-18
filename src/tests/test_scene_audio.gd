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
	var expected_playback: AudioServer.PlaybackType = AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web") else AudioServer.PLAYBACK_TYPE_STREAM
	check(audio.music_player.playback_type == expected_playback, "Web music uses independent browser playback while native music uses the mixer")
	check(not audio.underwater_player.playing, "No underwater ambience on shore")
	var normal_volume: float = audio.music_player.volume_linear
	audio.update_scene("restaurant", false, false, 0.25)
	check(audio.music_player.stream == menu_stream, "Outgoing track remains assigned during the fade")
	check(audio.music_player.volume_linear < normal_volume and audio.music_player.volume_linear > 0.0, "Music audibly fades before switching")
	audio.update_scene("restaurant", false, false, 0.549)
	check(audio.music_player.stream == menu_stream and audio.music_player.playing and audio.music_player.volume_linear > 0.0, "The outgoing music is still playing at 0.799 seconds")
	audio.update_scene("restaurant", false, false, 0.002)
	var restaurant_stream: AudioStream = audio.music_player.stream
	check(restaurant_stream != menu_stream and audio.music_player.playing, "Restaurant music starts at 0.801 seconds after the 0.8 second outgoing fade")
	check(restaurant_stream.loop, "Restaurant music loops in the decoder")
	for state: String in ["service", "service_paused", "restaurant"]:
		audio.update_scene(state, false, false, 1.0)
		check(audio.music_player.stream == restaurant_stream and audio.music_player.playing, "Restaurant music remains playing in "+state)
	audio.update_scene("dock", false, false, 0.801)
	check(audio.music_current == "dock" and audio.music_player.playing, "Returning to dock selects the main music after its outgoing fade")
	menu_stream = audio.music_player.stream
	audio.update_scene("dock", true, false, 0.0)
	check(audio.music_player.stream_paused, "Mute silences the current music immediately")
	audio.update_scene("dock", false, false, 0.0)
	check(not audio.music_player.stream_paused and audio.music_player.stream == menu_stream, "Unmute resumes the same menu stream")
	await test_repeated_mute(audio, audio.music_player, "dock", false)
	# A pending switch must never start a stale destination after another action.
	audio.update_scene("restaurant", false, false, 0.20)
	audio.update_scene("dive", false, false, 0.801)
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
	audio.update_scene("dock", false, false, 0.801)
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

func press_panel_button(panel: Node, label: String) -> bool:
	for button: Button in panel.buttons:
		if button.text == label and not button.disabled and button.is_visible_in_tree():
			button.pressed.emit()
			return true
	check(false,"A visible enabled UI button exists: " + label)
	return false

func check_restaurant_playback(game: Node, stream: AudioStream, playback: AudioStreamPlayback, label: String) -> void:
	game._physics_process(0.016)
	var player: AudioStreamPlayer = game.scene_audio.music_player
	check(player.playing and player.stream == stream and player.get_stream_playback() == playback and game.scene_audio.music_current == "restaurant" and game.scene_audio.fade_remaining == 0.0, label + " preserves the existing restaurant music playback")

func test_restaurant_buttons(game: Node) -> void:
	var audio: Node = game.scene_audio
	var stream: AudioStream = audio.music_player.stream
	var playback: AudioStreamPlayback = audio.music_player.get_stream_playback()
	game.progress.coins = 1000
	game.progress.inventory.orange = 5
	game.hud.rebuild()
	var panel: Node = game.hud.restaurant_ui
	press_panel_button(panel,"下一页")
	check(panel.warehouse_page == 1,"Actual warehouse next-page button changes the page")
	check_restaurant_playback(game,stream,playback,"Warehouse next page")
	press_panel_button(panel,"上一页")
	check(panel.warehouse_page == 0,"Actual warehouse previous-page button restores the page")
	check_restaurant_playback(game,stream,playback,"Warehouse previous page")
	for price: int in [40,100,70]:
		press_panel_button(panel,"%d G · 施工" % price)
		check_restaurant_playback(game,stream,playback,"Restaurant renovation %d" % price)
	press_panel_button(panel,"备菜菜单")
	check(game.restaurant_tab == "menu","Actual tab button opens the preparation menu")
	check_restaurant_playback(game,stream,playback,"Preparation menu tab")
	press_panel_button(panel,"+")
	check(int(game.menu_plan.orange) == 1,"Actual menu quantity button adds a dish")
	check_restaurant_playback(game,stream,playback,"Changing a menu quantity")
	press_panel_button(panel,game.bestiary_button_label(true))
	check(game.bestiary_open,"Actual restaurant journal button opens the journal")
	check_restaurant_playback(game,stream,playback,"Restaurant journal")
	press_panel_button(game.hud.bestiary_ui,"返回 · B / Esc")
	check(not game.bestiary_open,"Actual journal return button closes the journal")
	check_restaurant_playback(game,stream,playback,"Journal return")
	press_panel_button(panel,"开门营业   →")
	check(game.state == "service","Actual opening button starts restaurant service")
	check_restaurant_playback(game,stream,playback,"Starting restaurant service")
	game.toggle_pause()
	check(game.state == "service_paused","Service can pause without leaving the restaurant")
	check_restaurant_playback(game,stream,playback,"Pausing restaurant service")
	press_panel_button(panel,"继续营业")
	check(game.state == "service","Actual resume button continues service")
	check_restaurant_playback(game,stream,playback,"Resuming restaurant service")
	press_panel_button(panel,"提前打烊")
	check(game.state == "restaurant" and game.summary_visible,"Actual closing button shows the restaurant settlement")
	check_restaurant_playback(game,stream,playback,"Restaurant settlement")
	press_panel_button(panel,"收好账单 · 继续整备")
	check_restaurant_playback(game,stream,playback,"Dismissing the settlement")
	await process_frame

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
	game._physics_process(0.549)
	check(game.scene_audio.music_current == "dock", "Actual restaurant transition keeps outgoing music until 0.799 seconds")
	game._physics_process(0.002)
	check(game.scene_audio.music_current == "restaurant", "Actual restaurant entry completes the music switch")
	await test_restaurant_buttons(game)
	game.return_to_dock()
	game._physics_process(0.801)
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
