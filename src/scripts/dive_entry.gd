extends RefCounted
## Authored motion in seconds; matching tangents avoid a stop at the waterline.
const DURATION := 3.2
const IMPACT_TIME := 1.35

static func hermite(a: Vector3, b: Vector3, va: Vector3, vb: Vector3, span: float, u: float) -> Vector3:
	return (2*u*u*u-3*u*u+1)*a+(u*u*u-2*u*u+u)*va*span+(-2*u*u*u+3*u*u)*b+(u*u*u-u*u)*vb*span

static func position_at(time: float) -> Vector3:
	var t: float = clampf(time,0,DURATION)
	if t < .45:
		return hermite(Vector3(0,2.4,17.5),Vector3(0,2.25,17.5),Vector3.ZERO,Vector3(0,1.5,0),.45,t/.45)
	if t < 1.55:
		return hermite(Vector3(0,2.25,17.5),Vector3(0,-.55,22.5),Vector3(0,1.5,0),Vector3(0,-6.4,4.2),1.1,(t-.45)/1.1)
	return hermite(Vector3(0,-.55,22.5),Vector3(0,-6,25),Vector3(0,-6.4,4.2),Vector3.ZERO,1.65,(t-1.55)/1.65)

static func pitch_at(time: float) -> float:
	if time < .45:
		return PI/2-.12*sin(time/.45*PI)
	if time < 1.55:
		return lerpf(PI/2,-.58,smoothstep(.45,1.55,time))
	return lerpf(-.58,0,smoothstep(1.55,DURATION,time))

static func camera_offset(time: float) -> Vector3:
	var follow: float = smoothstep(.55,2.9,time)
	var final := Vector3(0,1.7-sin(-.12)*7.5,-cos(-.12)*7.5)
	return Vector3(5.5,2.65,-3.8).lerp(final,follow)
