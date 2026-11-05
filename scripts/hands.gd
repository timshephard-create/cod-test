extends Node3D
## Primitive arms: two capsule segments plus a box hand per side, posed every frame by
## an analytic two-bone IK toward the current weapon's GripR / GripL targets. The rig
## follows whatever the view model does (pose, spring kick, authored clips) for free.

const UPPER := 0.46
const FORE := 0.46
const SLEEVE := Color(0.14, 0.15, 0.14)
const SKIN := Color(0.62, 0.45, 0.33)

var target_r: Node3D
var target_l: Node3D
var arms: Dictionary = {}


func _ready() -> void:
	arms["r"] = _build_arm(Vector3(0.20, -0.27, 0.16), Vector3(0.50, -0.65, -0.05))
	arms["l"] = _build_arm(Vector3(-0.20, -0.27, 0.16), Vector3(-0.50, -0.65, -0.15))


func _seg(radius: float, length: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = length
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_arm(shoulder: Vector3, pole: Vector3) -> Dictionary:
	var hand := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.07, 0.035, 0.085)
	hand.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = SKIN
	m.roughness = 0.95
	hand.material_override = m
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hand)
	return {
		"shoulder": shoulder,
		"pole": pole,
		"upper": _seg(0.038, UPPER, SLEEVE),
		"fore": _seg(0.032, FORE, SLEEVE),
		"hand": hand,
		"elbow": shoulder,
	}


func set_targets(r: Node3D, l: Node3D) -> void:
	target_r = r
	target_l = l


func _aim_segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var y := b - a
	var len := y.length()
	if len < 0.001:
		return
	y /= len
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	(mi.mesh as CapsuleMesh).height = len + 0.02


func _solve(arm: Dictionary, target: Node3D) -> void:
	var s: Vector3 = arm.shoulder
	var tg: Vector3 = to_local(target.global_position)
	var d := tg - s
	var dist := clampf(d.length(), 0.05, UPPER + FORE - 0.01)
	var dir := d.normalized()
	var pole: Vector3 = arm.pole - s
	var perp := (pole - dir * pole.dot(dir)).normalized()
	var cos_a := clampf((UPPER * UPPER + dist * dist - FORE * FORE) / (2.0 * UPPER * dist), -1.0, 1.0)
	var a := acos(cos_a)
	var elbow := s + dir * (cos(a) * UPPER) + perp * (sin(a) * UPPER)
	var hand_pos := s + dir * dist
	arm.elbow = elbow
	_aim_segment(arm.upper, s, elbow)
	_aim_segment(arm.fore, elbow, hand_pos)
	var hand: MeshInstance3D = arm.hand
	hand.global_transform = Transform3D(target.global_transform.basis.orthonormalized(), target.global_position)


func _process(_delta: float) -> void:
	if target_r and is_instance_valid(target_r):
		_solve(arms.r, target_r)
	if target_l and is_instance_valid(target_l):
		_solve(arms.l, target_l)
