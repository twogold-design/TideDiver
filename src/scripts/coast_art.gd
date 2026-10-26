extends RefCounted
## Layered sandy shoreline, rolling surf and small coastal details in restaurant-local space.
const A = preload("res://scripts/ocean_art.gd")

static func shore(x: float) -> float:
	return -13.0+sin(x*0.09)*3.0

static func build(root: Node3D) -> void:
	var coast := Node3D.new()
	coast.name = "LivingCoast"
	root.add_child(coast)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in range(160):
		for iz in range(8):
			var corners: Array[Vector3] = []
			var colors: Array[Color] = []
			for offset: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
				var x: float = -200.0+(ix+offset.x)*2.5
				var t: float = (iz+offset.y)/8.0
				var z: float = lerpf(shore(x)-2.0,36.0,t)
				var y: float = -0.85+0.55*smoothstep(0,0.18,t)
				if absf(x) > 15:
					y += sin(x*0.31+z*0.17)*0.20*smoothstep(0.1,0.4,t)
				corners.append(Vector3(x,y,z))
				colors.append(Color("827d67").lerp(Color("ccb58c"),smoothstep(0,0.2,t)).darkened(0.025*sin(x*3.1+z*2.2)))
			for index in [0,2,1,1,2,3]:
				surface.set_color(colors[index])
				surface.add_vertex(corners[index])
	surface.generate_normals()
	var sand := A._mat(Color("bfb8ac"))
	sand.vertex_color_use_as_albedo = true
	sand.vertex_color_is_srgb = true
	sand.cull_mode = BaseMaterial3D.CULL_DISABLED
	A._mesh(coast,surface.commit(),Vector3.ZERO,sand)
	var water := PlaneMesh.new()
	water.size = Vector2(1400,1000)
	water.subdivide_width = 100
	water.subdivide_depth = 70
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 p;
float hash(vec2 q){return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 q){vec2 i=floor(q); vec2 f=fract(q); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){
 p=VERTEX+vec3(0.0,-0.78,-507.0);
}
void fragment(){
 float edge=p.z-(-13.0+sin(p.x*0.09)*3.0);
 float surge=sin(TIME*0.8+p.x*0.06)*0.7;
 if(edge>surge) discard;
 float shallow=exp(min(edge,0.0)*0.09);
 float n=noise(p.xz*1.5+vec2(TIME*0.1,0.0));
 float foam=1.0-smoothstep(0.15,1.0,abs(edge-surge+0.55+n*0.3));
 float ripple=pow(max(0.0,sin(edge*1.5+TIME*1.2+noise(p.xz*0.22)*1.8)),12.0)*smoothstep(-9.0,-2.0,edge);
 float far_haze=smoothstep(35.0,240.0,-edge);
 vec3 sea=mix(vec3(0.035,0.20,0.26),vec3(0.16,0.45,0.39),shallow);
 sea+=vec3(0.015,0.03,0.028)*(noise(p.xz*0.6+vec2(TIME*0.06))-0.5);
 sea=mix(sea,vec3(0.18,0.31,0.35),far_haze);
 ALBEDO=mix(sea,vec3(0.70,0.80,0.72),clamp(foam*(0.5+0.5*n)+ripple*0.26,0.0,0.85));
 vec2 q=p.xz*1.2+vec2(TIME*0.09,TIME*0.04);
 float wave=noise(q)+noise(q*2.3)*0.35;
 float dx=noise(q+vec2(0.15,0.0))+noise((q+vec2(0.15,0.0))*2.3)*0.35-wave;
 float dz=noise(q+vec2(0.0,0.15))+noise((q+vec2(0.0,0.15))*2.3)*0.35-wave;
 float detail=(1.0-far_haze)*0.55;
 NORMAL=normalize(NORMAL+vec3(dx*detail,dz*detail,0.0));
 ROUGHNESS=0.48+foam*0.4; METALLIC=0.0; SPECULAR=0.25;
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	A._mesh(coast,water,Vector3(0,-0.78,-507),material)
	# Weathered rocks, shells and driftwood stay outside the editable restaurant floor.
	var stone := A._mat(Color("647e7b"))
	var wood := A._mat(Color("908774"))
	var grass := A._mat(Color("8a9d68"))
	for i in range(20):
		var x: float = (-1.0 if i%2 == 0 else 1.0)*(20.0+float(i%7)*2.1)
		var z: float = -9.0+float(i%5)*6.1
		A._sphere(coast,Vector3(x,-0.25,z),Vector3(0.7+float(i%3)*0.3,0.28,0.55),stone,8)
		for j in range(4):
			var stem := A._sphere(coast,Vector3(x+0.8+j*0.11,0.12,z+0.5),Vector3(0.028,0.55+j*0.03,0.08),grass,6)
			stem.rotation.z = -0.35+j*0.2
	for i in range(28):
		var x: float = sin(i*2.399)*31.0
		var z: float = shore(x)+2.0+float(i%3)
		var shell := A._sphere(coast,Vector3(x,-0.43,z),Vector3(0.13,0.05,0.18),A._mat(Color("ede1c9")),6)
		shell.rotation.y = i*1.8
	for i in range(5):
		var log := A._cylinder(coast,Vector3(-20+i*0.7,-0.05,1+i*0.4),0.13,2.6,wood)
		log.rotation = Vector3(PI/2,0.4+i*0.2,0)
	# A small moored rowing boat anchors the scene to a working seaside.
	var boat := Node3D.new()
	boat.position = Vector3(22,-0.25,-10)
	boat.rotation.y = -0.6
	coast.add_child(boat)
	A._sphere(boat,Vector3.ZERO,Vector3(1.0,0.35,2.7),A._mat(Color("587f81")),12)
	A._sphere(boat,Vector3(0,0.20,0),Vector3(0.82,0.10,2.35),A._mat(Color("5c645b")),12)
	for z: float in [-1.0,0.0,1.0]:
		A._box(boat,Vector3(0,0.28,z),Vector3(1.65,0.09,0.30),wood)
	A._branch(coast,Vector3(23,0,-7),Vector3(18.5,0.4,-4),0.025,A._mat(Color("c4b790")))
	# Fabric eaves and narrow ribs frame the sea without covering the play area.
	for i in range(22):
		var color := A._mat(Color("d9c6a0") if i%2 == 0 else Color("497f80"))
		var cloth := A._box(coast,Vector3(-10.5+i,4.48,-5.4),Vector3(0.98,0.06,1.5),color)
		cloth.rotation.x = -0.08
