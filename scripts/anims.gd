extends RefCounted
## Builds every first-person clip in code. Clip lengths and key times are taken straight
## from the weapon tables, so the animation can never drift from the gameplay timers.
##
## Two players per weapon, on two nested pose nodes, so the layers add:
##   Kick (spring) -> Loco_<id> [loco player] -> AnimPose_<id> [action player] -> Model_<id>
## Loco clips animate Loco_<id> and the Grip*Base nodes; action clips animate AnimPose_<id>,
## Mag, Bolt and the inner GripR / GripL nodes.

const LOWER_POS := Vector3(0.0, -0.16, 0.02)
const LOWER_ROT := Vector3(-0.55, 0.0, 0.0)


static func _pos(a: Animation, path: String, keys: Array, cubic := true) -> int:
	var tr := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(tr, NodePath(path))
	if cubic:
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
	for k in keys:
		a.position_track_insert_key(tr, k[0], k[1])
	return tr


static func _rot(a: Animation, path: String, keys: Array, cubic := true) -> int:
	var tr := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(tr, NodePath(path))
	if cubic:
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
	for k in keys:
		a.rotation_track_insert_key(tr, k[0], Quaternion.from_euler(k[1]))
	return tr


static func _anim(length: float, loop := false) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a


## Rest-pose tracks for everything an action clip might have moved, so any clip that
## starts (lower, raise) snaps the rig back to a clean state first.
static func _rest(a: Animation, d: Dictionary, m: String, L: float) -> void:
	_pos(a, m + "/Mag", [[0.0, d.mag_pos], [L, d.mag_pos]], false)
	_rot(a, m + "/Mag", [[0.0, d.mag_rot], [L, d.mag_rot]], false)
	_pos(a, m + "/Bolt", [[0.0, d.bolt_pos], [L, d.bolt_pos]], false)
	_pos(a, m + "/GripLBase/GripL", [[0.0, d.grip_l_pos], [L, d.grip_l_pos]], false)
	_pos(a, m + "/GripRBase/GripR", [[0.0, d.grip_r_pos], [L, d.grip_r_pos]], false)


static func _reload(d: Dictionary, m: String, empty: bool) -> Animation:
	var L: float = d.reload_time + (d.empty_extra if empty else 0.0)
	var R: float = d.reload_time
	var a := _anim(L)
	var out_t: float = d.mag_out_t
	var in_t: float = d.mag_in_t
	var mag: Vector3 = d.mag_pos
	var drop: Vector3 = d.mag_drop
	var hand_on_mag: Vector3 = mag + Vector3(-0.02, -0.06, 0.0)
	# Gun tilts toward the chest and rolls so the mag well faces the off hand.
	_pos(a, ".", [[0.0, Vector3.ZERO], [0.25 * R, Vector3(0.02, -0.05, 0.02)], [0.65 * R, Vector3(0.01, -0.04, 0.03)], [R, Vector3.ZERO], [L, Vector3.ZERO]])
	_rot(a, ".", [[0.0, Vector3.ZERO], [0.25 * R, Vector3(-0.25, 0.10, 0.38)], [0.65 * R, Vector3(-0.15, 0.05, 0.28)], [R, Vector3.ZERO], [L, Vector3.ZERO]])
	# Magazine: out at mag_out_t, back in at mag_in_t (ammo refills on that key in gameplay).
	_pos(a, m + "/Mag", [[0.0, mag], [out_t - 0.05, mag], [out_t + 0.12, mag + drop], [in_t - 0.18, mag + drop * 0.85], [in_t, mag], [L, mag]], false)
	_rot(a, m + "/Mag", [[0.0, d.mag_rot], [out_t, d.mag_rot], [out_t + 0.12, d.mag_rot + Vector3(0.3, 0, 0.25)], [in_t - 0.18, d.mag_rot + Vector3(0.2, 0, 0.1)], [in_t, d.mag_rot], [L, d.mag_rot]], false)
	# Off hand: grabs the mag, rides it out and back, returns to the foregrip.
	var gl: Vector3 = d.grip_l_pos
	var lkeys := [[0.0, gl], [out_t - 0.12, hand_on_mag], [out_t + 0.12, hand_on_mag + drop], [in_t - 0.18, hand_on_mag + drop * 0.85], [in_t, hand_on_mag], [in_t + 0.2, gl]]
	if empty:
		# Then racks the bolt / slide.
		var bolt: Vector3 = d.bolt_pos
		var pull: Vector3 = d.bolt_pull
		lkeys.append([R + 0.05, bolt + Vector3(0.02, -0.03, 0.0)])
		lkeys.append([R + 0.22, bolt + pull + Vector3(0.02, -0.03, 0.0)])
		lkeys.append([R + 0.36, gl])
		_pos(a, m + "/Bolt", [[0.0, bolt], [R + 0.08, bolt], [R + 0.22, bolt + pull], [R + 0.30, bolt], [L, bolt]], false)
	lkeys.append([L, gl])
	_pos(a, m + "/GripLBase/GripL", lkeys)
	_pos(a, m + "/GripRBase/GripR", [[0.0, d.grip_r_pos], [L, d.grip_r_pos]], false)
	return a


static func action_library(d: Dictionary) -> AnimationLibrary:
	var m: String = "Model_" + d.id
	var lib := AnimationLibrary.new()
	lib.add_animation("reload", _reload(d, m, false))
	lib.add_animation("reload_empty", _reload(d, m, true))

	var lower := _anim(d.lower_time)
	_pos(lower, ".", [[0.0, Vector3.ZERO], [d.lower_time, LOWER_POS]])
	_rot(lower, ".", [[0.0, Vector3.ZERO], [d.lower_time, LOWER_ROT]])
	_rest(lower, d, m, d.lower_time)
	lib.add_animation("lower", lower)

	var raise := _anim(d.raise_time)
	_pos(raise, ".", [[0.0, LOWER_POS], [0.8 * d.raise_time, Vector3(0.0, 0.012, 0.0)], [d.raise_time, Vector3.ZERO]])
	_rot(raise, ".", [[0.0, LOWER_ROT], [0.8 * d.raise_time, Vector3(0.06, 0, 0)], [d.raise_time, Vector3.ZERO]])
	_rest(raise, d, m, d.raise_time)
	lib.add_animation("raise", raise)

	var fire := _anim(0.12)
	var gl: Vector3 = d.grip_l_pos
	_pos(fire, m + "/GripLBase/GripL", [[0.0, gl], [0.03, gl + Vector3(0.0, 0.006, 0.016)], [0.12, gl]])
	_pos(fire, m + "/GripRBase/GripR", [[0.0, d.grip_r_pos], [0.03, d.grip_r_pos + Vector3(0.0, 0.002, 0.006)], [0.12, d.grip_r_pos]])
	lib.add_animation("fire", fire)

	var ads_in := _anim(d.ads_time)
	_pos(ads_in, m + "/GripRBase/GripR", [[0.0, d.grip_r_pos], [d.ads_time, d.grip_r_pos + Vector3(0.0, 0.004, -0.004)]])
	_pos(ads_in, m + "/GripLBase/GripL", [[0.0, gl], [0.6 * d.ads_time, gl + Vector3(0.0, 0.008, -0.03)], [d.ads_time, gl + Vector3(0.0, 0.005, -0.02)]])
	lib.add_animation("ads_in", ads_in)
	var ads_out := _anim(d.ads_time)
	_pos(ads_out, m + "/GripRBase/GripR", [[0.0, d.grip_r_pos + Vector3(0.0, 0.004, -0.004)], [d.ads_time, d.grip_r_pos]])
	_pos(ads_out, m + "/GripLBase/GripL", [[0.0, gl + Vector3(0.0, 0.005, -0.02)], [d.ads_time, gl]])
	lib.add_animation("ads_out", ads_out)
	return lib


static func _loop(len: float, pose_amp: Vector3, roll: float, hand_l: Vector3, hand_r: Vector3, ap: String) -> Animation:
	var a := _anim(len, true)
	var q := len * 0.25
	_pos(a, ".", [[0.0, Vector3.ZERO], [q, Vector3(pose_amp.x, -pose_amp.y, pose_amp.z)], [2 * q, Vector3.ZERO], [3 * q, Vector3(-pose_amp.x, -pose_amp.y, pose_amp.z)], [len, Vector3.ZERO]])
	_rot(a, ".", [[0.0, Vector3.ZERO], [q, Vector3(0, 0, roll)], [2 * q, Vector3.ZERO], [3 * q, Vector3(0, 0, -roll)], [len, Vector3.ZERO]])
	# Hands lag the gun a little: offsets peak a quarter cycle after the pose.
	_pos(a, ap + "/GripLBase", [[0.0, Vector3(0, 0, hand_l.z)], [q, Vector3(hand_l.x, -hand_l.y, 0)], [2 * q, Vector3(0, 0, hand_l.z)], [3 * q, Vector3(-hand_l.x, -hand_l.y, 0)], [len, Vector3(0, 0, hand_l.z)]])
	_pos(a, ap + "/GripRBase", [[0.0, Vector3.ZERO], [q, Vector3(hand_r.x, -hand_r.y, 0)], [2 * q, Vector3.ZERO], [3 * q, Vector3(-hand_r.x, -hand_r.y, 0)], [len, Vector3.ZERO]])
	return a


static func loco_library(d: Dictionary) -> AnimationLibrary:
	var ap: String = "AnimPose_%s/Model_%s" % [d.id, d.id]
	var lib := AnimationLibrary.new()
	# Idle breathing: 4 s loop, tiny.
	var idle := _loop(4.0, Vector3(0.0015, 0.002, 0.0), 0.004, Vector3(0.002, 0.002, 0.002), Vector3(0.001, 0.001, 0.0), ap)
	lib.add_animation("idle", idle)
	lib.add_animation("walk", _loop(1.0 / 1.9, Vector3(0.003, 0.003, 0.0), 0.012, Vector3(0.006, 0.005, 0.006), Vector3(0.002, 0.002, 0.0), ap))
	lib.add_animation("sprint", _loop(1.0 / 2.8, Vector3(0.006, 0.006, 0.004), 0.03, Vector3(0.012, 0.01, 0.012), Vector3(0.004, 0.004, 0.0), ap))
	lib.add_animation("tac", _loop(1.0 / 3.3, Vector3(0.008, 0.009, 0.006), 0.045, Vector3(0.016, 0.014, 0.016), Vector3(0.006, 0.006, 0.0), ap))
	var slide := _anim(0.8, true)
	_pos(slide, ".", [[0.0, Vector3(-0.01, -0.02, 0.0)], [0.4, Vector3(-0.012, -0.025, 0.0)], [0.8, Vector3(-0.01, -0.02, 0.0)]])
	_rot(slide, ".", [[0.0, Vector3(-0.05, 0.0, 0.08)], [0.4, Vector3(-0.06, 0.0, 0.1)], [0.8, Vector3(-0.05, 0.0, 0.08)]])
	_pos(slide, ap + "/GripLBase", [[0.0, Vector3(-0.02, -0.02, 0.0)], [0.8, Vector3(-0.02, -0.02, 0.0)]])
	_pos(slide, ap + "/GripRBase", [[0.0, Vector3.ZERO], [0.8, Vector3.ZERO]])
	lib.add_animation("slide", slide)
	return lib
