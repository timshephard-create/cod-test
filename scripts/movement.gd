extends RefCounted
## Movement tuning table. One place for every speed, timer and FOV kick.
## Speeds are m/s, times are seconds, FOV kicks are degrees added to the base FOV
## (and fully overridden by the ADS FOV as ads blends in).


static func table() -> Dictionary:
	return {
		"walk_speed": 5.0,
		"sprint_speed": 7.4,
		"tac_sprint_speed": 8.6,
		"crouch_mult": 0.5,
		"jump_vel": 4.4,
		"gravity": 17.0,
		"accel_ground": 60.0,
		"accel_air": 12.0,
		# Tactical sprint: double-tap Shift within this window, or tap Shift again while sprinting.
		"double_tap_window": 0.28,
		"tac_duration": 6.0,
		"tac_rearm": 1.5,  # after tac runs out, wait this long before it can start again
		# Slide: Crouch while sprinting.
		"slide_speed": 9.2,
		"slide_end_speed": 2.4,
		"slide_duration": 0.8,
		"slide_cooldown": 1.0,
		"slide_fire_lock": 0.15,
		"slide_spread": 1.6,
		"slide_cam_dip": 0.14,
		"slide_cam_roll": 0.065,
		"slide_min_sprint": 0.15,  # must have been sprinting at least this long
		# FOV kicks (degrees), damped toward target at fov_damp (1/s).
		"fov_sprint": 4.0,
		"fov_tac": 8.0,
		"fov_slide": 3.0,
		"fov_damp": 9.0,
	}
