extends Node
## Browser lifecycle integration. The desktop build never creates this node.
var game: Node
var _lock_callback: JavaScriptObject
var _visibility_callback: JavaScriptObject
var _pause_callback: JavaScriptObject

func _ready() -> void:
	_lock_callback = JavaScriptBridge.create_callback(_on_pointer_lock)
	_visibility_callback = JavaScriptBridge.create_callback(_on_visibility)
	_pause_callback = JavaScriptBridge.create_callback(_on_pause)
	var document = JavaScriptBridge.get_interface("document")
	document.addEventListener("pointerlockchange", _lock_callback)
	document.addEventListener("visibilitychange", _visibility_callback)
	document.addEventListener("tide-pause", _pause_callback)
	JavaScriptBridge.eval("window.tideGameReady = true; document.dispatchEvent(new Event('tide-ready'));", true)
	if not OS.is_userfs_persistent():
		game.tell("浏览器未允许保存进度；请使用普通窗口并允许网站存储。", 12)

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
