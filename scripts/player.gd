extends CharacterBody3D
## First-person controller + gunplay. Everything that makes the "feel" lives here:
## ADS zoom/sway, recoil pattern + recovery, hip bloom, sprint-to-fire, reload timing,
## view-model bob/kick, hitscan with head/body resolution.

signal fired(def: Dictionary)
signal hit_landed(part: String, killed: bool, points: int, world_pos: Vector3)
signal ammo_changed
signal weapon_changed(def: Dictionary)

const Weapons := preload("res://scripts/weapons.gd")

const BASE_FOV := 80.0
const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.4
const CROUCH_MULT := 0.5
const JUMP_VEL := 4.4
const GRAVITY := 17.0
const SENS := 0.0021
const STAND_H := 1.62
const CROUCH_H := 1.05

var defs: Array = []
var weapon_index := 0
var def: Dictionary
var ammo: Dictionary = {}
var models: Dictionary = {}

var look_enabled := false
var input_enabled := true
var capture_grace := 0.0  # ignore mouse deltas right after pointer lock (browser warp jumps)
var yaw := 0.0
var pitch := 0.0
var mouse_delta := Vector2.ZERO

var ads_amount := 0.0
var ads_held := false
var sprinting := false
var sprint_amount := 0.0
var sprint_out_timer := 0.0
var fire_cooldown := 0.0
var trigger_held := false
var trigger_edge := false
var dry_edge := false
var crouching := false
var crouch_amount := 0.0

var reloading := false
var reload_t := 0.0
var reload_empty := false
var reload_flags := {}

var swapping := false
var swap_t := 0.0
var swap_phase := 0
var swap_to := -1
var lower_amount := 0.0

var pattern_index := 0
var last_shot_time := -10.0
var recoil_target := Vector2.ZERO
var recoil_current := Vector2.ZERO
var spread_bloom := 0.0

var kick_pos := Vector3.ZERO
var kick_vel := Vector3.ZERO
var kick_rot := Vector3.ZERO
var kick_rot_vel := Vector3.ZERO
var sway_rot := Vector3.ZERO
var sway_pos := Vector3.ZERO
var bob_phase := 0.0
var bob_amp := 0.0
var t := 0.0
var flash_timer := 0.0

var stats := {"shots": 0, "hits": 0, "headshots": 0, "kills": 0}

var head: Node3D
var recoil_pivot: Node3D
var camera: Camera3D
var sway_pivot: Node3D
var weapon_root: Node3D
var kick_node: Node3D
var shape: CollisionShape3D
var capsule: CapsuleShape3D
var muzzle_flash: MeshInstance3D
var muzzle_light: OmniLight3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.3
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape = CollisionShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, STAND_H, 0)
	add_child(head)
	recoil_pivot = Node3D.new()
	recoil_pivot.name = "Recoil"
	head.add_child(recoil_pivot)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = BASE_FOV
	camera.near = 0.03
	camera.far = 400.0
	recoil_pivot.add_child(camera)
	camera.current = true
	sway_pivot = Node3D.new()
	sway_pivot.name = "Sway"
	camera.add_child(sway_pivot)
	weapon_root = Node3D.new()
	weapon_root.name = "WeaponRoot"
	sway_pivot.add_child(weapon_root)
	kick_node = Node3D.new()
	kick_node.name = "Kick"
	weapon_root.add_child(kick_node)

	muzzle_flash = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.09, 0.09, 0.09)
	muzzle_flash.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.75, 0.3)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.6, 0.2)
	fmat.emission_energy_multiplier = 4.0
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash.material_override = fmat
	muzzle_flash.visible = false
	kick_node.add_child(muzzle_flash)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.7, 0.35)
	muzzle_light.omni_range = 4.0
	muzzle_light.light_energy = 0.0
	muzzle_light.shadow_enabled = false
	kick_node.add_child(muzzle_light)

	defs = [Weapons.rifle(), Weapons.pistol()]
	for d in defs:
		ammo[d.id] = {"mag": d.mag, "reserve": d.reserve}
		var m := Weapons.build_model(d)
		m.scale = Vector3.ONE * d.model_scale
		m.visible = false
		kick_node.add_child(m)
		models[d.id] = m
	_equip(0)


func _equip(i: int) -> void:
	weapon_index = i
	def = defs[i]
	for k in models:
		models[k].visible = (k == def.id)
	muzzle_flash.position = def.muzzle * def.model_scale
	muzzle_light.position = def.muzzle * def.model_scale + Vector3(0, 0.02, -0.05)
	pattern_index = 0
	recoil_target = Vector2.ZERO
	weapon_changed.emit(def)
	ammo_changed.emit()


func reset_stats() -> void:
	stats = {"shots": 0, "hits": 0, "headshots": 0, "kills": 0}
	for d in defs:
		ammo[d.id] = {"mag": d.mag, "reserve": d.reserve}
	ammo_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and look_enabled and input_enabled:
		if capture_grace > 0.0 or event.relative.length() > 300.0:
			return
		mouse_delta += event.relative
		var s := SENS * lerpf(1.0, def.ads_fov, ads_amount)
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s, deg_to_rad(-85.0), deg_to_rad(85.0))
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_request_swap((weapon_index + 1) % defs.size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_request_swap((weapon_index + defs.size() - 1) % defs.size())
	if event.is_action_pressed("fire"):
		trigger_held = true
		trigger_edge = true
		dry_edge = true
	elif event.is_action_released("fire"):
		trigger_held = false
	if event.is_action_pressed("aim"):
		ads_held = true
	elif event.is_action_released("aim"):
		ads_held = false
	if event.is_action_pressed("reload"):
		_request_reload()
	if event.is_action_pressed("weapon_1"):
		_request_swap(0)
	if event.is_action_pressed("weapon_2"):
		_request_swap(1)
	if event.is_action_pressed("swap"):
		_request_swap((weapon_index + 1) % defs.size())
	if event.is_action_pressed("crouch"):
		crouching = not crouching


func _request_swap(i: int) -> void:
	if i == weapon_index or swapping:
		return
	swapping = true
	swap_phase = 0
	swap_t = 0.0
	swap_to = i
	reloading = false
	Sfx.play("swap", -10.0, 1.0, 0.05)


func _request_reload() -> void:
	if reloading or swapping:
		return
	var a: Dictionary = ammo[def.id]
	if a.mag >= def.mag or a.reserve <= 0:
		return
	reloading = true
	reload_t = 0.0
	reload_empty = a.mag == 0
	reload_flags = {}
	ads_held = false


func _physics_process(delta: float) -> void:
	var fwd := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var side := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	if not input_enabled:
		fwd = 0.0
		side = 0.0
	var wish := Vector2(side, fwd).limit_length(1.0)
	# Firing (or trying to) always suppresses sprint, so holding Shift+LMB shoots.
	var want_sprint := input_enabled and Input.is_action_pressed("sprint") and fwd > 0.3 and not ads_held and not crouching and is_on_floor() and not trigger_held
	if want_sprint and not sprinting:
		sprinting = true
	elif not want_sprint and sprinting:
		sprinting = false
		sprint_out_timer = def.sprint_to_fire
	var speed := WALK_SPEED
	if sprinting:
		speed = SPRINT_SPEED
	speed *= lerpf(1.0, def.ads_move_mult, ads_amount)
	speed *= lerpf(1.0, CROUCH_MULT, crouch_amount)
	var basis := Basis(Vector3.UP, yaw)
	var dir := (basis * Vector3(wish.x, 0, -wish.y))
	var accel := 60.0 if is_on_floor() else 12.0
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_v.z, accel * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif input_enabled and Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VEL
	move_and_slide()


func _process(delta: float) -> void:
	t += delta
	# --- timers -------------------------------------------------------------
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	capture_grace = maxf(0.0, capture_grace - delta)
	sprint_out_timer = maxf(0.0, sprint_out_timer - delta)
	spread_bloom = maxf(0.0, spread_bloom - def.bloom_decay * delta * (0.5 + spread_bloom))
	sprint_amount = move_toward(sprint_amount, 1.0 if sprinting else 0.0, delta / 0.18)
	crouch_amount = move_toward(crouch_amount, 1.0 if crouching else 0.0, delta / 0.22)

	# --- ADS ------------------------------------------------------------------
	var can_ads := input_enabled and ads_held and not sprinting and not reloading and not swapping
	ads_amount = move_toward(ads_amount, 1.0 if can_ads else 0.0, delta / def.ads_time)
	var ads_c := smoothstep(0.0, 1.0, ads_amount)
	camera.fov = lerpf(BASE_FOV, BASE_FOV * def.ads_fov, ads_c) + sprint_amount * 4.0

	# --- reload -----------------------------------------------------------------
	if reloading:
		reload_t += delta
		if reload_t >= def.mag_out_t and not reload_flags.has("out"):
			reload_flags["out"] = true
			Sfx.play("mag_out", -8.0, 1.0, 0.04)
		if reload_t >= def.mag_in_t and not reload_flags.has("in"):
			reload_flags["in"] = true
			Sfx.play("mag_in", -6.0, 1.0, 0.04)
			var a: Dictionary = ammo[def.id]
			var need: int = def.mag - a.mag
			var take: int = mini(need, a.reserve)
			a.mag += take
			a.reserve -= take
			ammo_changed.emit()
		var total: float = def.reload_time + (def.empty_extra if reload_empty else 0.0)
		if reload_empty and reload_t >= def.reload_time + 0.1 and not reload_flags.has("bolt"):
			reload_flags["bolt"] = true
			Sfx.play("bolt", -6.0, 1.0, 0.04)
		if reload_t >= total:
			reloading = false

	# --- swap ---------------------------------------------------------------------
	if swapping:
		swap_t += delta
		if swap_phase == 0:
			lower_amount = clampf(swap_t / def.lower_time, 0.0, 1.0)
			if swap_t >= def.lower_time:
				_equip(swap_to)
				swap_phase = 1
				swap_t = 0.0
		else:
			lower_amount = 1.0 - clampf(swap_t / def.raise_time, 0.0, 1.0)
			if swap_t >= def.raise_time:
				swapping = false
				lower_amount = 0.0

	# --- fire ---------------------------------------------------------------------
	var wants_fire := trigger_held if def.auto else trigger_edge
	var blocked := reloading or swapping or sprinting or sprint_out_timer > 0.0 or not input_enabled
	if wants_fire and not blocked and fire_cooldown <= 0.0:
		var a: Dictionary = ammo[def.id]
		if a.mag > 0:
			_fire()
			trigger_edge = false
		elif dry_edge:
			dry_edge = false
			trigger_edge = false
			Sfx.play("dry_fire", -8.0)
			if a.reserve > 0:
				_request_reload()
	if not def.auto and not wants_fire:
		trigger_edge = false
	if not trigger_held:
		trigger_edge = false

	# --- recoil ---------------------------------------------------------------------
	var since := t - last_shot_time
	if since > def.pattern_reset:
		pattern_index = 0
	recoil_current = recoil_current.lerp(recoil_target, 1.0 - exp(-def.recoil_kick_speed * delta))
	if since > def.recoil_recover_delay:
		recoil_target = recoil_target.lerp(Vector2.ZERO, 1.0 - exp(-def.recoil_recover * delta))
	var aim_sway := Vector2(sin(t * 0.7) * 0.0011 + sin(t * 1.9) * 0.0005, sin(t * 1.1) * 0.0009) * ads_c
	recoil_pivot.rotation = Vector3(deg_to_rad(recoil_current.x) + aim_sway.x, deg_to_rad(recoil_current.y) + aim_sway.y, 0.0)
	rotation.y = yaw
	head.rotation.x = pitch
	head.position.y = lerpf(STAND_H, CROUCH_H, crouch_amount)
	capsule.height = lerpf(1.8, 1.3, crouch_amount)
	shape.position.y = capsule.height * 0.5

	# --- view-model pose -------------------------------------------------------------
	var pos: Vector3 = def.hip_pos.lerp(def.ads_pos, ads_c)
	var rot := Vector3.ZERO
	pos = pos.lerp(def.sprint_pos, sprint_amount)
	rot = rot.lerp(def.sprint_rot, sprint_amount)
	if reloading:
		var total: float = def.reload_time + (def.empty_extra if reload_empty else 0.0)
		var p := clampf(reload_t / total, 0.0, 1.0)
		var s := sin(p * PI)
		rot += Vector3(-0.28 * s, 0.10 * s, 0.42 * s)
		pos += Vector3(0.02 * s, -0.06 * s, 0.02 * s)
		if reload_empty and reload_t > def.reload_time:
			var q := clampf((reload_t - def.reload_time) / def.empty_extra, 0.0, 1.0)
			pos += Vector3(0, 0, 0.03 * sin(q * PI))
	pos += Vector3(0.0, -0.32, 0.05) * lower_amount
	rot += Vector3(-0.75, 0.0, 0.0) * lower_amount
	weapon_root.position = pos
	weapon_root.rotation = rot

	# --- sway + bob --------------------------------------------------------------------
	var sway_scale := lerpf(1.0, 0.18, ads_c)
	var target_rot := Vector3(-mouse_delta.y * 0.0009, -mouse_delta.x * 0.0012, -mouse_delta.x * 0.0007) * sway_scale
	var target_pos := Vector3(-mouse_delta.x * 0.00025, mouse_delta.y * 0.00015, 0.0) * sway_scale
	target_rot = target_rot.clamp(Vector3(-0.08, -0.1, -0.06), Vector3(0.08, 0.1, 0.06))
	target_pos = target_pos.clamp(Vector3(-0.03, -0.02, 0), Vector3(0.03, 0.02, 0))
	mouse_delta = Vector2.ZERO
	sway_rot = sway_rot.lerp(target_rot, 1.0 - exp(-9.0 * delta))
	sway_pos = sway_pos.lerp(target_pos, 1.0 - exp(-9.0 * delta))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var moving := hspeed > 0.5 and is_on_floor()
	var bob_hz := 1.9 + 0.9 * sprint_amount
	if moving:
		var prev := bob_phase
		bob_phase += delta * TAU * bob_hz
		if floori(prev / PI) != floori(bob_phase / PI):
			Sfx.play("footstep", -18.0 + 5.0 * sprint_amount, 1.0, 0.12)
	bob_amp = move_toward(bob_amp, (0.012 + 0.016 * sprint_amount) * (1.0 - 0.85 * ads_c) if moving else 0.0, delta * 0.08)
	var bob := Vector3(sin(bob_phase) * bob_amp, -abs(sin(bob_phase)) * bob_amp * 0.6 + sin(bob_phase * 2.0) * bob_amp * 0.2, 0.0)
	var breathe := Vector3(sin(t * 0.9) * 0.0018, sin(t * 1.6) * 0.0012, 0.0) * (1.0 - 0.75 * ads_c)
	sway_pivot.rotation = sway_rot + Vector3(0, 0, sin(bob_phase) * bob_amp * 0.9)
	sway_pivot.position = sway_pos + bob + breathe

	# --- kick spring ---------------------------------------------------------------------
	_spring(delta, 180.0, 16.0)
	kick_node.position = kick_pos
	kick_node.rotation = kick_rot

	# --- muzzle flash --------------------------------------------------------------------
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			muzzle_flash.visible = false
			muzzle_light.light_energy = 0.0


func _spring(delta: float, k: float, damp: float) -> void:
	# Sub-stepped so the spring stays stable at any frame rate.
	var n := maxi(1, ceili(delta / 0.004))
	var dt := delta / float(n)
	for i in range(n):
		kick_vel += (-kick_pos * k - kick_vel * damp) * dt
		kick_pos += kick_vel * dt
		kick_rot_vel += (-kick_rot * k - kick_rot_vel * damp) * dt
		kick_rot += kick_rot_vel * dt


func current_spread() -> float:
	var s := lerpf(def.hip_spread, def.ads_spread, smoothstep(0.0, 1.0, ads_amount))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	s += def.move_spread * clampf(hspeed / WALK_SPEED, 0.0, 1.3) * (1.0 - 0.7 * ads_amount)
	s += spread_bloom * (1.0 - 0.6 * ads_amount)
	if not is_on_floor():
		s += 2.5
	s *= lerpf(1.0, 0.8, crouch_amount)
	return s


func _fire() -> void:
	var a: Dictionary = ammo[def.id]
	a.mag -= 1
	ammo_changed.emit()
	fire_cooldown = 60.0 / def.rpm
	stats.shots += 1
	last_shot_time = t

	# Recoil: next step of the pattern plus a little randomness.
	var step: Vector2 = def.pattern[mini(pattern_index, def.pattern.size() - 1)]
	pattern_index += 1
	var rnd: float = def.recoil_random
	step += Vector2(randf_range(-rnd, rnd) * 0.5, randf_range(-rnd, rnd))
	step *= lerpf(1.0, def.recoil_ads_mult, ads_amount)
	recoil_target += Vector2(step.x, step.y)
	spread_bloom = minf(def.bloom_max, spread_bloom + def.bloom_per_shot)

	# View-model kick (spring impulse).
	kick_vel += Vector3(randf_range(-0.05, 0.05), 0.08, def.kick_back * 42.0)
	kick_rot_vel += Vector3(def.kick_up * 40.0, randf_range(-0.3, 0.3), randf_range(-1.0, 1.0) * def.kick_roll * 40.0)

	# Flash + audio.
	muzzle_flash.visible = true
	muzzle_flash.rotation = Vector3(randf() * TAU, 0, randf() * TAU)
	muzzle_light.light_energy = 2.5
	flash_timer = 0.035
	Sfx.play(def.shot_sfx, def.shot_db, 1.0, 0.05)
	Sfx.play("shot_tail", -16.0, 1.0, 0.1)
	fired.emit(def)

	# Hitscan with spread cone.
	var xf := camera.global_transform
	var dir := -xf.basis.z
	var ang := deg_to_rad(current_spread()) * sqrt(randf())
	var ph := randf() * TAU
	dir = (dir + xf.basis.x * tan(ang) * cos(ph) + xf.basis.y * tan(ang) * sin(ph)).normalized()
	var from := xf.origin
	var to := from + dir * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var col: Object = r.collider
	if col.has_meta("target_part"):
		var tgt: Node = col.get_meta("target")
		var part: String = col.get_meta("target_part")
		var res: Dictionary = tgt.hit(part, def.damage, def.head_mult, r.position)
		if not res.is_empty():
			stats.hits += 1
			if part == "head":
				stats.headshots += 1
			if res.killed:
				stats.kills += 1
			hit_landed.emit(part, res.killed, res.points, r.position)
	else:
		Sfx.play_at("impact", r.position, -6.0, 1.0, 0.15)
		_spawn_impact(r.position, r.normal)


func _spawn_impact(pos: Vector3, n: Vector3) -> void:
	var holder := get_tree().get_first_node_in_group("impacts")
	if holder == null:
		return
	if holder.get_child_count() > 80:
		holder.get_child(0).queue_free()
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.07, 0.07, 0.004)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.08)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	mi.look_at_from_position(pos + n * 0.003, pos + n, up)
	var tw := mi.create_tween()
	tw.tween_interval(10.0)
	tw.tween_callback(mi.queue_free)


func ammo_text() -> String:
	var a: Dictionary = ammo[def.id]
	return "%d / %d" % [a.mag, a.reserve]
