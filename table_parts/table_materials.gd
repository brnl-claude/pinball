@tool
class_name TableMaterials
## PBR surface finishes for table parts, built in code so the project needs
## no texture assets yet. Textures are procedural and shared between parts.

enum Finish {
	## Painted wood or plastic: plain, fairly rough.
	PAINTED,
	## Clear-coated playfield: base colour with a glossy lacquer on top.
	PLAYFIELD,
	## Wooden cabinet side: wood grain, satin.
	WOOD,
	## Polished steel guides and rails.
	METAL,
	## Rubber rings and slingshot rubbers: matte.
	RUBBER,
	## Translucent plastic (inserts, caps).
	PLASTIC,
}

static var _wood_texture: NoiseTexture2D
static var _playfield_texture: NoiseTexture2D


static func make(finish: Finish, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	match finish:
		Finish.PLAYFIELD:
			material.albedo_texture = _playfield_noise()
			material.roughness = 0.35
			material.clearcoat_enabled = true
			material.clearcoat = 1.0
			material.clearcoat_roughness = 0.05
		Finish.WOOD:
			material.albedo_texture = _wood_noise()
			material.roughness = 0.45
			material.uv1_triplanar = true
			material.uv1_scale = Vector3(4.0, 4.0, 4.0)
		Finish.METAL:
			material.metallic = 1.0
			material.roughness = 0.22
			material.metallic_specular = 0.6
		Finish.RUBBER:
			material.roughness = 0.85
			material.metallic_specular = 0.3
		Finish.PLASTIC:
			material.roughness = 0.2
			material.clearcoat_enabled = true
			material.clearcoat = 0.6
			material.rim_enabled = true
			material.rim = 0.25
		_:
			material.roughness = 0.55
	return material


## A polished steel ball: fully metallic and nearly smooth, so it mirrors
## the reflection probe around the table.
static func chrome() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.9, 0.92)
	material.metallic = 1.0
	material.roughness = 0.04
	material.metallic_specular = 0.7
	return material


## Subtle mottling so the lacquered playfield does not look like flat paint.
static func _playfield_noise() -> NoiseTexture2D:
	if _playfield_texture == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.02
		noise.fractal_octaves = 3
		_playfield_texture = NoiseTexture2D.new()
		_playfield_texture.noise = noise
		_playfield_texture.width = 512
		_playfield_texture.height = 512
		_playfield_texture.seamless = true
		_playfield_texture.color_ramp = _ramp(Color(0.86, 0.86, 0.9), Color(1.0, 1.0, 1.0))
	return _playfield_texture


## Long, stretched noise reads as wood grain.
static func _wood_noise() -> NoiseTexture2D:
	if _wood_texture == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.01
		noise.fractal_octaves = 4
		_wood_texture = NoiseTexture2D.new()
		_wood_texture.noise = noise
		_wood_texture.width = 256
		_wood_texture.height = 1024
		_wood_texture.seamless = true
		_wood_texture.color_ramp = _ramp(Color(0.62, 0.5, 0.4), Color(1.0, 0.92, 0.82))
	return _wood_texture


static func _ramp(dark: Color, light: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, dark)
	gradient.set_color(1, light)
	return gradient
