extends Node
## Headless gameplay test. Run:  godot --headless --path . -- --autotest
## Drives the real input pipeline with synthetic events and checks the feel timings.

var main: Node
var player: Node
var game_t := 0.0
var fails := 0
var checks := 0

signal tick


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = get_parent()
	player = main.player
	Engine.max_fps = 120
	_run.call_deferred()


func _process(delta: float) -> void:
	game_t += delta
	tick.emit()


func wait(sec: float) -> void:
	var until := game_t + sec
	while game_t < until:
		await tick


func key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func press(code: Key) -> void:
	key(code, true)
	await tick
	key(code, false)
	await tick


func mouse(button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = Vector2(640, 360)
	Input.parse_input_event(e)


func check(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		fails += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])


func aim_at(world_pos: Vector3) -> void:
	var cam_pos: Vector3 = player.camera.global_position
	var d: Vector3 = world_pos - cam_pos
	player.yaw = atan2(-d.x, -d.z)
	player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	player.recoil_target = Vector2.ZERO
	player.recoil_current = Vector2.ZERO
	await tick
	await tick


func _run() -> void:
	await wait(0.5)
	check("start zone detects player at spawn", main.start_zone_in)
	check("practice targets up", main.targets.filter(func(x): return x.is_up).size() == 9, str(main.targets.size()))

	# Click to enable look.
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.3)
	check("click enables look", player.look_enabled)

	# ADS timing: rifle ads_time 0.24 s, fov 80 -> 57.6.
	mouse(MOUSE_BUTTON_RIGHT, true)
	await wait(0.12)
	var mid: float = player.ads_amount
	await wait(0.25)
	check("ADS halfway at 0.12 s", mid > 0.3 and mid < 0.7, "ads=%.2f" % mid)
	check("ADS complete by 0.37 s", player.ads_amount >= 0.99 and absf(player.camera.fov - 57.6) < 0.2, "fov=%.1f" % player.camera.fov)
	check("ADS spread tight", player.current_spread() < 0.2, "spread=%.2f" % player.current_spread())

	# Headshot on the near centre-lane target (0,0,-9): head centre y=1.28.
	var tg: Node3D = main.range_targets[3]
	await aim_at(tg.global_position + Vector3(0, 1.28, 0))
	var hs0: int = player.stats.headshots
	var score_before: int = main.score
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick
	await tick
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.08)
	check("rifle fires on trigger", player.stats.shots >= 1, "shots=%d" % player.stats.shots)
	check("headshot registered", player.stats.headshots == hs0 + 1, "hits=%d head=%d" % [player.stats.hits, player.stats.headshots])
	check("hitmarker shown", main.hud.hit_timer > 0.0 and main.hud.hit_kind == 1)
	check("practice does not score", main.score == score_before)
	check("recoil kicked up", player.recoil_current.x > 0.5, "recoil=%s" % str(player.recoil_current))
	await wait(1.0)
	check("recoil recovered within 1 s", absf(player.recoil_current.x) < 0.15, "recoil=%s" % str(player.recoil_current))
	await aim_at(tg.global_position + Vector3(0, 0.6, 0))
	var k0: int = player.stats.kills
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.35)
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.1)
	check("full-auto burst ~760 rpm", player.stats.shots >= 4 and player.stats.shots <= 7, "shots=%d" % player.stats.shots)
	check("recoil climbs through burst", player.recoil_current.x > 2.0, "recoil=%s" % str(player.recoil_current))
	check("body hits + kill on sustained fire", player.stats.kills == k0 + 1 and not tg.is_up, "kills=%d hits=%d" % [player.stats.kills, player.stats.hits])
	mouse(MOUSE_BUTTON_RIGHT, false)
	await wait(0.4)
	check("ADS releases", player.ads_amount < 0.05)

	# Reload timing: mag_in at 1.35 s, done at 2.05 s.
	var mag_before: int = player.ammo["rifle"].mag
	await press(KEY_R)
	await wait(1.1)
	check("reload in progress, mag not yet refilled at 1.1 s", player.reloading and player.ammo["rifle"].mag == mag_before)
	await wait(0.4)
	check("mag refilled by 1.5 s", player.ammo["rifle"].mag == 30, "mag=%d" % player.ammo["rifle"].mag)
	check("still in reload animation at 1.5 s", player.reloading)
	await wait(0.7)
	check("reload complete at 2.2 s", not player.reloading)

	# Sprint-to-fire delay: 0.28 s for the rifle.
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	await wait(0.5)
	check("sprinting", player.sprinting and player.sprint_amount > 0.9, "fov=%.1f" % player.camera.fov)
	var s0: int = player.stats.shots
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.18)
	check("no shot 0.18 s after trigger from sprint", player.stats.shots == s0 and not player.sprinting, "shots=%d sprint_out=%.2f" % [player.stats.shots - s0, player.sprint_out_timer])
	await wait(0.25)
	check("fires once sprint-out elapses", player.stats.shots > s0, "shots=%d" % (player.stats.shots - s0))
	mouse(MOUSE_BUTTON_LEFT, false)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await wait(0.3)

	# Pistol: swap, semi-auto.
	await press(KEY_2)
	await wait(0.3)
	check("swap lowers rifle first", player.swapping)
	await wait(0.5)
	check("pistol equipped", player.def.id == "pistol" and not player.swapping)
	var p0: int = player.stats.shots
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.5)
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.1)
	check("pistol is semi-auto (hold = 1 shot)", player.stats.shots == p0 + 1, "shots=%d" % (player.stats.shots - p0))
	check("pistol recoil snappier", player.recoil_current.x < 1.0, "recoil=%s" % str(player.recoil_current))
	await press(KEY_1)
	await wait(0.9)

	# Course: start, run, score, finish.
	player.position = Vector3(0, 0.1, 2.0)
	player.velocity = Vector3.ZERO
	await wait(0.3)
	check("back on start pad", main.start_zone_in)
	await press(KEY_E)
	await wait(0.1)
	check("countdown begins", main.state == main.State.COUNTDOWN)
	await wait(3.2)
	check("course running after countdown", main.state == main.State.RUNNING, str(main.state))
	check("targets reset for course", main.range_targets.filter(func(x): return x.is_up).size() == 9)
	check("stats reset", player.stats.shots == 0 and player.ammo["rifle"].mag == 30)
	var tg2: Node3D = main.range_targets[0]
	await aim_at(tg2.global_position + Vector3(0, 1.28, 0))
	mouse(MOUSE_BUTTON_RIGHT, true)
	await wait(0.3)
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick
	await tick
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.2)
	check("course headshot scores 25", main.score == 25, "score=%d" % main.score)
	await aim_at(tg2.global_position + Vector3(0, 0.6, 0))
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.4)
	mouse(MOUSE_BUTTON_LEFT, false)
	mouse(MOUSE_BUTTON_RIGHT, false)
	await wait(0.2)
	check("kill adds +50 and target stays down (no respawn in course)", not tg2.is_up and main.score >= 25 + 10 + 50, "score=%d" % main.score)
	var before_up: int = main.targets.filter(func(x): return x.is_up).size()
	player.position = Vector3(10.5, 0.1, -27.0)
	player.velocity = Vector3.ZERO
	await wait(1.6)
	var after_up: int = main.targets.filter(func(x): return x.is_up).size()
	check("alley zone A pops 3 targets", after_up == before_up + 3, "%d -> %d" % [before_up, after_up])
	player.position = Vector3(30, 0.1, -27.0)
	await wait(1.6)
	player.position = Vector3(30, 0.1, -49.0)
	await wait(1.6)
	check("zones B and C pop their targets", main.targets.filter(func(x): return x.is_up).size() == after_up + 6)
	var t_before: float = main.course_time
	var sc_before: int = main.score
	player.position = Vector3(48, 0.1, -49.0)
	await wait(0.5)
	check("finish pad ends the course", main.state == main.State.FINISHED, str(main.state))
	check("time bonus applied", main.score > sc_before and main.best == main.score, "score=%d best=%d t=%.1f" % [main.score, main.best, t_before])
	check("results panel visible", main.hud.results.visible)
	await press(KEY_ENTER)
	await wait(0.3)
	check("enter restarts to practice", main.state == main.State.PRACTICE and main.range_targets.filter(func(x): return x.is_up).size() == 9)

	await _movement_tests()
	await _fx_tests()
	await _anim_tests()

	print("AUTOTEST %d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails > 0 else 0)


func hspeed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func reset_player() -> void:
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	mouse(MOUSE_BUTTON_LEFT, false)
	mouse(MOUSE_BUTTON_RIGHT, false)
	# Clear lane down the range (the spawn pad has a bench right in front of it).
	player.position = Vector3(3.0, 0.1, -3.0)
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.pitch = 0.0
	player.crouching = false
	player.sliding = false
	player.slide_cooldown_t = 0.0
	player.tac_rearm_t = 0.0
	await wait(0.4)


## Step 2 (pass 2): tactical sprint, slide, FOV kicks.
func _movement_tests() -> void:
	var mv: Dictionary = player.mv
	await reset_player()
	# Regular sprint.
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	await wait(0.9)
	check("sprint speed matches table", absf(hspeed() - mv.sprint_speed) < 0.3, "v=%.2f" % hspeed())
	check("sprint FOV kick +%.0f" % mv.fov_sprint, absf(player.camera.fov - (80.0 + mv.fov_sprint)) < 0.5 and not player.tac_sprinting, "fov=%.2f" % player.camera.fov)
	# Shift again while sprinting -> tactical sprint.
	key(KEY_SHIFT, false)
	key(KEY_SHIFT, true)
	await wait(0.7)
	check("shift again while sprinting -> tactical sprint", player.tac_sprinting, "")
	check("tac sprint speed matches table", absf(hspeed() - mv.tac_sprint_speed) < 0.3, "v=%.2f" % hspeed())
	check("tac sprint FOV kick +%.0f" % mv.fov_tac, absf(player.camera.fov - (80.0 + mv.fov_tac)) < 0.5, "fov=%.2f" % player.camera.fov)
	check("tac sprint raises the weapon", player.weapon_root.rotation.x > 0.6, "rot.x=%.2f" % player.weapon_root.rotation.x)
	# ADS ends tactical sprint.
	mouse(MOUSE_BUTTON_RIGHT, true)
	await wait(0.3)
	check("ADS ends tactical sprint", not player.tac_sprinting and not player.sprinting)
	mouse(MOUSE_BUTTON_RIGHT, false)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await wait(0.7)
	check("FOV restores on stop", absf(player.camera.fov - 80.0) < 0.4, "fov=%.2f" % player.camera.fov)
	await reset_player()
	# Double tap inside the window.
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await tick
	key(KEY_SHIFT, false)
	await wait(0.12)
	key(KEY_SHIFT, true)
	await wait(0.7)
	check("double-tap inside window -> tactical sprint", player.tac_sprinting)
	await reset_player()
	# Two taps outside the window -> regular sprint only.
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await tick
	key(KEY_SHIFT, false)
	await wait(mv.double_tap_window + 0.3)
	key(KEY_SHIFT, true)
	await wait(0.7)
	check("taps outside window -> regular sprint only", player.sprinting and not player.tac_sprinting)
	# Tactical sprint-to-fire delay (rifle 0.42 s vs 0.28 s regular).
	key(KEY_SHIFT, false)
	key(KEY_SHIFT, true)
	await wait(0.6)
	check("tac sprint re-engaged", player.tac_sprinting)
	var s0: int = player.stats.shots
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.32)
	check("no shot 0.32 s after trigger from tac sprint", player.stats.shots == s0 and not player.sprinting, "sprint_out=%.2f" % player.sprint_out_timer)
	await wait(0.25)
	check("fires after tac sprint-to-fire (%.2f s)" % player.def.tac_sprint_to_fire, player.stats.shots > s0, "shots=%d" % (player.stats.shots - s0))
	mouse(MOUSE_BUTTON_LEFT, false)
	await reset_player()
	# Slide.
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await wait(0.5)
	await press(KEY_C)
	await wait(0.04)
	check("crouch while sprinting starts a slide", player.sliding and player.crouching and not player.sprinting)
	check("slide launches faster than sprint", hspeed() > mv.sprint_speed + 0.5, "v=%.2f" % hspeed())
	check("slide keeps a FOV kick", player.camera.fov > 82.0, "fov=%.2f" % player.camera.fov)
	s0 = player.stats.shots
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.06)
	check("no fire in the first %.0f ms of a slide" % (mv.slide_fire_lock * 1000.0), player.stats.shots == s0, "shots=%d" % (player.stats.shots - s0))
	await wait(0.25)
	check("fires from slide after the lockout", player.stats.shots > s0, "shots=%d" % (player.stats.shots - s0))
	check("slide adds spread", player.current_spread() > player.def.hip_spread + mv.slide_spread, "spread=%.2f" % player.current_spread())
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.6)
	check("slide ends after %.1f s, stays crouched" % mv.slide_duration, not player.sliding and player.crouching and player.slide_cooldown_t > 0.0, "cd=%.2f" % player.slide_cooldown_t)
	check("slide decelerates on the friction curve", hspeed() < mv.slide_end_speed + 1.0, "v=%.2f" % hspeed())
	# Cooldown: uncrouch, sprint, crouch again too early -> plain crouch, no slide.
	await press(KEY_C)
	await wait(0.3)
	await press(KEY_C)
	await wait(0.05)
	check("slide on cooldown -> no slide", not player.sliding, "cd=%.2f" % player.slide_cooldown_t)
	await press(KEY_C)
	await wait(1.1)
	await press(KEY_C)
	await wait(0.04)
	check("slide available after cooldown", player.sliding)
	# Jump cancels the slide.
	key(KEY_SPACE, true)
	await wait(0.06)
	key(KEY_SPACE, false)
	check("jump cancels slide", not player.sliding and player.velocity.y > 1.0 and not player.crouching, "vy=%.2f" % player.velocity.y)
	await reset_player()
	# ADS during a slide: ADS FOV wins over the kick.
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await wait(0.5)
	await press(KEY_C)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await wait(0.4)
	check("ADS from slide overrides the FOV kick", player.ads_amount > 0.95 and absf(player.camera.fov - 57.6) < 0.5, "fov=%.2f ads=%.2f" % [player.camera.fov, player.ads_amount])
	mouse(MOUSE_BUTTON_RIGHT, false)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await wait(1.0)
	check("FOV back to base after slide + ADS", absf(player.camera.fov - 80.0) < 0.4, "fov=%.2f" % player.camera.fov)
	await reset_player()


## Step 2 (pass 2): layered audio variants, pooled FX, fire shake.
func _fx_tests() -> void:
	var fx: Node3D = main.get_tree().get_first_node_in_group("fx")
	check("fx manager present", fx != null)
	# Variant cycling: every variant heard before a repeat, never twice running.
	var seq: Array = []
	for i in range(8):
		seq.append(Sfx.pick("rifle_crack"))
	var first: Array = seq.slice(0, 4)
	first.sort()
	var no_repeat := true
	for i in range(1, seq.size()):
		if seq[i] == seq[i - 1]:
			no_repeat = false
	check("variant cycling covers all variants before repeating", first == [0, 1, 2, 3], str(seq))
	check("variant cycling never repeats consecutively", no_repeat, str(seq))
	# Shake: energy after a shot, decays to zero.
	await reset_player()
	await aim_at(Vector3(3.0, 1.5, -37.0))
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick
	await tick
	mouse(MOUSE_BUTTON_LEFT, false)
	await tick
	check("fire adds shake energy", player.shake_energy > 0.05, "e=%.3f" % player.shake_energy)
	await wait(1.0)
	check("shake decays to zero", player.shake_energy == 0.0 and player.shake_rot == Vector3.ZERO, "e=%.4f" % player.shake_energy)
	player.add_shake(0.25)
	check("target drop kick adds shake", player.shake_energy > 0.2)
	await wait(1.0)
	# Pools: 500 shots into the backstop allocate nothing and cap decals.
	var nodes0 := fx.get_child_count()
	var objs0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var tracers0: int = fx.tracer_count
	player.ammo["rifle"] = {"mag": 500, "reserve": 0}
	var rpm0: float = player.def.rpm
	player.def.rpm = 6000.0
	var shots0: int = player.stats.shots
	mouse(MOUSE_BUTTON_LEFT, true)
	while player.stats.shots - shots0 < 500:
		await tick
		player.recoil_target = Vector2.ZERO
		player.recoil_current = Vector2.ZERO
	mouse(MOUSE_BUTTON_LEFT, false)
	player.def.rpm = rpm0
	await wait(0.3)
	var nodes1 := fx.get_child_count()
	var objs1 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	check("500 shots fired", player.stats.shots - shots0 == 500, "shots=%d" % (player.stats.shots - shots0))
	check("fx pool node count unchanged over 500 shots", nodes1 == nodes0, "%d -> %d" % [nodes0, nodes1])
	check("scene node count stable over 500 shots", objs1 - objs0 <= 2, "%d -> %d" % [objs0, objs1])
	check("decal count capped at pool size", fx.visible_decals() == fx.DECAL_POOL and fx.decal_count >= 500, "visible=%d total=%d" % [fx.visible_decals(), fx.decal_count])
	check("tracer every 3rd shot", absf((fx.tracer_count - tracers0) - 500.0 / 3.0) <= 2.0, "tracers=%d" % (fx.tracer_count - tracers0))
	check("bursts pooled per surface", fx.burst_count >= 500 and fx.bursts["concrete"].size() == fx.BURSTS_PER_SURFACE)
	await wait(0.2)
	check("tracers hidden after their life", fx.tracers.filter(func(m): return m.visible).size() == 0)
	player.ammo["rifle"] = {"mag": 30, "reserve": 120}
	await reset_player()


func _track_has_key(a: Animation, path_part: String, time: float) -> bool:
	for i in range(a.get_track_count()):
		if str(a.track_get_path(i)).contains(path_part):
			if a.track_find_key(i, time, Animation.FIND_MODE_APPROX) >= 0:
				return true
	return false


## True when the view model is on screen: the receiver origin or the muzzle projects
## inside the viewport and nothing of the rig sits behind the camera.
func view_model_on_screen(label: String) -> void:
	var cam: Camera3D = player.camera
	var rect := Rect2(Vector2.ZERO, cam.get_viewport().get_visible_rect().size)
	var model: Node3D = player.models[player.def.id]
	var pts := [model.global_position, player.muzzle_flash.global_position]
	var inside := 0
	var behind := false
	for p in pts:
		if cam.is_position_behind(p):
			behind = true
		elif rect.has_point(cam.unproject_position(p)):
			inside += 1
	for arm in ["r", "l"]:
		if cam.is_position_behind(player.hands.arms[arm].hand.global_position):
			behind = true
	check("view model on screen: " + label, inside > 0 and not behind, "inside=%d behind=%s origin=%s" % [inside, behind, str(cam.unproject_position(pts[0]).round()) if not cam.is_position_behind(pts[0]) else "behind"])


## Step 3 (pass 2): authored first-person clips + IK hands.
func _anim_tests() -> void:
	await reset_player()
	check("arm rig built (2 arms x upper, fore, hand)", player.hands.get_child_count() == 6)
	for d in player.defs:
		var ap: AnimationPlayer = player.action_players[d.id]
		var lp: AnimationPlayer = player.loco_players[d.id]
		check("%s reload clip length == reload_time" % d.id, is_equal_approx(ap.get_animation("reload").length, d.reload_time), "%.3f" % ap.get_animation("reload").length)
		check("%s empty reload clip length == reload_time + empty_extra" % d.id, is_equal_approx(ap.get_animation("reload_empty").length, d.reload_time + d.empty_extra))
		check("%s reload clip keys the mag at mag_in_t" % d.id, _track_has_key(ap.get_animation("reload"), "Mag", d.mag_in_t))
		check("%s reload clip starts the mag drop at mag_out_t" % d.id, _track_has_key(ap.get_animation("reload"), "Mag", d.mag_out_t - 0.05))
		check("%s empty reload racks the bolt after reload_time" % d.id, _track_has_key(ap.get_animation("reload_empty"), "Bolt", d.reload_time + 0.22))
		check("%s lower clip length == lower_time" % d.id, is_equal_approx(ap.get_animation("lower").length, d.lower_time))
		check("%s raise clip length == raise_time" % d.id, is_equal_approx(ap.get_animation("raise").length, d.raise_time))
		check("%s ads clip length == ads_time" % d.id, is_equal_approx(ap.get_animation("ads_in").length, d.ads_time) and is_equal_approx(ap.get_animation("ads_out").length, d.ads_time))
		check("%s loco loops present" % d.id, lp.has_animation("idle") and lp.has_animation("walk") and lp.has_animation("sprint") and lp.has_animation("tac") and lp.has_animation("slide"))
	# Reload clip runs in lockstep with the gameplay timer.
	await aim_at(Vector3(3.0, 1.5, -37.0))
	mouse(MOUSE_BUTTON_LEFT, true)
	await tick
	await tick
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.1)
	var ap_r: AnimationPlayer = player.action_players["rifle"]
	check("fire plays the off-hand kick clip", ap_r.current_animation == "fire" or ap_r.assigned_animation == "fire", ap_r.current_animation)
	await wait(0.5)
	await press(KEY_R)
	await wait(0.6)
	check("reload clip playing during reload", ap_r.is_playing() and ap_r.current_animation == "reload", ap_r.current_animation)
	check("reload clip position tracks reload_t", absf(ap_r.current_animation_position - player.reload_t) < 0.04, "clip=%.3f t=%.3f" % [ap_r.current_animation_position, player.reload_t])
	await view_model_on_screen("rifle reload (mid)")
	var mag_node: Node3D = player.models["rifle"].get_node("Mag")
	check("magazine is out of the well mid-reload", mag_node.position.distance_to(player.def.mag_pos) > 0.1, "d=%.3f" % mag_node.position.distance_to(player.def.mag_pos))
	await wait(1.6)
	check("reload clip finished with the reload", not player.reloading and not ap_r.is_playing())
	check("magazine back in the well", mag_node.position.distance_to(player.def.mag_pos) < 0.002)
	# Empty reload racks the bolt.
	player.ammo["rifle"] = {"mag": 0, "reserve": 90}
	await press(KEY_R)
	await wait(0.2)
	check("empty reload plays the empty clip", ap_r.current_animation == "reload_empty")
	await wait(player.def.reload_time + 0.22 - 0.2)
	var bolt: Node3D = player.models["rifle"].get_node("Bolt")
	check("bolt pulled back during the empty-reload extra phase", bolt.position.distance_to(player.def.bolt_pos) > 0.04, "d=%.3f" % bolt.position.distance_to(player.def.bolt_pos))
	await wait(0.6)
	check("bolt returned, empty reload done", not player.reloading and bolt.position.distance_to(player.def.bolt_pos) < 0.002)
	# Swap: lower on the old weapon, raise on the new, matching the swap timers.
	await press(KEY_2)
	await wait(0.1)
	check("swap plays lower on the outgoing weapon", ap_r.current_animation == "lower" and ap_r.is_playing())
	await view_model_on_screen("rifle lowering (mid swap)")
	await wait(player.defs[0].lower_time)
	var ap_p: AnimationPlayer = player.action_players["pistol"]
	check("swap plays raise on the incoming weapon", player.def.id == "pistol" and ap_p.current_animation == "raise" and ap_p.is_playing(), ap_p.current_animation)
	await view_model_on_screen("pistol raising (mid swap)")
	await wait(player.def.raise_time + 0.05)
	check("raise finished with the swap", not player.swapping and not ap_p.is_playing())
	await view_model_on_screen("pistol hip")
	mouse(MOUSE_BUTTON_RIGHT, true)
	await wait(0.4)
	await view_model_on_screen("pistol ADS")
	mouse(MOUSE_BUTTON_RIGHT, false)
	await wait(0.3)
	await press(KEY_1)
	await wait(0.9)
	# Locomotion loops follow the movement state; view model stays on screen in each.
	await view_model_on_screen("rifle hip idle")
	check("idle loop", player.loco_players["rifle"].current_animation == "idle")
	key(KEY_W, true)
	await wait(0.4)
	check("walk loop", player.loco_players["rifle"].current_animation == "walk")
	await view_model_on_screen("rifle walk")
	key(KEY_SHIFT, true)
	await wait(0.5)
	check("sprint loop", player.loco_players["rifle"].current_animation == "sprint")
	await view_model_on_screen("rifle sprint")
	key(KEY_SHIFT, false)
	key(KEY_SHIFT, true)
	await wait(0.5)
	check("tac sprint loop", player.loco_players["rifle"].current_animation == "tac")
	await view_model_on_screen("rifle tactical sprint")
	await press(KEY_C)
	await wait(0.3)
	check("slide loop", player.loco_players["rifle"].current_animation == "slide")
	await view_model_on_screen("rifle slide")
	await wait(0.6)
	await reset_player()
	mouse(MOUSE_BUTTON_RIGHT, true)
	await wait(0.4)
	await view_model_on_screen("rifle ADS")
	mouse(MOUSE_BUTTON_RIGHT, false)
	await reset_player()
