extends SceneTree
## Resizing preserves the complete original interface on desktop and touch devices.
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

func check_panel(panel: Node, description: String) -> void:
	check(not panel.compact_enabled(),description + " retains the full layout")
	check(panel._mobile_actions.is_empty(),description + " has no replacement pagination")
	var rects: Array[Rect2] = []
	var labels: Array[String] = []
	for child in panel.get_children():
		if not child is Button or not child.is_visible_in_tree() or child.is_queued_for_deletion():
			continue
		check(child.has_meta("layout_anchor"),description + " preserves original anchoring: " + child.text)
		var rect: Rect2 = child.get_viewport_transform() * child.get_global_transform() * Rect2(Vector2.ZERO,child.size)
		check(Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(rect),description + " stays inside screen: " + child.text)
		check(rect.size.y >= 1.0,description + " retains a nonzero control: " + child.text)
		for previous in range(rects.size()):
			check(not rect.intersects(rects[previous]),description + " has no overlap: " + child.text + " / " + labels[previous])
		rects.append(rect)
		labels.append(child.text)
	check(not rects.is_empty(),description + " has reachable actions")

func press(panel: Node, fragment: String) -> bool:
	for child in panel.get_children():
		if child is Button and child.is_visible_in_tree() and not child.is_queued_for_deletion() and child.text.contains(fragment):
			check(not child.disabled,"Action is enabled: " + fragment)
			child.pressed.emit()
			return true
	check(false,"Action exists: " + fragment)
	return false

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
	for touch: bool in [false,true]:
		game.mobile_controls = touch
		for dimensions: Vector2i in [Vector2i(480,270),Vector2i(667,300),Vector2i(938,480),Vector2i(1000,1000),Vector2i(1440,900),Vector2i(1920,1080)]:
			root.size = dimensions
			game.hud.rebuild()
			await settle()
			var context := ("Touch " if touch else "Desktop ") + str(dimensions) + " "
			check_panel(game.hud,context + "dock")
			if game.BuildMode.GM_ENABLED:
				press(game.hud,"GM 自选潜点")
				await settle()
				check(game.gm_menu_open,"GM opens through the original button")
				check_panel(game.hud,context + "GM")
				check(game.hud.buttons.size() == 14,"GM exposes every destination and option at once")
				game.close_gm_menu()
			press(game.hud,"重新开始游戏")
			await settle()
			check_panel(game.hud,context + "new game confirmation")
			press(game.hud,"保留进度")
			press(game.hud,"海洋图鉴")
			await settle()
			check_panel(game.hud.bestiary_ui,context + "bestiary")
			check(game.hud.bestiary_ui.preview_image.visible,"Journal retains its specimen view")
			press(game.hud.bestiary_ui,"返回")
			press(game.hud,"我的餐厅")
			await settle()
			check(game.state == "restaurant","Original dock button enters the restaurant")
			check_panel(game.hud.restaurant_ui,context + "restaurant")
			game.progress.renovation.clean = true
			game.enter_layout()
			await settle()
			check_panel(game.hud.restaurant_ui.layout_ui,context + "layout")
			game.toggle_layout_panel()
			await settle()
			check_panel(game.hud.restaurant_ui.layout_ui,context + "collapsed layout")
			game.cancel_layout()
			for id in ["clean","kitchen","tables"]:
				game.progress.renovation[id] = true
			game.progress.inventory.orange = 4
			game.progress.last_service_day = -1
			game.menu_plan = {"orange":2}
			game.start_service()
			check(game.state == "service","Prepared restaurant starts actual service")
			game._update_service(.3)
			await settle()
			check_panel(game.hud.restaurant_ui,context + "service")
			game.toggle_pause()
			await settle()
			check_panel(game.hud.restaurant_ui,context + "paused service")
			press(game.hud.restaurant_ui,"提前打烊")
			await settle()
			check_panel(game.hud.restaurant_ui,context + "service summary")
			press(game.hud.restaurant_ui,"收好账单")
			press(game.hud.restaurant_ui,"返回码头")
			game.start_dive(false,false)
			game.toggle_pause()
			await settle()
			check_panel(game.hud,context + "dive pause")
			press(game.hud,"继续探索")
			check(game.state == "dive","Original pause action resumes diving")
			game.finish_dive(false)
			await settle()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("SMALL_SCREEN_CHECKS: %d, failures: %d" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
