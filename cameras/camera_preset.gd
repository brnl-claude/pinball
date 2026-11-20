class_name CameraPreset
extends Resource
## A layout profile: camera angle and field of view for a range of aspect
## ratios, plus where the HUD goes. Tables can bring their own presets; the
## defaults cover 9:16 portrait/cabinet, 16:9 to 21:9 and 32:9.

enum HudLayout {
	## Score and info in a bar at the top, as if the backbox hangs above.
	TOP_BAR,
	## Score and info in a column next to the table.
	SIDE_PANEL,
	## Score on one side of the table, info on the other.
	SIDE_PANELS,
}

@export var name := "landscape"
## Picked automatically when min_aspect <= aspect < max_aspect.
@export var auto_select := true
@export var min_aspect := 1.0
@export var max_aspect := 2.6
@export_range(10.0, 90.0) var pitch_degrees := 38.0
## Vertical field of view of the (logical, after screen rotation) view.
@export_range(20.0, 90.0) var fov_degrees := 50.0
## Extra space around the table, as a fraction of the view.
@export_range(1.0, 1.5) var framing_margin := 1.04
@export var hud_layout := HudLayout.SIDE_PANEL


static func make(preset_name: String, min_ratio: float, max_ratio: float, pitch: float,
		fov: float, layout: HudLayout, automatic := true) -> CameraPreset:
	var preset := CameraPreset.new()
	preset.name = preset_name
	preset.min_aspect = min_ratio
	preset.max_aspect = max_ratio
	preset.pitch_degrees = pitch
	preset.fov_degrees = fov
	preset.hud_layout = layout
	preset.auto_select = automatic
	return preset


## Portrait/cabinet (9:16, 3:4, 9:21), landscape (16:10 to 21:9), super
## ultrawide (32:9) and a manual top-down view.
static func defaults() -> Array[CameraPreset]:
	return [
		make("portrait", 0.0, 1.0, 62.0, 50.0, HudLayout.TOP_BAR),
		make("landscape", 1.0, 2.6, 38.0, 50.0, HudLayout.SIDE_PANEL),
		make("ultrawide", 2.6, INF, 40.0, 46.0, HudLayout.SIDE_PANELS),
		make("top-down", 0.0, INF, 90.0, 50.0, HudLayout.TOP_BAR, false),
	]


## The first automatic preset whose range contains the aspect ratio.
static func select(presets: Array[CameraPreset], aspect: float) -> CameraPreset:
	for preset in presets:
		if preset.auto_select and aspect >= preset.min_aspect and aspect < preset.max_aspect:
			return preset
	return presets[0] if not presets.is_empty() else null
