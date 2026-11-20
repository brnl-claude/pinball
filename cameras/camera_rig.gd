class_name CameraRig
extends Camera3D
## Camera that frames the whole table for the current aspect ratio.
##
## The rig picks a layout profile from the viewport's aspect ratio (portrait
## for 9:16 and other tall screens, landscape for 16:9 up to 32:9) and then
## finds the closest distance at which the whole table fits in view.
## Cameras are deliberately decoupled from game logic, so a VR rig can be
## added later without touching the table or the rules.

enum Profile { AUTO, PORTRAIT, LANDSCAPE, TOP_DOWN }

const PROFILE_NAMES := ["auto", "portrait", "landscape", "top-down"]

## Size of the table's bounding box in meters (width, height, length).
@export var table_size := Vector3(0.55, 0.07, 1.11)
@export var table_center := Vector3(0.0, 0.03, 0.0)
@export_range(10.0, 90.0) var portrait_pitch_degrees := 62.0
@export_range(10.0, 90.0) var landscape_pitch_degrees := 38.0
## Extra space around the table, as a fraction of the view.
@export_range(1.0, 1.5) var framing_margin := 1.04

var profile := Profile.AUTO


func _ready() -> void:
	get_viewport().size_changed.connect(update_framing)
	update_framing()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		profile = ((profile + 1) % Profile.size()) as Profile
		update_framing()


func viewport_aspect() -> float:
	var size := get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)


func active_profile() -> Profile:
	if profile != Profile.AUTO:
		return profile
	return Profile.PORTRAIT if viewport_aspect() < 1.0 else Profile.LANDSCAPE


func profile_name() -> String:
	var label: String = PROFILE_NAMES[active_profile()]
	return label + (" (auto)" if profile == Profile.AUTO else "")


func pitch_for(p: Profile) -> float:
	match p:
		Profile.PORTRAIT:
			return portrait_pitch_degrees
		Profile.TOP_DOWN:
			return 90.0
		_:
			return landscape_pitch_degrees


func update_framing() -> void:
	global_transform = compute_framing(
			pitch_for(active_profile()), fov, viewport_aspect(),
			table_center, table_size, framing_margin)
	reset_physics_interpolation()


## Returns a camera transform that looks at the table from the player's side
## (+Z) with the given pitch, as close as possible while the whole bounding
## box stays inside the view.
static func compute_framing(pitch_degrees: float, vfov_degrees: float, aspect: float,
		center: Vector3, size: Vector3, margin: float) -> Transform3D:
	var basis := Basis(Vector3.RIGHT, -deg_to_rad(pitch_degrees))
	var forward := -basis.z
	var tan_v := tan(deg_to_rad(vfov_degrees) * 0.5) / margin
	var tan_h := tan_v * aspect
	var corners := box_corners(center, size)

	var low := 0.0
	var high := 100.0
	for i in 48:
		var mid := (low + high) * 0.5
		var candidate := Transform3D(basis, center - forward * mid)
		if corners_visible(candidate, corners, tan_h, tan_v):
			high = mid
		else:
			low = mid
	return Transform3D(basis, center - forward * high)


static func box_corners(center: Vector3, size: Vector3) -> PackedVector3Array:
	var half := size * 0.5
	var corners := PackedVector3Array()
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				corners.append(center + Vector3(half.x * x, half.y * y, half.z * z))
	return corners


static func corners_visible(xform: Transform3D, corners: PackedVector3Array,
		tan_h: float, tan_v: float) -> bool:
	var to_local := xform.affine_inverse()
	for corner in corners:
		var p := to_local * corner
		var depth := -p.z
		if depth <= 0.0:
			return false
		if absf(p.x) > tan_h * depth or absf(p.y) > tan_v * depth:
			return false
	return true
