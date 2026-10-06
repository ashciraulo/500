extends SceneTree
## A contact sheet of every bird and fish plate (SpeciesIcon), in colour and as
## silhouettes, for checking the drawings:
##
##   godot --headless --path . --script res://tools/species_sheet.gd -- out=/tmp/species.png [px=64]


func _init() -> void:
	var out := "user://species.png"
	var px := 64
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
		elif arg.begins_with("px="):
			px = int(arg.trim_prefix("px="))
	var birds: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/field/birds.json")).birds
	var fish_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/field/fish.json"))
	var fish: Array = fish_data.fish if fish_data is Dictionary else fish_data
	var cols := 10
	var cell := px + 12
	var rows := ceili(birds.size() / float(cols)) * 2 + ceili(fish.size() / float(cols)) * 2
	var sheet := Image.create(cols * cell + 12, rows * cell + 12, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("f3ead7"))
	var row := 0
	for group in [[birds, true], [fish, false]]:
		for silhouette in [false, true]:
			var list: Array = group[0]
			for i in list.size():
				var tex: Texture2D = SpeciesIcon.bird(list[i], px, silhouette) if group[1] else SpeciesIcon.fish(list[i], px, silhouette)
				var img := tex.get_image()
				img.convert(Image.FORMAT_RGBA8)
				var at := Vector2i(12 + (i % cols) * cell, 12 + (row + i / cols) * cell)
				sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
			row += ceili(list.size() / float(cols))
	sheet.save_png(out)
	print("species sheet: ", out)
	quit()
