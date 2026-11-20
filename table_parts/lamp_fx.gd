class_name LampFx
## Helpers for lighting up part materials (inserts, caps, rubbers).

const LIT_ENERGY := 1.6
const FLASH_ENERGY := 4.0


## Makes a material glow briefly, then fade back to its lit/unlit level.
static func flash(owner_node: Node, material: StandardMaterial3D, color: Color,
		duration := 0.18, rest_energy := 0.0) -> void:
	if material == null or not owner_node.is_inside_tree():
		return
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = FLASH_ENERGY
	var tween := owner_node.create_tween()
	tween.tween_property(material, "emission_energy_multiplier", rest_energy, duration)


## Turns a material's glow on or off permanently.
static func set_lit(material: StandardMaterial3D, color: Color, lit: bool) -> void:
	if material == null:
		return
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = LIT_ENERGY if lit else 0.0
