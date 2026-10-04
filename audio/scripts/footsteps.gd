class_name FootstepAudio
extends Node3D
## Footsteps for anyone walking: add as a child of a CharacterBody3D (the
## player on foot, a neighbour). Every stride while it moves on the floor it
## plays a step for the surface underfoot, a heavier one on landing.
##
## The surface comes from what's under the feet, in this order:
##   1. the collider's "surface" metadata (the same as the car's tyres use);
##   2. the material of the floor face that was hit, for imported trimesh
##      colliders like the townhouse's (MATERIAL_SURFACES);
##   3. default_surface.
## Sounds are home/home_step_<surface>_NN; see audio/docs/home.md.

## Surfaces with step sounds.
const SURFACES := ["timber", "carpet", "stairs", "brick", "tile", "concrete", "mulch", "gravel"]
## Floor material name (from the Blender models) -> surface.
const MATERIAL_SURFACES := {
	"Jarrah": "timber", "F_wood_mid": "timber", "F_wood_dark": "timber", "F_oak": "timber",
	"Timber": "timber", "Carpet": "carpet", "StairCarpet": "stairs", "FloorTiles": "tile",
	"Mosaic": "tile", "WallTiles": "tile", "Pavers": "brick", "Concrete": "concrete",
	"Asphalt": "concrete", "Mulch": "mulch", "Corrugated": "concrete", "Iron": "concrete",
}
## The car's surface names -> step surfaces.
const SURFACE_ALIAS := {
	"asphalt": "concrete", "dirt": "gravel", "grass": "mulch", "sand": "gravel",
	"wood": "timber", "rumble": "concrete",
}

## Metres per step at a walk, and at a run (strides lengthen with speed).
@export var stride_walk := 0.7
@export var stride_run := 1.15
@export var run_speed := 4.5
@export var volume_db := -4.0
@export var default_surface := "concrete"

var surface := ""            # last surface stepped on
var steps := 0               # steps played, for tests

var _body: CharacterBody3D
var _travel := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _face_cache := {}        # Mesh instance id -> PackedInt32Array of cumulative face counts


func _ready() -> void:
	var n := get_parent()
	while n and not n is CharacterBody3D:
		n = n.get_parent()
	_body = n as CharacterBody3D


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	var on_floor := _body.is_on_floor()
	if on_floor and not _was_on_floor and _fall_speed > 2.5:
		_step(clampf(_fall_speed / 6.0, 0.6, 1.4))  # landing
		_travel = 0.0
	_was_on_floor = on_floor
	_fall_speed = maxf(-_body.velocity.y, 0.0) if not on_floor else 0.0
	if not on_floor:
		return
	var v := _body.velocity
	var speed := Vector2(v.x, v.z).length()
	if speed < 0.3:
		# Coming to a stop finishes the stride with a soft step.
		if _travel > stride_walk * 0.45:
			_step(0.6)
		_travel = 0.0
		return
	_travel += speed * delta
	var stride := lerpf(stride_walk, stride_run, clampf((speed - 1.4) / (run_speed - 1.4), 0.0, 1.0))
	if _travel >= stride:
		_travel -= stride
		_step(clampf(0.75 + speed / run_speed * 0.4, 0.75, 1.2))


func _step(force: float) -> void:
	surface = surface_under()
	steps += 1
	Audio.play_at("home/home_step_" + surface, global_position,
			volume_db + linear_to_db(force), "SFX", 0.06)


## What's underfoot: see the class notes.
func surface_under() -> String:
	var from := _body.global_position + Vector3.UP * 0.3 if _body else global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5)
	if _body:
		q.exclude = [_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return default_surface
	var col: Object = hit.collider
	if col is Node and (col as Node).has_meta("surface"):
		var s := String((col as Node).get_meta("surface"))
		s = SURFACE_ALIAS.get(s, s)
		return s if s in SURFACES else default_surface
	var mat := _material_at(col as Node, int(hit.get("face_index", -1)))
	return MATERIAL_SURFACES.get(mat, default_surface)


## Material name of the mesh face a trimesh collider was hit on. Godot's
## trimesh shapes keep the mesh's faces in surface order, so the face index
## tells which surface (and so which material) it belongs to.
func _material_at(col: Node, face: int) -> String:
	if col == null or face < 0:
		return ""
	var mi := col.get_parent() as MeshInstance3D
	if mi == null or mi.mesh == null:
		return ""
	var mesh := mi.mesh
	var key := mesh.get_instance_id()
	if not _face_cache.has(key):
		var ends := PackedInt32Array()
		var total := 0
		for i in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(i)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += (idx.size() if idx.size() > 0 else verts.size()) / 3
			ends.append(total)
		_face_cache[key] = ends
	var ends: PackedInt32Array = _face_cache[key]
	for i in ends.size():
		if face < ends[i]:
			var m := mi.get_active_material(i)
			return m.resource_name if m else ""
	return ""
