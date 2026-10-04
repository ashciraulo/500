extends SceneTree
## Dumps the map's road data (map/tiles/*.p5r) to JSON for tools/places/gen_places.py.
## godot --headless --path . --script res://tools/places/dump_roads.gd -- (writes $OUT, default /tmp/roads.json)
func _init():
	var out := {"roads": [], "stations": []}
	var d := DirAccess.open("res://map/tiles")
	for f in d.get_files():
		if not f.ends_with(".p5r"): continue
		var data := MapTileLoader.read("res://map/tiles/" + f)
		for r in data.get("roads", []):
			var pts := []
			for p in r.pts: pts.append([p[0], p[1], p[2]])
			out.roads.append({"name": r.get("name", ""), "kind": r.get("kind", ""), "pts": pts, "oneway": r.get("oneway", false), "lanes": r.get("lanes_fwd", 1)})
		for s in data.get("stations", []):
			out.stations.append({"name": s.get("name", ""), "p": [s.p[0], s.p[1], s.p[2]]})
	var fa := FileAccess.open(OS.get_environment("OUT") if OS.has_environment("OUT") else "/tmp/roads.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	print("roads ", out.roads.size())
	quit()
