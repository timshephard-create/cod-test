extends CanvasLayer
## Crosshair, hitmarker, ammo, timer/score, prompts and results. Built in code.

var player: Node
var draw_ctl: Control
var ammo_lbl: Label
var weapon_lbl: Label
var timer_lbl: Label
var score_lbl: Label
var prompt_lbl: Label
var pop_lbl: Label
var overlay: Control
var overlay_lbl: Label
var results: PanelContainer
var results_lbl: Label
var state_lbl: Label

var hit_timer := 0.0
var hit_kind := 0  # 0 body, 1 head, 2 kill
var pop_timer := 0.0
var pop_tw: Tween
var pop_base := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	draw_ctl = Control.new()
	draw_ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draw_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_ctl.draw.connect(_on_draw)
	add_child(draw_ctl)

	ammo_lbl = _label(36, Color.WHITE)
	ammo_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_lbl.offset_left = -320
	ammo_lbl.offset_top = -96
	ammo_lbl.offset_right = -28
	ammo_lbl.offset_bottom = -46
	ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_lbl = _label(16, Color(0.85, 0.85, 0.85))
	weapon_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_lbl.offset_left = -320
	weapon_lbl.offset_top = -46
	weapon_lbl.offset_right = -28
	weapon_lbl.offset_bottom = -22
	weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	timer_lbl = _label(30, Color.WHITE)
	timer_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer_lbl.offset_left = -150
	timer_lbl.offset_right = 150
	timer_lbl.offset_top = 16
	timer_lbl.offset_bottom = 56
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl = _label(22, Color(1.0, 0.85, 0.4))
	score_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	score_lbl.offset_left = -360
	score_lbl.offset_right = -28
	score_lbl.offset_top = 18
	score_lbl.offset_bottom = 50
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_lbl = _label(16, Color(0.8, 0.8, 0.8))
	state_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	state_lbl.offset_left = 28
	state_lbl.offset_top = -46
	state_lbl.offset_right = 800
	state_lbl.offset_bottom = -22
	state_lbl.text = "WASD move   Shift sprint   RMB aim   LMB fire   R reload   1/2/Q weapons   C crouch"

	prompt_lbl = _label(22, Color(0.95, 0.95, 0.95))
	prompt_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_lbl.offset_left = -400
	prompt_lbl.offset_right = 400
	prompt_lbl.offset_top = -140
	prompt_lbl.offset_bottom = -100
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	pop_lbl = _label(26, Color(1.0, 0.4, 0.2))
	pop_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pop_lbl.offset_left = -200
	pop_lbl.offset_right = 200
	pop_lbl.offset_top = -90
	pop_lbl.offset_bottom = -50
	pop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop_lbl.modulate.a = 0.0
	pop_base = pop_lbl.position

	results = PanelContainer.new()
	results.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	results.offset_left = -260
	results.offset_right = 260
	results.offset_top = -170
	results.offset_bottom = 170
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.88)
	sb.border_color = Color(1.0, 0.85, 0.4)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	results.add_theme_stylebox_override("panel", sb)
	results_lbl = _label(22, Color.WHITE, results)
	results_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results.visible = false
	add_child(results)

	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay_lbl = _label(28, Color.WHITE, overlay)
	overlay_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay_lbl.offset_left = -400
	overlay_lbl.offset_right = 400
	overlay_lbl.offset_top = -80
	overlay_lbl.offset_bottom = 80
	overlay_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_lbl.text = "RANGE DAY\n\nClick to play"


func _label(size: int, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else self).add_child(l)
	return l


func bind(p: Node) -> void:
	player = p
	p.hit_landed.connect(_on_hit)
	p.ammo_changed.connect(_refresh_ammo)
	p.weapon_changed.connect(func(_d): _refresh_ammo())
	_refresh_ammo()


func _refresh_ammo() -> void:
	if player == null:
		return
	ammo_lbl.text = player.ammo_text()
	weapon_lbl.text = player.def.name
	var mag: int = player.ammo[player.def.id].mag
	ammo_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if mag <= 5 else Color.WHITE)


func _on_hit(part: String, killed: bool, points: int, _pos: Vector3) -> void:
	hit_timer = 0.28
	hit_kind = 2 if killed else (1 if part == "head" else 0)
	if killed:
		Sfx.play("kill", -4.0, 1.0, 0.03)
	if part == "head":
		Sfx.play("headshot", -5.0, 1.0, 0.03)
		_pop("HEADSHOT  +%d" % points, Color(1.0, 0.45, 0.2))
	else:
		Sfx.play("hitmarker", -6.0, 1.0, 0.03)
		if killed:
			_pop("+%d" % points, Color(1.0, 0.85, 0.4))
	draw_ctl.queue_redraw()


func _pop(text: String, color: Color) -> void:
	pop_lbl.text = text
	pop_lbl.add_theme_color_override("font_color", color)
	if pop_tw:
		pop_tw.kill()
	pop_lbl.modulate.a = 1.0
	pop_lbl.scale = Vector2(1.25, 1.25)
	pop_lbl.pivot_offset = pop_lbl.size * 0.5
	pop_tw = create_tween().set_parallel(true)
	pop_tw.tween_property(pop_lbl, "scale", Vector2.ONE, 0.12)
	pop_tw.tween_property(pop_lbl, "modulate:a", 0.0, 0.5).set_delay(0.35)


func set_prompt(text: String) -> void:
	prompt_lbl.text = text


func set_timer(text: String, color := Color.WHITE) -> void:
	timer_lbl.text = text
	timer_lbl.add_theme_color_override("font_color", color)


func set_score(text: String) -> void:
	score_lbl.text = text


func set_overlay(visible_: bool, text := "") -> void:
	overlay.visible = visible_
	if text != "":
		overlay_lbl.text = text


func show_results(text: String) -> void:
	results_lbl.text = text
	results.visible = true


func hide_results() -> void:
	results.visible = false


func _process(delta: float) -> void:
	if hit_timer > 0.0:
		hit_timer -= delta
	draw_ctl.queue_redraw()


func _on_draw() -> void:
	if player == null:
		return
	var c := draw_ctl.size * 0.5
	var vp_h := draw_ctl.size.y
	var fov: float = player.camera.fov
	var px_per_rad := (vp_h * 0.5) / tan(deg_to_rad(fov) * 0.5)
	var spread: float = player.current_spread()
	var gap := tan(deg_to_rad(spread)) * px_per_rad + 6.0
	var ads: float = player.ads_amount
	var alpha := clampf(1.0 - ads * 1.6, 0.0, 1.0)
	if player.sprinting:
		alpha *= 0.35
	if alpha > 0.0:
		var col := Color(1, 1, 1, alpha)
		var shadow := Color(0, 0, 0, alpha * 0.8)
		var len := 9.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var a: Vector2 = c + d * gap
			var b: Vector2 = c + d * (gap + len)
			draw_ctl.draw_line(a, b, shadow, 4.0)
			draw_ctl.draw_line(a, b, col, 2.0)
		draw_ctl.draw_circle(c, 1.5, col)
	if hit_timer > 0.0:
		var k := hit_timer / 0.28
		var col2 := Color(1, 1, 1, k)
		var w := 2.0
		if hit_kind == 1:
			col2 = Color(1.0, 0.45, 0.2, k)
			w = 3.0
		elif hit_kind == 2:
			col2 = Color(1.0, 0.2, 0.15, k)
			w = 3.5
		var inner := 5.0 + (1.0 - k) * 4.0
		var outer := inner + 9.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn: Vector2 = d.normalized()
			draw_ctl.draw_line(c + dn * inner, c + dn * outer, Color(0, 0, 0, k * 0.7), w + 2.0)
			draw_ctl.draw_line(c + dn * inner, c + dn * outer, col2, w)
