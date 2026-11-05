extends Node3D
## Builds the level (shooting range -> alley), spawns targets and zones, runs the
## timed course, and publishes state to JS on web builds for automated checks.

const PlayerScript := preload("res://scripts/player.gd")
const TargetScript := preload("res://scripts/target.gd")
const HudScript := preload("res://scripts/hud.gd")
const FxScript := preload("res://scripts/fx.gd")

const COURSE_LIMIT := 90.0
const TIME_BONUS_FROM := 75.0

enum State { PRACTICE, COUNTDOWN, RUNNING, FINISHED }

var state := State.PRACTICE
var course_time := 0.0
var countdown := 0.0
var score := 0
var best := 0
var player: CharacterBody3D
var hud: CanvasLayer
var world: Node3D
var targets: Array = []
var range_targets: Array = []
var alley_groups: Dictionary = {}
var zones_fired: Dictionary = {}
var start_zone_in := false
var finish_zone_in := false
var was_captured := false
var paused := false
var frame := 0
var mats: Dictionary = {}
var low_fx := false
var sun: DirectionalLight3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_load_best()
	_detect_low_fx()
	_build_environment()
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var fx := FxScript.new()
	fx.name = "Fx"
	world.add_child(fx)
	_build_level()
	_build_targets()
	_build_zones()

	player = PlayerScript.new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(player)
	player.position = Vector3(0, 0.1, 2.0)
	player.hit_landed.connect(_on_hit)
	player.fired.connect(_on_fired)

	hud = HudScript.new()
	add_child(hud)
	hud.bind(player)
	hud.set_timer("PRACTICE")
	hud.set_score("BEST %d" % best)
	_set_prompt()
	if "--autotest" in OS.get_cmdline_user_args():
		var at: Script = load("res://tests/autotest.gd")
		if at:
			add_child(at.new())


# ---------------------------------------------------------------------------
# Level
# ---------------------------------------------------------------------------

func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var key := "%s_%f" % [c.to_html(), rough]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, color: Color, rot_y := 0.0, parent: Node3D = null, surface := "concrete") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	sb.add_child(mi)
	sb.position = pos
	sb.rotation.y = rot_y
	(parent if parent else world).add_child(sb)
	return sb


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.42, 0.68)
	sm.sky_horizon_color = Color(0.72, 0.76, 0.80)
	sm.ground_bottom_color = Color(0.2, 0.19, 0.17)
	sm.ground_horizon_color = Color(0.6, 0.58, 0.52)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.5
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.85
	e.fog_enabled = true
	e.fog_light_color = Color(0.7, 0.74, 0.8)
	e.fog_density = 0.004
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = not low_fx
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	if low_fx:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().scaling_3d_scale = 0.5


## "?low" in the page URL (web) or --low on the command line turns off shadows
## and MSAA and halves 3D resolution, for weak GPUs and software renderers.
func _detect_low_fx() -> void:
	if OS.has_feature("web"):
		var q: String = str(JavaScriptBridge.eval("window.location.search", true))
		low_fx = q.find("low") >= 0
	else:
		low_fx = "--low" in OS.get_cmdline_user_args()


func _build_level() -> void:
	var concrete := Color(0.40, 0.39, 0.36)
	var concrete_d := Color(0.34, 0.33, 0.31)
	var brick := Color(0.48, 0.3, 0.24)
	var brick2 := Color(0.38, 0.26, 0.22)
	var plaster := Color(0.62, 0.58, 0.5)
	var wood := Color(0.5, 0.36, 0.2)
	var metal := Color(0.25, 0.27, 0.3)
	var green := Color(0.2, 0.35, 0.22)
	var h := 4.0

	# ---- Range: x -8..8, z +4..-36, firing line at z=0 ----
	_box(Vector3(16, 0.4, 40), Vector3(0, -0.2, -16), Color(0.36, 0.35, 0.32))  # floor
	_box(Vector3(16, 0.1, 1.0), Vector3(0, 0.05, 0.0), Color(1.0, 0.85, 0.4))  # firing line stripe
	for i in range(3):
		var x := -5.0 + i * 5.0
		_box(Vector3(1.2, 1.1, 0.6), Vector3(x, 0.55, 0.6), wood, 0.0, null, "wood")  # shooting benches
	_box(Vector3(0.4, h, 40), Vector3(-8.2, h / 2, -16), concrete_d)  # left wall
	_box(Vector3(0.4, h, 29), Vector3(8.2, h / 2, -10.5), concrete_d)  # right wall (to z=-25)
	_box(Vector3(0.4, h, 8), Vector3(8.2, h / 2, -32), concrete_d)  # right wall past the door (z -28..-36)
	_box(Vector3(16.8, h, 0.4), Vector3(0, h / 2, 4.2), concrete_d)  # back wall
	_box(Vector3(16.8, 2.0, 1.0), Vector3(0, 1.0, -36.5), Color(0.45, 0.4, 0.3))  # berm low
	_box(Vector3(16.8, h + 2, 0.6), Vector3(0, (h + 2) / 2, -37.3), Color(0.35, 0.32, 0.25))  # backstop
	for i in range(2):  # lane dividers
		var x := -2.5 + i * 5.0
		_box(Vector3(0.15, 1.6, 3.0), Vector3(x, 0.8, 0.6), metal, 0.0, null, "metal")
	_box(Vector3(4, 0.3, 4), Vector3(0, 0.15, 2.0), Color(0.85, 0.85, 0.85))  # start pad
	_box(Vector3(2.0, 2.4, 0.4), Vector3(0, 1.2, 4.0), Color(0.1, 0.1, 0.1))  # sign board
	# Door frame on the right wall at z -25..-28 (gap 3m) with a lintel.
	_box(Vector3(0.4, 1.0, 3.2), Vector3(8.2, 3.5, -26.5), concrete_d)

	# ---- Alley A: runs +x from x=8 to x=30 at z -25..-29 (width 4) ----
	_box(Vector3(24, 0.4, 4.4), Vector3(20, -0.2, -27), Color(0.33, 0.33, 0.34))  # asphalt
	_box(Vector3(22, 6.5, 0.5), Vector3(19.2, 3.25, -24.55), brick)  # north wall (z=-24.8)
	_box(Vector3(22, 6.5, 0.5), Vector3(19.2, 3.25, -29.45), brick2)  # south wall (z=-29.2)
	_box(Vector3(0.5, 6.5, 5), Vector3(30.25, 3.25, -29.0), plaster)  # end wall segment (south of turn)
	# Props in A.
	_box(Vector3(1.2, 1.0, 1.2), Vector3(13, 0.5, -28.3), wood, 0.0, null, "wood")
	_box(Vector3(1.0, 0.8, 1.0), Vector3(14.2, 0.4, -28.5), wood, 0.0, null, "wood")
	_box(Vector3(1.2, 1.0, 1.2), Vector3(13, 1.5, -28.3), wood, 0.0, null, "wood")
	_box(Vector3(2.0, 1.4, 1.0), Vector3(21, 0.7, -25.4), green, 0.0, null, "metal")  # dumpster
	_box(Vector3(0.5, 2.6, 0.5), Vector3(25, 1.3, -26.0), concrete)  # pillar
	for i in range(4):  # window ledges / AC units on the north wall
		_box(Vector3(1.4, 0.5, 0.6), Vector3(11.0 + i * 5.0, 3.6, -24.5), metal, 0.0, null, "metal")

	# ---- Alley B: runs -z from z=-25 to z=-49 at x 28..32 ----
	_box(Vector3(4.4, 0.4, 24), Vector3(30, -0.2, -37), Color(0.33, 0.33, 0.34))
	_box(Vector3(0.5, 6.5, 20.5), Vector3(32.25, 3.25, -39.25), brick2)  # east wall (z -29 .. -49.5)
	_box(Vector3(0.5, 6.5, 2.0), Vector3(32.25, 3.25, -26.0), brick2)  # east wall stub near turn
	_box(Vector3(0.5, 6.5, 2.0), Vector3(32.25, 3.25, -28.5), brick2)
	_box(Vector3(0.5, 6.5, 20), Vector3(27.75, 3.25, -39.5), plaster)  # west wall (z -29.5 .. -49.5)
	_box(Vector3(1.0, 1.0, 1.0), Vector3(28.6, 0.5, -34), wood, 0.0, null, "wood")
	_box(Vector3(1.0, 0.6, 1.0), Vector3(31.4, 0.3, -40), wood, 0.0, null, "wood")
	_box(Vector3(1.8, 1.0, 0.9), Vector3(29.0, 0.5, -45), green, 0.0, null, "metal")
	_box(Vector3(0.5, 6.5, 0.5), Vector3(31.0, 3.25, -37.5), concrete)  # drainpipe-ish column

	# ---- Alley C: runs +x from x=28 to x=50 at z -47..-51 ----
	_box(Vector3(24, 0.4, 4.4), Vector3(40, -0.2, -49), Color(0.33, 0.33, 0.34))
	_box(Vector3(18, 6.5, 0.5), Vector3(41.25, 3.25, -46.75), brick)  # north wall (x 32.25..50.25)
	_box(Vector3(22.5, 6.5, 0.5), Vector3(39.0, 3.25, -51.25), brick2)  # south wall
	_box(Vector3(0.5, 6.5, 5), Vector3(50.25, 3.25, -49.0), plaster)  # end wall
	_box(Vector3(0.5, 6.5, 4), Vector3(27.75, 3.25, -49.5), plaster)  # west closure
	_box(Vector3(1.0, 1.2, 1.0), Vector3(36, 0.6, -50.5), wood, 0.0, null, "wood")
	_box(Vector3(2.4, 1.3, 1.0), Vector3(44, 0.65, -47.5), green, 0.0, null, "metal")
	_box(Vector3(3, 0.3, 3), Vector3(48, 0.15, -49), Color(0.85, 0.85, 0.85))  # finish pad
	# Elevated spot in C: a raised ledge where a high target sits.
	_box(Vector3(2.0, 0.3, 1.2), Vector3(41, 2.8, -47.2), metal, 0.0, null, "metal")


func _add_target(pos: Vector3, rot_y: float, respawn: bool, group: String) -> Node3D:
	var tg := TargetScript.new()
	tg.position = pos
	tg.rotation.y = rot_y
	tg.respawn = respawn
	world.add_child(tg)
	tg.downed.connect(_on_target_downed)
	targets.append(tg)
	if group == "range":
		range_targets.append(tg)
	else:
		if not alley_groups.has(group):
			alley_groups[group] = []
		alley_groups[group].append(tg)
		tg.set_down_instant()
	return tg


func _build_targets() -> void:
	# Range: three lanes at increasing distance.
	for i in range(3):
		var x := -5.0 + i * 5.0
		_add_target(Vector3(x, 0, -9.0 - i * 1.5), 0.0, true, "range")
		_add_target(Vector3(x + 1.2, 0, -19.0 + i * 1.0), 0.0, true, "range")
		_add_target(Vector3(x - 0.8, 0, -31.0), 0.0, true, "range")
	# Alley A: pop when entering A.
	_add_target(Vector3(17.0, 0, -25.6), PI / 2.0, false, "A")
	_add_target(Vector3(22.5, 0, -28.4), PI / 2.0, false, "A")
	_add_target(Vector3(28.5, 0, -26.0), PI / 2.0, false, "A")
	# Alley B.
	_add_target(Vector3(31.2, 0, -33.0), 0.0, false, "B")
	_add_target(Vector3(28.7, 0, -41.0), 0.0, false, "B")
	_add_target(Vector3(30.5, 0, -48.0), 0.0, false, "B")
	# Alley C (one elevated on the ledge).
	_add_target(Vector3(36.0, 0, -47.8), PI / 2.0, false, "C")
	_add_target(Vector3(41.0, 2.95, -47.3), PI / 2.0, false, "C")
	_add_target(Vector3(46.5, 0, -50.2), PI / 2.0, false, "C")


func _zone(size: Vector3, pos: Vector3, cb: Callable) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 8
	a.collision_mask = 4
	a.monitoring = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	a.position = pos
	a.body_entered.connect(func(_b): cb.call(true))
	a.body_exited.connect(func(_b): cb.call(false))
	world.add_child(a)
	return a


func _build_zones() -> void:
	_zone(Vector3(4, 3, 4), Vector3(0, 1.5, 2.0), func(inside): start_zone_in = inside; _set_prompt())
	_zone(Vector3(4, 4, 4), Vector3(10.5, 2, -27), func(inside): if inside: _trigger_group("A"))
	_zone(Vector3(4, 4, 4), Vector3(30, 2, -27), func(inside): if inside: _trigger_group("B"))
	_zone(Vector3(4, 4, 4), Vector3(30, 2, -49), func(inside): if inside: _trigger_group("C"))
	_zone(Vector3(3, 3, 3), Vector3(48, 1.5, -49), func(inside): finish_zone_in = inside; _set_prompt(); if inside: _finish())


# ---------------------------------------------------------------------------
# Course
# ---------------------------------------------------------------------------

func _set_prompt() -> void:
	match state:
		State.PRACTICE:
			if start_zone_in:
				hud.set_prompt("Press E to start the course")
			else:
				hud.set_prompt("Free practice. Stand on the white pad behind you to start the course.")
		State.COUNTDOWN:
			hud.set_prompt("")
		State.RUNNING:
			hud.set_prompt("Clear the range, then push through the door on the right into the alley.")
		State.FINISHED:
			hud.set_prompt("Press Enter to run it again")


func _trigger_group(g: String) -> void:
	if state != State.RUNNING or zones_fired.has(g):
		return
	zones_fired[g] = true
	var delay := 0.0
	for tg in alley_groups[g]:
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(tg.pop_up)
		delay += 0.35


func _start_course() -> void:
	state = State.COUNTDOWN
	countdown = 3.0
	score = 0
	zones_fired.clear()
	player.reset_stats()
	hud.hide_results()
	for tg in range_targets:
		tg.respawn = false
		tg.reset_up_instant()
	for g in alley_groups:
		for tg in alley_groups[g]:
			tg.set_down_instant()
	hud.set_score("SCORE 0")
	_set_prompt()


func _finish() -> void:
	if state != State.RUNNING:
		return
	state = State.FINISHED
	Sfx.play("finish", -4.0)
	var time_bonus := int(maxf(0.0, TIME_BONUS_FROM - course_time) * 10.0)
	var s: Dictionary = player.stats
	var acc := 0.0
	if s.shots > 0:
		acc = float(s.hits) / float(s.shots)
	var acc_bonus := int(acc * 200.0)
	score += time_bonus + acc_bonus
	var new_best := score > best
	if new_best:
		best = score
		_save_best()
	hud.set_score("SCORE %d" % score)
	hud.set_timer("%s" % _fmt(course_time), Color(1.0, 0.85, 0.4))
	hud.show_results(
		"COURSE COMPLETE\n\nTime  %s\nTargets  %d / %d\nHeadshots  %d\nAccuracy  %d%%  (%d / %d)\n\nTime bonus  +%d\nAccuracy bonus  +%d\n\nSCORE  %d%s\n\nPress Enter to go again"
		% [_fmt(course_time), s.kills, targets.size(), s.headshots, int(acc * 100.0), s.hits, s.shots, time_bonus, acc_bonus, score, "   NEW BEST" if new_best else "   (best %d)" % best]
	)
	_set_prompt()


func _fail_time() -> void:
	state = State.FINISHED
	var s: Dictionary = player.stats
	hud.set_timer("TIME", Color(1.0, 0.35, 0.3))
	hud.show_results("OUT OF TIME\n\nTargets  %d / %d\nHeadshots  %d\nSCORE  %d\n\nPress Enter to go again" % [s.kills, targets.size(), s.headshots, score])
	_set_prompt()


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _on_hit(_part: String, _killed: bool, points: int, _pos: Vector3) -> void:
	if state == State.RUNNING:
		score += points
		hud.set_score("SCORE %d" % score)


func _on_fired(_def: Dictionary) -> void:
	pass


func _on_target_downed(_tg: Node3D, _headshot: bool) -> void:
	# Subtle camera kick when a target drops.
	player.add_shake(0.25)


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://best.cfg") == OK:
		best = int(cf.get_value("course", "best", 0))


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("course", "best", best)
	cf.save("user://best.cfg")


# ---------------------------------------------------------------------------
# Input / loop
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			player.look_enabled = true
			player.capture_grace = 0.15
			_set_paused(false)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("interact") and state == State.PRACTICE and start_zone_in:
		_start_course()
	elif event.is_action_pressed("restart") and state == State.FINISHED:
		_restart()


func _restart() -> void:
	state = State.PRACTICE
	course_time = 0.0
	score = 0
	hud.hide_results()
	hud.set_timer("PRACTICE")
	hud.set_score("BEST %d" % best)
	player.position = Vector3(0, 0.1, 2.0)
	player.yaw = 0.0
	player.pitch = 0.0
	player.velocity = Vector3.ZERO
	for tg in range_targets:
		tg.respawn = true
		tg.reset_up_instant()
	for g in alley_groups:
		for tg in alley_groups[g]:
			tg.set_down_instant()
	_set_prompt()


func _set_paused(p: bool) -> void:
	paused = p
	get_tree().paused = p
	hud.set_overlay(p, "PAUSED\n\nClick to resume" if p else "RANGE DAY\n\nClick to play")


func _process(delta: float) -> void:
	frame += 1
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if was_captured and not captured and not paused:
		_set_paused(true)
	elif captured and paused:
		_set_paused(false)
	was_captured = captured
	if not player.look_enabled:
		hud.set_overlay(true)
	elif not paused:
		hud.set_overlay(false)

	if paused:
		_publish()
		return
	match state:
		State.COUNTDOWN:
			var prev := countdown
			countdown -= delta
			if ceili(prev) != ceili(countdown) and countdown > 0.0:
				Sfx.play("countdown", -6.0)
			hud.set_timer("%d" % ceili(maxf(countdown, 0.0)), Color(1.0, 0.85, 0.4))
			if countdown <= 0.0:
				state = State.RUNNING
				course_time = 0.0
				Sfx.play("start", -4.0)
				hud.set_timer("GO")
				_set_prompt()
		State.RUNNING:
			course_time += delta
			var left := COURSE_LIMIT - course_time
			hud.set_timer(_fmt(course_time), Color(1.0, 0.35, 0.3) if left < 10.0 else Color.WHITE)
			if left <= 0.0:
				_fail_time()
	_publish()


func _publish() -> void:
	if not OS.has_feature("web"):
		return
	var a: Dictionary = player.ammo[player.def.id]
	var d := {
		"state": State.keys()[state],
		"time": snappedf(course_time, 0.01),
		"score": score,
		"best": best,
		"shots": player.stats.shots,
		"hits": player.stats.hits,
		"headshots": player.stats.headshots,
		"kills": player.stats.kills,
		"weapon": player.def.id,
		"mag": a.mag,
		"reserve": a.reserve,
		"ads": snappedf(player.ads_amount, 0.01),
		"fov": snappedf(player.camera.fov, 0.1),
		"spread": snappedf(player.current_spread(), 0.01),
		"recoil": [snappedf(player.recoil_current.x, 0.01), snappedf(player.recoil_current.y, 0.01)],
		"reloading": player.reloading,
		"sprinting": player.sprinting,
		"tac": player.tac_sprinting,
		"sliding": player.sliding,
		"fov_kick": snappedf(player.fov_kick, 0.1),
		"shake": snappedf(player.shake_energy, 0.001),
		"sprint_out": snappedf(player.sprint_out_timer, 0.01),
		"pos": [snappedf(player.position.x, 0.1), snappedf(player.position.y, 0.1), snappedf(player.position.z, 0.1)],
		"yaw": snappedf(player.yaw, 0.001),
		"pitch": snappedf(player.pitch, 0.001),
		"captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"look": player.look_enabled,
		"paused": paused,
		"fps": Engine.get_frames_per_second(),
		"frame": frame,
		"targets_up": targets.filter(func(x): return x.is_up).size(),
	}
	JavaScriptBridge.eval("window.__rangeday = %s;" % JSON.stringify(d), true)
