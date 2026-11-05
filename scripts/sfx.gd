extends Node
## Autoload sound bank. Every clip is synthesised by tools/gen_sfx.py (no recordings).
## One polyphonic stream so rapid fire never cuts voices off. Multi-variant sets are
## cycled (never the same variant twice in a row) so bursts don't sound stamped.

const NAMES := [
	"hitmarker", "headshot", "kill",
	"mag_out", "mag_in", "bolt", "dry_fire", "swap", "target_fall", "target_up",
	"footstep", "start", "finish", "countdown",
]
## base name -> number of variants (files are <base>_<i>.wav).
const VARIANTS := {
	"rifle_crack": 4, "rifle_body": 4, "rifle_tail": 3,
	"pistol_crack": 4, "pistol_body": 4, "pistol_tail": 3,
	"impact_concrete": 3, "impact_metal": 3, "impact_wood": 3,
	"shell": 3,
}

var _streams: Dictionary = {}
var _player: AudioStreamPlayer
var _muted := false
var _cursor: Dictionary = {}
var _last: Dictionary = {}


func _ready() -> void:
	for n in NAMES:
		_streams[n] = load("res://assets/sfx/%s.wav" % n)
	for base in VARIANTS:
		for i in range(VARIANTS[base]):
			var n := "%s_%d" % [base, i]
			_streams[n] = load("res://assets/sfx/%s.wav" % n)
		_cursor[base] = randi() % VARIANTS[base]
		_last[base] = -1
	_player = AudioStreamPlayer.new()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 48
	_player.stream = poly
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_player.play()


## Next variant index for a set: cycles through all variants from a random start
## so every variant is heard before any repeats, and never the same one twice running.
func pick(base: String) -> int:
	var n: int = VARIANTS[base]
	var i: int = _cursor[base]
	if n > 1 and i == _last[base]:
		i = (i + 1) % n
	_cursor[base] = (i + 1) % n
	_last[base] = i
	return i


func play(n: String, volume_db := 0.0, pitch := 1.0, pitch_var := 0.0) -> void:
	if _muted or not _streams.has(n):
		return
	if not _player.playing:
		_player.play()
	var pb := _player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb == null:
		return
	var p := pitch + randf_range(-pitch_var, pitch_var)
	pb.play_stream(_streams[n], 0.0, volume_db, p)


func play_variant(base: String, volume_db := 0.0, pitch := 1.0, pitch_var := 0.0) -> void:
	play("%s_%d" % [base, pick(base)], volume_db, pitch, pitch_var)


## Layered gunshot: crack + body + tail, each from its own variant set.
func shot(weapon_id: String, base_db := 0.0) -> void:
	play_variant(weapon_id + "_crack", base_db - 1.0, 1.0, 0.04)
	play_variant(weapon_id + "_body", base_db, 1.0, 0.05)
	play_variant(weapon_id + "_tail", base_db - 9.0, 1.0, 0.08)


func _distance_db(world_pos: Vector3) -> float:
	var cam := get_viewport().get_camera_3d()
	var d := 1.0
	if cam:
		d = maxf(1.0, cam.global_position.distance_to(world_pos))
	return -20.0 * log(d) / log(10.0) * 0.8


## Positional-ish helper: attenuate by distance from the listener (camera).
func play_at(n: String, world_pos: Vector3, base_db := 0.0, pitch := 1.0, pitch_var := 0.0) -> void:
	play(n, base_db + _distance_db(world_pos), pitch, pitch_var)


func impact(surface: String, world_pos: Vector3, base_db := -4.0) -> void:
	var base := "impact_" + surface
	if not VARIANTS.has(base):
		base = "impact_concrete"
	play_variant(base, base_db + _distance_db(world_pos), 1.0, 0.1)
