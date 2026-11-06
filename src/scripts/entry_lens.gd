extends ColorRect
## A short water film as the actual camera passes below the surface.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float film = 0.0;
uniform float immersion = 0.0;
uniform float entry_clock = 0.0;
void fragment() {
    vec2 uv=SCREEN_UV;
    float edge=smoothstep(.18,.68,length(uv-.5));
    vec2 flow=vec2(sin(uv.y*34.0+entry_clock*8.0),cos(uv.x*27.0-entry_clock*6.0));
    vec2 offset=flow*film*(.0006+edge*.0016);
    vec3 scene=texture(screen_texture,clamp(uv+offset,vec2(.001),vec2(.999))).rgb;
    scene=mix(scene,scene*vec3(.88,1.015,1.035),immersion*.22);
    scene+=vec3(.10,.18,.19)*film*edge*.12;
    COLOR=vec4(scene,1.0);
}
"""
	material = ShaderMaterial.new()
	material.shader = shader
	visible = false

func update_view(time: float, camera_y: float, active: bool) -> void:
	var immersion: float = 1.0-smoothstep(-1.1,.25,camera_y)
	var crossing: float = exp(-pow((camera_y+.08)/.65,2.0))
	var fade: float = 1.0-smoothstep(2.45,3.2,time)
	visible = active and time > .8 and fade > .001
	material.set_shader_parameter("film",crossing*fade)
	material.set_shader_parameter("immersion",immersion*fade)
	material.set_shader_parameter("entry_clock",time)
