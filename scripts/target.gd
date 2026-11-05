extends Node3D
## Pop-up silhouette target with a separate head and body hitbox.

signal downed(target: Node3D, headshot: bool)

var hp := 100.0
var max_hp := 100.0
var is_up := true
var respawn := false
var respawn_time := 3.0
var pivot: Node3D
var body_mat: StandardMaterial3D
var head_mat: StandardMaterial3D
var ring_mat: StandardMaterial3D
var _flash_tw: Tween
var _last_head := false

const OLIVE := Color(0.36, 0.40, 0.28)
const HEAD := Color(0.42, 0.44, 0.30)
const RING := Color(0.85, 0.85, 0.80)


func _ready() -> void:
	pivot = Node3D.new()
	add_child(pivot)
	# Base plate + post.
	_mesh(self, BoxMesh.new(), Vector3(0.5, 0.05, 0.3), Vector3(0, 0.025, 0), Color(0.2, 0.2, 0.2))
	# Body silhouette.
	body_mat = _mat(OLIVE)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("target_part", "body")
	body.set_meta("target", self)
	var bs := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.52, 1.05, 0.06)
	bs.shape = bb
	body.add_child(bs)
	var bm := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = bb.size
	bm.mesh = bmesh
	bm.material_override = body_mat
	body.add_child(bm)
	body.position = Vector3(0, 0.575, 0)
	pivot.add_child(body)
	# Centre-mass ring (visual only).
	ring_mat = _mat(RING)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.1
	ring.mesh = tm
	ring.material_override = ring_mat
	ring.rotation.x = PI / 2.0
	ring.position = Vector3(0, 0.78, -0.035)
	pivot.add_child(ring)
	# Head.
	head_mat = _mat(HEAD)
	var head := StaticBody3D.new()
	head.collision_layer = 2
	head.collision_mask = 0
	head.set_meta("target_part", "head")
	head.set_meta("target", self)
	var hs := CollisionShape3D.new()
	var hshape := SphereShape3D.new()
	hshape.radius = 0.16
	hs.shape = hshape
	head.add_child(hs)
	var hm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	hm.mesh = sm
	hm.material_override = head_mat
	head.add_child(hm)
	head.position = Vector3(0, 1.28, 0)
	pivot.add_child(head)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _mesh(parent: Node3D, mesh: BoxMesh, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Returns {} when the target is already down, otherwise {killed, points}.
func hit(part: String, damage: float, head_mult: float, _pos: Vector3) -> Dictionary:
	if not is_up:
		return {}
	var is_head := part == "head"
	var dmg := damage * (head_mult if is_head else 1.0)
	hp -= dmg
	_last_head = is_head
	var points := 25 if is_head else 10
	_flash(is_head)
	Sfx.impact("metal", global_position, -3.0)
	var killed := false
	if hp <= 0.0:
		killed = true
		points += 50
		_fall()
	return {"killed": killed, "points": points}


func _flash(is_head: bool) -> void:
	if _flash_tw:
		_flash_tw.kill()
	var m := head_mat if is_head else body_mat
	var base := HEAD if is_head else OLIVE
	m.albedo_color = Color(1.0, 0.95, 0.8) if not is_head else Color(1.0, 0.35, 0.2)
	_flash_tw = create_tween()
	_flash_tw.tween_property(m, "albedo_color", base, 0.18)


func _fall() -> void:
	is_up = false
	var tw := create_tween()
	tw.tween_property(pivot, "rotation:x", deg_to_rad(-88.0), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Sfx.play_at("target_fall", global_position, -2.0, 1.0, 0.08)
	downed.emit(self, _last_head)
	if respawn:
		tw.tween_interval(respawn_time)
		tw.tween_callback(pop_up)


func pop_up() -> void:
	hp = max_hp
	is_up = true
	var tw := create_tween()
	tw.tween_property(pivot, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play_at("target_up", global_position, -6.0, 1.0, 0.08)


func set_down_instant() -> void:
	is_up = false
	pivot.rotation.x = deg_to_rad(-88.0)


func reset_up_instant() -> void:
	hp = max_hp
	is_up = true
	pivot.rotation.x = 0.0
