extends RefCounted
## Touch state stays separate from physical keys, so releasing one never sticks the other.
var movement := Vector2.ZERO
var held: Dictionary = {}

func reset() -> void:
	movement = Vector2.ZERO
	held.clear()

func pressed(action: String) -> bool:
	return bool(held.get(action,false))

func _number(data: Dictionary, key: String) -> float:
	var value: Variant = data.get(key,0.0)
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return 0.0

func handle(game: Node, action: String, data: Dictionary) -> void:
	if not game.mobile_controls:
		return
	if action == "release":
		reset()
		return
	if action == "sketch":
		reset()
		game.begin_sketch()
		return
	if action == "pause":
		reset()
		game.toggle_pause()
		return
	if action == "bestiary":
		reset()
		if game.bestiary_open:
			game.close_bestiary()
		else:
			game.open_bestiary()
		return
	if game.state != "dive" or game.entry_active or game.bestiary_open or game.gm_menu_open or game.new_game_confirmation:
		reset()
		return
	match action:
		"move":
			movement = Vector2(_number(data,"x"),_number(data,"y")).limit_length()
		"look":
			game.yaw -= clampf(_number(data,"dx"),-180,180)*.004
			game.pitch = clampf(game.pitch-clampf(_number(data,"dy"),-180,180)*.004,-1.25,1.10)
		"ascend", "descend", "boost", "stealth":
			held[action] = data.get("pressed") == true
		"shoot": game.shoot()
		"knife": game.diver_knife.swing(game)
		"interact": game.interact()
