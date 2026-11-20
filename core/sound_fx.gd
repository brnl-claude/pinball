class_name SoundFx
## Safe entry point for sound effects: plays through the `Sfx` autoload when
## it is running, and does nothing otherwise (editor, headless test scripts).


static func play(sound_name: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx:
		sfx.call("play", sound_name)
