class_name CameraRig
extends Camera3D
## Camera that frames the whole table for the current aspect ratio.
##
## The rig picks a layout profile (`CameraPreset`) from the aspect ratio the
## player sees: portrait for 9:16 and other tall screens, landscape for 16:10
## to 21:9, ultrawide for 32:9. It then finds the closest distance at which
## the whole table fits in view. With in-game screen rotation (a monitor
## turned upright in a cabinet), the camera rolls with the content. C cycles
## through the presets manually.
## Cameras are deliberately decoupled from game logic, so a VR rig can be
## added later without touching the table or the rules.
##
## The camera is the player's head: when a nudge shoves the cabinet, the
## camera stays put, so the table visibly jolts in the view.

signal preset_changed(preset: CameraPreset)

## Size of the table's bounding box in meters (width, height, length).
@export var table_size := Vector3(0.55, 0.07, 1.11)
@export var table_center := Vector3(0.0, 0.03, 0.0)
## Layout profiles; empty means `CameraPreset.defaults()`.
@export var presets: Array[CameraPreset] = []
## How much of the cabinet's nudge motion shows on screen (1 = real).
@export_range(0.0, 3.0) var nudge_view_scale := 1.0

## Index into `presets` chosen with C, or -1 for automatic.
var manual_index := -1

var _framing := Transform3D.IDENTITY
var _last_preset: CameraPreset


func _ready() -> void:
	if presets.is_empty():
		presets = CameraPreset.defaults()
	get_viewport().size_changed.connect(update_framing)
	var settings := get_node_or_null("/root/DisplaySettings")
	if settings:
		settings.connect("changed", update_framing)
	update_framing()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		# auto → each preset in turn → auto
		manual_index += 1
		if manual_index >= presets.size():
			manual_index = -1
		update_framing()


func _physics_process(_delta: float) -> void:
	var cabinet := get_tree().get_first_node_in_group("cabinet")
	if cabinet == null:
		return
	var offset: Vector3 = cabinet.get("offset")
	global_transform = _framing.translated(-offset * nudge_view_scale)


func screen_rotation() -> int:
	return ScreenRotation.current(get_tree())


## Aspect ratio as the player sees it (after screen rotation).
func viewport_aspect() -> float:
	var size := ScreenRotation.logical_size(get_viewport().get_visible_rect().size, screen_rotation())
	return size.x / maxf(size.y, 1.0)


func active_preset() -> CameraPreset:
	if manual_index >= 0 and manual_index < presets.size():
		return presets[manual_index]
	return CameraPreset.select(presets, viewport_aspect())


func profile_name() -> String:
	var preset := active_preset()
	var label := preset.name if preset else "none"
	label += " (auto)" if manual_index < 0 else ""
	if screen_rotation() != 0:
		label += ", rotated %d°" % screen_rotation()
	return label


func update_framing() -> void:
	var preset := active_preset()
	if preset == null:
		return
	var rotation_degrees_screen := screen_rotation()
	# The preset's FOV is for the logical view. With the content turned a
	# quarter, the logical vertical is the real horizontal.
	keep_aspect = Camera3D.KEEP_WIDTH if rotation_degrees_screen % 180 == 90 else Camera3D.KEEP_HEIGHT
	fov = preset.fov_degrees
	_framing = compute_framing(preset.pitch_degrees, preset.fov_degrees, viewport_aspect(),
			table_center, table_size, preset.framing_margin)
	_framing.basis = _framing.basis * roll_basis(rotation_degrees_screen)
	global_transform = _framing
	reset_physics_interpolation()
	if preset != _last_preset:
		_last_preset = preset
		preset_changed.emit(preset)


## Rolling the camera counterclockwise around its view axis turns the image
## clockwise, which is how screen rotation is defined.
static func roll_basis(screen_rotation_degrees: int) -> Basis:
	return Basis(Vector3.BACK, deg_to_rad(float(screen_rotation_degrees)))


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
