extends Node3D
## Pooled hit effects: decals, per-surface particle bursts, tracers, and the muzzle
## flash material. Everything is allocated once here; the firing path only re-uses.

const DECAL_POOL := 64
const TRACER_POOL := 4
const BURSTS_PER_SURFACE := 6
const SURFACES := ["concrete", "metal", "wood"]
const TRACER_LIFE := 0.07

var decals: Array = []
var decal_i := 0
var decal_count := 0
var tracers: Array = []
var tracer_life: PackedFloat32Array = PackedFloat32Array()
var tracer_i := 0
var tracer_count := 0
var bursts: Dictionary = {}
var burst_i: Dictionary = {}
var burst_count := 0
var decal_tex: ImageTexture
var flash_tex: ImageTexture
var _tmp_up := Vector3.UP


func _ready() -> void:
	add_to_group("fx")
	decal_tex = _make_decal_texture()
	flash_tex = _make_flash_texture()
	# Decals: one shared material, pooled quads.
	var dmat := StandardMaterial3D.new()
	dmat.albedo_texture = decal_tex
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	dmat.alpha_scissor_threshold = 0.3
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.9, 0.9, 0.9)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	for i in range(DECAL_POOL):
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = dmat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		decals.append(mi)
	# Tracers: thin emissive boxes scaled along their length.
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(1.0, 0.85, 0.45)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.albedo_color.a = 0.85
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(0.012, 0.012, 1.0)
	tracer_life.resize(TRACER_POOL)
	for i in range(TRACER_POOL):
		var mi := MeshInstance3D.new()
		mi.mesh = tmesh
		mi.material_override = tmat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		tracers.append(mi)
		tracer_life[i] = 0.0
	# Particle bursts keyed by surface.
	for s in SURFACES:
		bursts[s] = []
		burst_i[s] = 0
		for i in range(BURSTS_PER_SURFACE):
			var p := _make_burst(s)
			add_child(p)
			bursts[s].append(p)


func _make_burst(surface: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0, -1)
	m.gravity = Vector3(0, -9.8, 0)
	var mesh: Mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match surface:
		"metal":
			p.amount = 14
			p.lifetime = 0.35
			m.spread = 50.0
			m.initial_velocity_min = 3.0
			m.initial_velocity_max = 7.0
			m.scale_min = 0.6
			m.scale_max = 1.2
			m.color = Color(1.0, 0.8, 0.35)
			var b := BoxMesh.new()
			b.size = Vector3(0.012, 0.012, 0.05)
			mesh = b
			mat.albedo_color = Color(1.0, 0.75, 0.3)
		"wood":
			p.amount = 10
			p.lifetime = 0.5
			m.spread = 60.0
			m.initial_velocity_min = 1.5
			m.initial_velocity_max = 4.0
			m.scale_min = 0.7
			m.scale_max = 1.4
			m.color = Color(0.55, 0.38, 0.2)
			var b := BoxMesh.new()
			b.size = Vector3(0.02, 0.01, 0.03)
			mesh = b
			mat.albedo_color = Color(0.5, 0.35, 0.18)
		_:
			p.amount = 10
			p.lifetime = 0.55
			m.spread = 70.0
			m.initial_velocity_min = 0.8
			m.initial_velocity_max = 2.5
			m.gravity = Vector3(0, -2.0, 0)
			m.scale_min = 0.8
			m.scale_max = 1.6
			m.color = Color(0.6, 0.58, 0.52, 0.8)
			var q := QuadMesh.new()
			q.size = Vector2(0.07, 0.07)
			mesh = q
			mat.albedo_color = Color(0.62, 0.6, 0.55, 0.7)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.damping_min = 1.0
	m.damping_max = 3.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	(mesh as PrimitiveMesh).material = mat
	p.process_material = m
	p.draw_pass_1 = mesh
	p.material_override = mat
	return p


func _make_decal_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var dx := (x + 0.5) / n - 0.5
			var dy := (y + 0.5) / n - 0.5
			var r := sqrt(dx * dx + dy * dy) * 2.0
			var noise := fmod(absf(sin(x * 12.9898 + y * 78.233) * 43758.5453), 1.0)
			var a := clampf(1.0 - r * r, 0.0, 1.0) * (0.55 + 0.45 * noise)
			var shade := 0.05 + 0.12 * noise
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return ImageTexture.create_from_image(img)


func _make_flash_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var dx := (x + 0.5) / n - 0.5
			var dy := (y + 0.5) / n - 0.5
			var r := sqrt(dx * dx + dy * dy) * 2.0
			var core := clampf(1.0 - r * 1.6, 0.0, 1.0)
			var arms := 0.0
			for k in range(4):
				var ang := k * PI / 4.0
				var ax := cos(ang)
				var ay := sin(ang)
				var along := absf(dx * ax + dy * ay) * 2.0
				var across := absf(-dx * ay + dy * ax) * 2.0
				arms = maxf(arms, clampf(1.0 - across * 9.0, 0.0, 1.0) * clampf(1.0 - along * 1.1, 0.0, 1.0))
			var a := clampf(core * core * 1.2 + arms * 0.9, 0.0, 1.0)
			var c := Color(1.0, 0.85 - 0.35 * r, 0.45 - 0.3 * r, a)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func make_flash_quad() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = flash_tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


func _orient(node: Node3D, pos: Vector3, n: Vector3) -> void:
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	node.look_at_from_position(pos, pos + n, up)


func decal(pos: Vector3, n: Vector3) -> void:
	var mi: MeshInstance3D = decals[decal_i]
	decal_i = (decal_i + 1) % DECAL_POOL
	decal_count += 1
	mi.visible = true
	_orient(mi, pos + n * 0.004, n)
	mi.rotate_object_local(Vector3(0, 0, 1), randf() * TAU)


func burst(surface: String, pos: Vector3, n: Vector3) -> void:
	if not bursts.has(surface):
		surface = "concrete"
	var arr: Array = bursts[surface]
	var p: GPUParticles3D = arr[burst_i[surface]]
	burst_i[surface] = (burst_i[surface] + 1) % BURSTS_PER_SURFACE
	burst_count += 1
	_orient(p, pos + n * 0.01, n)
	p.restart()


func tracer(from: Vector3, to: Vector3) -> void:
	var mi: MeshInstance3D = tracers[tracer_i]
	tracer_life[tracer_i] = TRACER_LIFE
	tracer_i = (tracer_i + 1) % TRACER_POOL
	tracer_count += 1
	var d := to - from
	var len := d.length()
	if len < 0.2:
		return
	mi.visible = true
	var mid := from + d * 0.5
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	mi.look_at_from_position(mid, to, up)
	mi.scale = Vector3(1, 1, len)


func visible_decals() -> int:
	var c := 0
	for mi in decals:
		if mi.visible:
			c += 1
	return c


func _process(delta: float) -> void:
	for i in range(TRACER_POOL):
		if tracer_life[i] > 0.0:
			tracer_life[i] -= delta
			if tracer_life[i] <= 0.0:
				tracers[i].visible = false
