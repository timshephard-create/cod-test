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

	print("AUTOTEST %d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails > 0 else 0)
