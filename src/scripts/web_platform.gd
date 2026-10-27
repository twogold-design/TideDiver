extends Node
## Browser lifecycle integration. The desktop build never creates this node.
var game: Node
var _lock_callback: JavaScriptObject
var _visibility_callback: JavaScriptObject
var _pause_callback: JavaScriptObject
const MAX_3D_PIXELS := 1800000.0
var _stats_time := 0.0
var _render_scene := ""

func _ready() -> void:
	_lock_callback = JavaScriptBridge.create_callback(_on_pointer_lock)
	_visibility_callback = JavaScriptBridge.create_callback(_on_visibility)
	_pause_callback = JavaScriptBridge.create_callback(_on_pause)
	var document = JavaScriptBridge.get_interface("document")
	document.addEventListener("pointerlockchange", _lock_callback)
	document.addEventListener("visibilitychange", _visibility_callback)
	document.addEventListener("tide-pause", _pause_callback)
	get_viewport().size_changed.connect(_apply_render_budget)
	_apply_render_budget()
	JavaScriptBridge.eval("window.tideGameReady = true; document.dispatchEvent(new Event('tide-ready'));", true)
	if not OS.is_userfs_persistent():
		game.tell("浏览器未允许保存进度；请使用普通窗口并允许网站存储。", 12)

func _apply_render_budget() -> void:
	# Limit only the 3D buffer. UI glyphs keep the native display resolution.
	var pixels := Vector2(get_window().size)
	var area := maxf(1.0, pixels.x * pixels.y)
	_render_scene = "restaurant" if game.state in ["restaurant", "service", "service_paused"] else "ocean"
	# The smaller restaurant scene is faster without the extra upscale render pass
	# at normal desktop sizes; only budget it on very large/high-DPI canvases.
	var budget: float = (area if area <= 4500000.0 else 3000000.0) if _render_scene == "restaurant" else MAX_3D_PIXELS
	get_viewport().scaling_3d_scale = minf(1.0, sqrt(budget / area))
	_publish_render_stats()

func _process(delta: float) -> void:
	var scene: String = "restaurant" if game.state in ["restaurant", "service", "service_paused"] else "ocean"
	if scene != _render_scene:
		_apply_render_budget()
	_stats_time += delta
	if _stats_time >= 1.0:
		_stats_time = 0.0
		_publish_render_stats()

func _publish_render_stats() -> void:
	var pixels := Vector2(get_window().size)
	var render_scale := get_viewport().scaling_3d_scale
	var stats := {"scale3d": render_scale, "pixels3d": pixels.x * pixels.y * render_scale * render_scale,
		"fps": Engine.get_frames_per_second(), "physicsMs": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
		"drawCalls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"state": game.state, "oxygen": game.oxygen, "rescueResult": game.rescue_result_visible}
	JavaScriptBridge.eval("window.tideRenderStats = " + JSON.stringify(stats) + ";", true)

func _on_pointer_lock(_args: Array) -> void:
	var document = JavaScriptBridge.get_interface("document")
	if document.pointerLockElement == null and game.state == "dive":
		game.toggle_pause()

func _on_visibility(_args: Array) -> void:
	if JavaScriptBridge.get_interface("document").hidden:
		_pause_active_game()

func _on_pause(_args: Array) -> void:
	_pause_active_game()

func _pause_active_game() -> void:
	if game.state in ["dive", "service"]:
		game.toggle_pause()

func _exit_tree() -> void:
	var document = JavaScriptBridge.get_interface("document")
	document.removeEventListener("pointerlockchange", _lock_callback)
	document.removeEventListener("visibilitychange", _visibility_callback)
	document.removeEventListener("tide-pause", _pause_callback)
