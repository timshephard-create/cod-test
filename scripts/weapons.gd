extends RefCounted
## Weapon definitions and procedural view-model builders.
## Angles are degrees, times are seconds, positions are metres in camera space
## (x right, y up, -z forward).

const GUNMETAL := Color(0.16, 0.17, 0.19)
const POLYMER := Color(0.08, 0.08, 0.09)
const TAN := Color(0.45, 0.38, 0.27)
const STEEL := Color(0.55, 0.56, 0.58)
const BRASS := Color(0.75, 0.6, 0.25)


static func rifle() -> Dictionary:
	# Front sight tip sits at y = 0.075 on the model; the view model is drawn at 0.78 scale,
	# so ADS drops the gun by sight_h * scale to put the post on the camera axis.
	var scale := 0.78
	var sight_h := 0.075 * scale
	return {
		"id": "rifle",
		"model_scale": scale,
		"name": "KR-7 CARBINE",
		"auto": true,
		"rpm": 760.0,
		"mag": 30,
		"reserve": 120,
		"damage": 28.0,
		"head_mult": 1.5,
		"ads_time": 0.24,
		"ads_fov": 0.72,
		"ads_move_mult": 0.55,
		"hip_spread": 2.4,
		"ads_spread": 0.12,
		"move_spread": 1.4,
		"bloom_per_shot": 0.32,
		"bloom_max": 2.2,
		"bloom_decay": 7.0,
		# Pitch (up) / yaw (right) per shot. Climbs hard, drifts right, then wanders.
		"pattern": [
			Vector2(1.05, 0.05), Vector2(1.15, -0.10), Vector2(1.10, 0.20), Vector2(0.95, 0.35),
			Vector2(0.90, 0.40), Vector2(0.80, -0.25), Vector2(0.75, -0.45), Vector2(0.70, -0.30),
			Vector2(0.65, 0.25), Vector2(0.65, 0.50), Vector2(0.60, 0.55), Vector2(0.55, 0.20),
			Vector2(0.55, -0.35), Vector2(0.50, -0.50), Vector2(0.50, -0.20), Vector2(0.50, 0.30),
		],
		"pattern_reset": 0.30,
		"recoil_ads_mult": 0.82,
		"recoil_kick_speed": 32.0,
		"recoil_recover": 5.5,
		"recoil_recover_delay": 0.09,
		"recoil_random": 0.12,
		"kick_back": 0.030,
		"kick_up": 0.045,
		"kick_roll": 0.02,
		"reload_time": 2.05,
		"mag_out_t": 0.45,
		"mag_in_t": 1.35,
		"empty_extra": 0.45,
		"sprint_to_fire": 0.28,
		"tac_sprint_to_fire": 0.42,
		"raise_time": 0.45,
		"lower_time": 0.25,
		"hip_pos": Vector3(0.19, -0.19, -0.42),
		"ads_pos": Vector3(0.0, -sight_h, -0.24),
		"sprint_pos": Vector3(0.12, -0.25, -0.38),
		"sprint_rot": Vector3(-0.30, 0.65, 0.30),
		"tac_pos": Vector3(0.10, -0.14, -0.30),
		"tac_rot": Vector3(0.95, 0.40, -0.30),
		"slide_pos": Vector3(0.16, -0.26, -0.40),
		"slide_rot": Vector3(-0.15, 0.35, 0.55),
		"shot_sfx": "rifle_shot",
		"shot_db": -2.0,
		"muzzle": Vector3(0.0, 0.02, -0.66),
	}


static func pistol() -> Dictionary:
	var scale := 0.85
	var sight_h := 0.052 * scale
	return {
		"id": "pistol",
		"model_scale": scale,
		"name": "P9 SIDEARM",
		"auto": false,
		"rpm": 430.0,
		"mag": 15,
		"reserve": 60,
		"damage": 36.0,
		"head_mult": 1.6,
		"ads_time": 0.17,
		"ads_fov": 0.86,
		"ads_move_mult": 0.70,
		"hip_spread": 1.8,
		"ads_spread": 0.10,
		"move_spread": 1.0,
		"bloom_per_shot": 0.5,
		"bloom_max": 2.0,
		"bloom_decay": 9.0,
		"pattern": [
			Vector2(2.1, 0.15), Vector2(2.0, -0.25), Vector2(1.9, 0.30), Vector2(1.8, -0.20),
			Vector2(1.8, 0.35), Vector2(1.7, -0.35),
		],
		"pattern_reset": 0.22,
		"recoil_ads_mult": 0.9,
		"recoil_kick_speed": 45.0,
		"recoil_recover": 11.0,
		"recoil_recover_delay": 0.04,
		"recoil_random": 0.2,
		"kick_back": 0.045,
		"kick_up": 0.16,
		"kick_roll": 0.0,
		"reload_time": 1.55,
		"mag_out_t": 0.35,
		"mag_in_t": 0.95,
		"empty_extra": 0.30,
		"sprint_to_fire": 0.16,
		"tac_sprint_to_fire": 0.26,
		"raise_time": 0.30,
		"lower_time": 0.18,
		"hip_pos": Vector3(0.16, -0.16, -0.36),
		"ads_pos": Vector3(0.0, -sight_h, -0.28),
		"sprint_pos": Vector3(0.12, -0.24, -0.34),
		"sprint_rot": Vector3(-0.25, 0.50, 0.25),
		"tac_pos": Vector3(0.09, -0.12, -0.26),
		"tac_rot": Vector3(0.85, 0.30, -0.25),
		"slide_pos": Vector3(0.14, -0.23, -0.34),
		"slide_rot": Vector3(-0.10, 0.30, 0.45),
		"shot_sfx": "pistol_shot",
		"shot_db": -4.0,
		"muzzle": Vector3(0.0, 0.03, -0.26),
	}


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mat.metallic = 0.3
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func build_model(def: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + def.id
	if def.id == "rifle":
		_box(root, Vector3(0.07, 0.085, 0.34), Vector3(0, 0, 0.0), GUNMETAL)  # receiver
		_box(root, Vector3(0.06, 0.065, 0.30), Vector3(0, 0.0, -0.31), TAN)  # handguard
		_box(root, Vector3(0.024, 0.024, 0.30), Vector3(0, 0.02, -0.52), STEEL)  # barrel
		_box(root, Vector3(0.03, 0.03, 0.06), Vector3(0, 0.02, -0.66), GUNMETAL)  # muzzle device
		_box(root, Vector3(0.035, 0.19, 0.075), Vector3(0, -0.12, -0.02), POLYMER, Vector3(0.12, 0, 0))  # magazine
		_box(root, Vector3(0.04, 0.11, 0.045), Vector3(0, -0.09, 0.12), POLYMER, Vector3(-0.35, 0, 0))  # grip
		_box(root, Vector3(0.045, 0.06, 0.26), Vector3(0, -0.01, 0.30), POLYMER)  # stock
		_box(root, Vector3(0.05, 0.12, 0.04), Vector3(0, -0.02, 0.42), POLYMER)  # butt pad
		_box(root, Vector3(0.05, 0.015, 0.34), Vector3(0, 0.05, 0.0), GUNMETAL)  # top rail
		_box(root, Vector3(0.02, 0.02, 0.02), Vector3(0.045, 0.0, 0.05), STEEL)  # charging handle
		# Rear aperture: four thin bars forming a square hole centred at y=0.075.
		var ry := 0.075
		var rz := 0.05
		_box(root, Vector3(0.034, 0.005, 0.008), Vector3(0, ry + 0.0145, rz), GUNMETAL)
		_box(root, Vector3(0.034, 0.005, 0.008), Vector3(0, ry - 0.0145, rz), GUNMETAL)
		_box(root, Vector3(0.005, 0.034, 0.008), Vector3(0.0145, ry, rz), GUNMETAL)
		_box(root, Vector3(0.005, 0.034, 0.008), Vector3(-0.0145, ry, rz), GUNMETAL)
		_box(root, Vector3(0.034, 0.008, 0.008), Vector3(0, ry - 0.02, rz), GUNMETAL)  # base
		# Front post with guard ears.
		var fz := -0.60
		_box(root, Vector3(0.005, 0.022, 0.005), Vector3(0, 0.0665, fz), BRASS)  # tip at y=0.0775
		_box(root, Vector3(0.005, 0.035, 0.008), Vector3(0.014, 0.062, fz), GUNMETAL)
		_box(root, Vector3(0.005, 0.035, 0.008), Vector3(-0.014, 0.062, fz), GUNMETAL)
		_box(root, Vector3(0.034, 0.012, 0.01), Vector3(0, 0.047, fz), GUNMETAL)
	else:
		_box(root, Vector3(0.034, 0.045, 0.19), Vector3(0, 0.01, -0.08), GUNMETAL)  # slide
		_box(root, Vector3(0.03, 0.035, 0.16), Vector3(0, -0.02, -0.05), POLYMER)  # frame
		_box(root, Vector3(0.034, 0.075, 0.04), Vector3(0, -0.07, 0.03), POLYMER, Vector3(-0.3, 0, 0))  # grip
		_box(root, Vector3(0.016, 0.016, 0.03), Vector3(0, 0.012, -0.185), STEEL)  # muzzle
		_box(root, Vector3(0.012, 0.025, 0.02), Vector3(0, -0.035, -0.06), GUNMETAL)  # trigger guard bar
		var ry := 0.052
		_box(root, Vector3(0.006, 0.014, 0.006), Vector3(0.009, ry - 0.006, 0.0), GUNMETAL)  # rear notch sides
		_box(root, Vector3(0.006, 0.014, 0.006), Vector3(-0.009, ry - 0.006, 0.0), GUNMETAL)
		_box(root, Vector3(0.004, 0.014, 0.004), Vector3(0, ry - 0.0065, -0.17), BRASS)  # front post tip at ~0.0525
	return root
