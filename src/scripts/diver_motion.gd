extends RefCounted
## Visual swimming follows local controls; currents and aiming keep their own transforms.
var motion_input := Vector3.ZERO
var phase: float = 0.0
var _boost: float = 0.0
var _rig: Node3D
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arms: Array[Node3D] = []

func setup(rig: Node3D) -> void:
	_rig = rig
	_legs.clear()
	_knees.clear()
	_arms.clear()
	for side: String in ["Left", "Right"]:
		_legs.append(rig.get_node("Leg" + side))
		_knees.append(rig.get_node("Leg" + side + "/Knee" + side))
		_arms.append(rig.get_node("Arm" + side))
	reset()

func reset() -> void:
	motion_input = Vector3.ZERO
	phase = 0.0
	_boost = 0.0
	if not is_instance_valid(_rig):
		return
	_rig.rotation = Vector3.ZERO
	for joint: Node3D in _legs + _knees + _arms:
		joint.rotation = Vector3.ZERO

func advance(delta: float, local_input: Vector3, boosting: bool) -> void:
	if not is_instance_valid(_rig):
		return
	var dt: float = maxf(0.0, delta)
	# Exponential blending keeps changes smooth at different browser frame rates.
	var blend: float = 1.0 - exp(-dt * 8.0)
	motion_input = motion_input.lerp(local_input.limit_length(), blend)
	_boost = move_toward(_boost, 1.0 if boosting else 0.0, dt * 5.0)
	phase = fposmod(phase + dt * lerpf(5.5, 10.0, _boost), TAU)
	var effort: float = minf(motion_input.length(), 1.0)
	var strafe: float = motion_input.x
	var lateral: float = absf(strafe)
	var reverse: float = maxf(0.0, motion_input.z)
	var wave: float = sin(phase)
	var sweep: float = 0.5 + 0.5 * wave
	# Bank into side strokes, lift the chest when backing up, and keep the aim heading.
	_rig.rotation = Vector3(reverse * 0.20, 0, -strafe * 0.26)
	for index in range(2):
		var side: float = -1.0 if index == 0 else 1.0
		var flutter: float = sin(phase + index * PI) * lerpf(0.055, 0.32, effort)
		var hip := Vector3.ZERO
		hip.x = flutter * (1.0 - reverse) * (1.0 - lateral * 0.35)
		hip.x += reverse * (0.18 + wave * 0.25) + side * strafe * 0.10
		# Lateral sculls push both fins opposite the travel direction. The reverse
		# stroke flares both fins, then draws them in together instead of fluttering.
		hip.y = side * reverse * (0.16 + sweep * 0.34) - strafe * (0.24 + sweep * 0.20)
		hip.z = strafe * 0.08
		_legs[index].rotation = hip
		var knee_bend: float = -maxf(0.0, -flutter) * 0.6 * (1.0 - reverse)
		knee_bend -= reverse * (0.35 + (0.5 + 0.5 * cos(phase)) * 0.40)
		knee_bend -= lateral * (0.14 + (0.5 + 0.5 * sin(phase + index * PI)) * 0.16)
		_knees[index].rotation = Vector3(knee_bend, -side * reverse * sweep * 0.18, 0)
		# The left hand sculls for balance; the gun hand uses a smaller stroke.
		var arm_weight: float = 1.0 if index == 0 else 0.3
		var arm := Vector3(sin(phase * 0.5) * 0.012, 0, 0)
		arm.x += reverse * (0.08 + wave * 0.10) * arm_weight
		arm.y = (-side * reverse * (0.16 + sweep * 0.22) - strafe * 0.12) * arm_weight
		arm.z = (-side * reverse * 0.12 + strafe * (0.12 + wave * 0.06)) * arm_weight
		_arms[index].rotation = arm
