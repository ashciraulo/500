extends SceneTree
## Writes the water surface heights inside each lake habitat (from the map's
## tiles) into data/field/habitats.json as `water`: [[x, z, height], ...],
## one per 25 m cell, so ducks float on the right pond. Rerun after a map
## rebuild:
##
##   godot --headless --path . --script res://tools/field/water_levels.gd

const CELL := 25.0


const Tiles := preload("res://map/scripts/tile_loader.gd")


func _initialize() -> void:
	var path := "res://data/field/habitats.json"
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var habitats: Array = doc.habitats
	for h: Dictionary in habitats:
		if not Array(h.tags).has("lake") and not Array(h.tags).has("reeds"):
			continue
		var c := Vector2(float(h.x), float(h.z))
		var r := float(h.radius)
		var cells := {}
		for i in range(floori((c.x - r) / 500.0), floori((c.x + r) / 500.0) + 1):
			for j in range(floori(-(c.y + r) / 500.0), floori(-(c.y - r) / 500.0) + 1):
				var data: Dictionary = Tiles.read("res://map/tiles/%d_%d.p5t" % [i, j])
				if data.is_empty():
					continue
				var origin: Array = data.origin
				for mesh: Dictionary in data.meshes:
					for surface: Dictionary in mesh.surfaces:
						if String(surface.material) != "water":
							continue
						var arrays: Array = Tiles._decode_surface(surface)
						for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
							var p := v + Vector3(origin[0], origin[1], origin[2])
							if Vector2(p.x, p.z).distance_to(c) < r:
								var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
								if not cells.has(key):
									cells[key] = []
								cells[key].append(p)
		var water := []
		for key: Vector2i in cells:
			var pts: Array = cells[key]
			var ys := pts.map(func(q: Vector3) -> float: return q.y)
			ys.sort()
			var mid := Vector3.ZERO
			for q: Vector3 in pts:
				mid += q
			mid /= pts.size()
			water.append([snappedf(mid.x, 0.1), snappedf(mid.z, 0.1), snappedf(float(ys[ys.size() / 2]), 0.05)])
		water.sort()
		h.water = water
		print(h.id, ": ", water.size(), " cells")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t", false) + "\n")
	f.close()
	quit()
