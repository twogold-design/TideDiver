extends SceneTree
## Exercise real controls across compact desktop, touch and expanded layouts.
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void: pass
	func save_game() -> void: pass

var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for index in range(4):
		await process_frame

func check_buttons(panel: Node, description: String) -> void:
	var rects: Array[Rect2] = []
	var labels: Array[String] = []
	for child in panel.get_children():
		if not child is Button or not child.is_visible_in_tree() or child.is_queued_for_deletion():
			continue
		var rect: Rect2 = child.get_viewport_transform() * child.get_global_transform() * Rect2(Vector2.ZERO,child.size)
		check(Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(rect),description + " stays inside screen: " + child.text)
		check(rect.size.y >= 43.0,description + " keeps readable control height: " + child.text)
		for previous in range(rects.size()):
			check(not rect.intersects(rects[previous]),description + " has no overlap: " + child.text + " / " + labels[previous])
		rects.append(rect)
		labels.append(child.text)
	check(not rects.is_empty(),description + " has reachable actions")

func check_pages(panel: Node, description: String) -> void:
	var pages: int = maxi(1,ceili(float(panel._mobile_actions.size())/panel._mobile_page_size))
	for index in range(pages):
		check_buttons(panel,description + " page " + str(index+1))
		if index < pages-1:
			panel._mobile_turn(1)
			await settle()
	if pages > 1:
		panel._mobile_turn(1-pages)
		await settle()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await settle()
	for dimensions: Vector2i in [Vector2i(938,480),Vector2i(667,300)]:
		root.size = dimensions
		await settle()
		check(game.hud.compact_enabled() and not game.mobile_controls,"Small desktop uses compact UI without enabling touch input")
		game.hud.rebuild()
		await settle()
		await check_pages(game.hud,"Dock " + str(dimensions))
		if game.BuildMode.GM_ENABLED:
			check(game.hud.buttons.any(func(button: Button) -> bool: return button.text.contains("GM")),"Development dock exposes a touch-accessible GM entry")
			game.open_gm_menu()
			await settle()
			if "--capture-gm" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://../.runtime/gm-ui-%dx%d.png" % [dimensions.x,dimensions.y])
			await check_pages(game.hud,"GM " + str(dimensions))
			check(game.hud.buttons.size() == 14,"GM has six destinations, both entry methods, air toggle and return")
			game.close_gm_menu()
			await settle()
		game.request_new_game()
		await settle()
		check_buttons(game.hud,"New game confirmation " + str(dimensions))
		game.cancel_new_game()
		game.open_bestiary()
		await settle()
		check_buttons(game.hud.bestiary_ui,"Bestiary " + str(dimensions))
		game.close_bestiary()
		game.open_restaurant()
		await settle()
		await check_pages(game.hud.restaurant_ui,"Restaurant " + str(dimensions))
		game.progress.renovation.clean = true
		game.enter_layout()
		await settle()
		await check_pages(game.hud.restaurant_ui.layout_ui,"Layout " + str(dimensions))
		game.toggle_layout_panel()
		await settle()
		check_buttons(game.hud.restaurant_ui.layout_ui,"Collapsed layout " + str(dimensions))
		game.cancel_layout()
		game.return_to_dock()
		await settle()
	root.size = Vector2i(1440,900)
	await settle()
	check(not game.hud.compact_enabled(),"Growing desktop restores expanded UI automatically")
	check(game.hud._mobile_actions.is_empty(),"Growing desktop removes compact controls")
	game.mobile_controls = true
	game.hud.rebuild()
	await settle()
	check(game.hud.compact_enabled(),"Touch devices retain compact UI at large resolution")
	check_buttons(game.hud,"Touch dock")
	if game.BuildMode.GM_ENABLED:
		game.open_gm_menu()
		await settle()
		await check_pages(game.hud,"Touch GM")
		game.close_gm_menu()
	print("SMALL_SCREEN_CHECKS: %d, failures: %d" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
