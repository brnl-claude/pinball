@tool
class_name RampPath
## Geometry helpers for ramps: a smooth path through control points, a
## frame (side and up vectors) along it, and meshes extruded along it.
##
## Paths are given as the track of the ball's lowest point, in the ramp
## node's local coordinates (which are table coordinates when the node sits
## at the origin): x across the table, y up from the playfield, z toward the
## drain.


## Samples a centripetal Catmull-Rom spline through `points`, about every
## `step` meters. Centripetal parameterization does not overshoot or loop
## when control points are unevenly spaced, so tight turns stay tight.
static func sample(points: PackedVector3Array, step: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	if points.size() < 2:
		return points.duplicate()
	var count := points.size()
	for i in count - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, count - 1)]
		# Extend the ends straight, so the first and last segments do not bend.
		if i == 0:
			p0 = p1 - (p2 - p1)
		if i + 2 >= count:
			p3 = p2 + (p2 - p1)
		var pieces := maxi(1, ceili(p1.distance_to(p2) / step))
		for k in pieces:
			result.append(_centripetal(p0, p1, p2, p3, float(k) / pieces))
	result.append(points[count - 1])
	return result


static func _centripetal(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var t0 := 0.0
	var t1 := t0 + sqrt(maxf(p0.distance_to(p1), 1e-6))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 1e-6))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 1e-6))
	var t := lerpf(t1, t2, u)
	var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))


## For each sample a Basis with x = side (to the right when travelling along
## the path, always horizontal), y = up (perpendicular to the path) and
## z = tangent (the direction of travel).
static func frames(samples: PackedVector3Array) -> Array[Basis]:
	var result: Array[Basis] = []
	var count := samples.size()
	for i in count:
		var tangent := samples[mini(i + 1, count - 1)] - samples[maxi(i - 1, 0)]
		tangent = tangent.normalized() if tangent.length() > 1e-9 else Vector3.FORWARD
		var side := tangent.cross(Vector3.UP)
		side = side.normalized() if side.length() > 1e-6 else Vector3.RIGHT
		var up := side.cross(tangent).normalized()
		result.append(Basis(side, up, tangent))
	return result


## Total length of a sampled path.
static func length(samples: PackedVector3Array) -> float:
	var total := 0.0
	for i in samples.size() - 1:
		total += samples[i].distance_to(samples[i + 1])
	return total


## Extrudes a 2D cross-section along the path into `tool` (PRIMITIVE_TRIANGLES).
## Profile points are (side, up) offsets from the path. With `smooth`, the
## vertex normal points away from `profile_center` (tubes); otherwise each
## profile edge is shaded flat (plastic walls). Triangles are wound so the
## outward side is the front face.
##
## `widen`, if given, has one value per sample: profile points move that much
## further out sideways (away from the centre line) at that sample, for
## ramps whose width changes along the path.
static func extrude(tool: SurfaceTool, samples: PackedVector3Array, basis_list: Array[Basis],
		profile: PackedVector2Array, closed: bool, smooth: bool,
		profile_center := Vector2.ZERO, widen := PackedFloat32Array()) -> void:
	var edge_count := profile.size() if closed else profile.size() - 1
	for i in samples.size() - 1:
		var b0 := basis_list[i]
		var b1 := basis_list[i + 1]
		for k in edge_count:
			var a := profile[k]
			var c := profile[(k + 1) % profile.size()]
			var n_a: Vector2
			var n_c: Vector2
			if smooth:
				n_a = (a - profile_center).normalized()
				n_c = (c - profile_center).normalized()
			else:
				var d := c - a
				n_a = Vector2(-d.y, d.x).normalized()
				n_c = n_a
			var w0 := widen[i] if i < widen.size() else 0.0
			var w1 := widen[i + 1] if i + 1 < widen.size() else 0.0
			var v00 := samples[i] + b0.x * _wider(a.x, w0) + b0.y * a.y
			var v01 := samples[i] + b0.x * _wider(c.x, w0) + b0.y * c.y
			var v10 := samples[i + 1] + b1.x * _wider(a.x, w1) + b1.y * a.y
			var v11 := samples[i + 1] + b1.x * _wider(c.x, w1) + b1.y * c.y
			var m00 := (b0.x * n_a.x + b0.y * n_a.y).normalized()
			var m01 := (b0.x * n_c.x + b0.y * n_c.y).normalized()
			var m10 := (b1.x * n_a.x + b1.y * n_a.y).normalized()
			var m11 := (b1.x * n_c.x + b1.y * n_c.y).normalized()
			_triangle(tool, [v00, v10, v11], [m00, m10, m11])
			_triangle(tool, [v00, v11, v01], [m00, m11, m01])


## Adds one triangle, wound clockwise as seen from the side its normals face
## (Godot's front face).
static func _triangle(tool: SurfaceTool, vertices: Array, normals: Array) -> void:
	var face: Vector3 = (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0])
	var average: Vector3 = normals[0] + normals[1] + normals[2]
	var order := [0, 1, 2] if face.dot(average) < 0.0 else [0, 2, 1]
	for index: int in order:
		tool.set_normal(normals[index])
		tool.add_vertex(vertices[index])


## Triangles (three vertices each) of a ribbon between two profile points,
## swept along the path: collision faces for ConcavePolygonShape3D.
static func ribbon_faces(samples: PackedVector3Array, basis_list: Array[Basis],
		a: Vector2, c: Vector2, widen := PackedFloat32Array()) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in samples.size() - 1:
		var b0 := basis_list[i]
		var b1 := basis_list[i + 1]
		var w0 := widen[i] if i < widen.size() else 0.0
		var w1 := widen[i + 1] if i + 1 < widen.size() else 0.0
		var v00 := samples[i] + b0.x * _wider(a.x, w0) + b0.y * a.y
		var v01 := samples[i] + b0.x * _wider(c.x, w0) + b0.y * c.y
		var v10 := samples[i + 1] + b1.x * _wider(a.x, w1) + b1.y * a.y
		var v11 := samples[i + 1] + b1.x * _wider(c.x, w1) + b1.y * c.y
		for vertex: Vector3 in [v00, v10, v11, v00, v11, v01]:
			faces.append(vertex)
	return faces


## A circle of `segments` points, for tube profiles.
static func circle(radius: float, segments: int, center := Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in segments:
		var angle := TAU * k / segments
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _wider(x: float, extra: float) -> float:
	return x + signf(x) * extra
