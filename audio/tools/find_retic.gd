extends SceneTree
## Finds where the reticulation runs: the map's lawns (grass and turf ground
## in the tiles) big enough to be a park, oval or golf course, and spreads
## sprinkler spots over each one. Writes res://audio/data/retic.json, which
## the ambience reads (ambience_manager.gd, "retic" places). Run after the
## map's tiles are rebuilt:
##
##   godot --headless --path . --script res://audio/tools/find_retic.gd

const CELL := 20.0          # metres
const CELL_MIN := 0.5       # a cell is lawn when at least this much of it is grass
const PARK_MIN := 5000.0    # m² of lawn for a park (a big backyard is ~300)
const SPACING := 90.0       # metres between sprinkler spots in one park
const OUT := "res://audio/data/retic.json"


func _init() -> void:
	var cells := {}         # Vector2i -> [area, sum_y]
	var d := DirAccess.open("res://map/tiles")
	for f in d.get_files():
		if not f.ends_with(".p5t"):
			continue
		var data: Dictionary = MapTileLoader.read("res://map/tiles/" + f)
		if data.is_empty():
			continue
		var origin := Vector3(data.origin[0], data.origin[1], data.origin[2])
		for m in data.meshes:
			if m.name != "ground":
				continue
			for s in m.surfaces:
				if not String(s.material) in ["grass", "turf"]:
					continue
				var arrays: Array = MapTileLoader._decode_surface(s)
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for t in range(0, idx.size(), 3):
					var a := v[idx[t]] + origin
					var b := v[idx[t + 1]] + origin
					var c := v[idx[t + 2]] + origin
					var area := (b - a).cross(c - a).length() * 0.5
					var mid := (a + b + c) / 3.0
					var key := Vector2i(floori(mid.x / CELL), floori(mid.z / CELL))
					var cur: Array = cells.get(key, [0.0, 0.0])
					cur[0] += area
					cur[1] += mid.y * area
					cells[key] = cur
	var lawn := {}
	for key in cells:
		if cells[key][0] >= CELL * CELL * CELL_MIN:
			lawn[key] = cells[key]
	# Parks: lawn cells joined edge to edge.
	var seen := {}
	var spots: Array = []
	var parks := 0
	for start in lawn:
		if seen.has(start):
			continue
		var patch: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			patch.append(c)
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + o
				if lawn.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		var area := 0.0
		for c in patch:
			area += lawn[c][0]
		if area < PARK_MIN:
			continue
		parks += 1
		# One spot per SPACING square the park reaches into, at the lawn cell
		# nearest that square's middle.
		var best := {}
		for c in patch:
			var mid := (Vector2(c) + Vector2(0.5, 0.5)) * CELL
			var sq := Vector2i(floori(mid.x / SPACING), floori(mid.y / SPACING))
			var centre := (Vector2(sq) + Vector2(0.5, 0.5)) * SPACING
			var dist := mid.distance_to(centre)
			if not best.has(sq) or dist < best[sq][0]:
				best[sq] = [dist, c]
		for sq in best:
			var c: Vector2i = best[sq][1]
			var y: float = lawn[c][1] / lawn[c][0]
			spots.append([snappedf((c.x + 0.5) * CELL, 0.1), snappedf(y, 0.1), snappedf((c.y + 0.5) * CELL, 0.1)])
	spots.sort()
	DirAccess.make_dir_recursive_absolute("res://audio/data")
	var out := FileAccess.open(OUT, FileAccess.WRITE)
	out.store_string(JSON.stringify({"_comment": "Sprinkler spots on the map's lawns (audio/tools/find_retic.gd): [x, y, z] world metres.",
			"spots": spots}))
	print("%d lawn cells, %d parks, %d sprinkler spots -> %s" % [lawn.size(), parks, spots.size(), OUT])
	quit()
