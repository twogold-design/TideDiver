extends SceneTree
## Bake the original procedural splash once; gameplay only plays the bundled WAV.
func _init() -> void:
	# Layer the initial impact, broad spray and irregular resonant bubbles.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	var count: int = 26460
	data.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 31415
	var low: float = 0.0
	var mid: float = 0.0
	for i in range(count):
		var t: float = float(i) / 22050.0
		var white: float = noise.randf_range(-1, 1)
		low = lerpf(low, white, 0.045)
		mid = lerpf(mid, white, 0.42)
		var attack: float = minf(t / 0.008, 1.0)
		var impact: float = low * 3.8 * exp(-t * 24)
		var spray: float = (mid - low) * 1.3 * exp(-t * 5.5)
		var wash: float = low * 1.7 * (1.0 - exp(-t * 22)) * exp(-t * 3.8)
		var bubbles: float = 0.0
		for j in range(9):
			var age: float = t - (0.12 + j * 0.083 + sin(j * 17.0) * 0.025)
			if age > 0:
				var frequency: float = 340 + fposmod(j * 173.0, 630)
				bubbles += sin(TAU * (frequency * age - 230 * age * age)) * exp(-age * 38) * minf(age * 900, 1.0) * 0.17
		var value: float = (impact + spray + wash) * attack + bubbles
		data.encode_s16(i * 2, int(clampf(value, -0.95, 0.95) * 29000))
	wav.data = data
	DirAccess.make_dir_recursive_absolute("res://assets/audio")
	var result := wav.save_to_wav("res://assets/audio/dive_splash.wav")
	assert(result == OK)
	quit()
