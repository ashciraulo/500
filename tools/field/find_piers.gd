extends SceneTree
## Lists the map's piers (decks the importer built from OSM man_made=pier):
## centre, size, deck height. For picking fishing spots.
##
##   godot --headless --path . --script res://tools/field/find_piers.gd

const Tiles := preload("res://map/scripts/tile_loader.gd")


func _initialize() -> void:
	var dir := DirAccess.open("res://map/tiles")
	var cells := {}
	for f in dir.get_files():
		if not f.ends_with(".p5t"):
			continue
		var data: Dictionary = Tiles.read("res://map/tiles/" + f)
		if data.is_empty():
			continue
		var origin: Array = data.origin
		var o := Vector3(origin[0], origin[1], origin[2])
		for mesh: Dictionary in data.meshes:
			if String(mesh.name) != "props":
				continue
			for surface: Dictionary in mesh.surfaces:
				if String(surface.material) != "path":
					continue
				var arrays: Array = Tiles._decode_surface(surface)
				for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					var p := v + o
					var key := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
					if not cells.has(key):
						cells[key] = []
					cells[key].append(p)
	# Join neighbouring cells into piers.
	var seen := {}
	for key: Vector2i in cells:
		if seen.has(key):
			continue
		var stack := [key]
		var pts := []
		seen[key] = true
		while not stack.is_empty():
			var k: Vector2i = stack.pop_back()
			pts.append_array(cells[k])
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var n := k + Vector2i(dx, dz)
					if cells.has(n) and not seen.has(n):
						seen[n] = true
						stack.append(n)
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for p: Vector3 in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		print("pier centre (%.1f, %.1f, %.1f) size %.0f x %.0f  top %.1f" % [(lo.x + hi.x) / 2, hi.y, (lo.z + hi.z) / 2, hi.x - lo.x, hi.z - lo.z, hi.y])
	quit()
