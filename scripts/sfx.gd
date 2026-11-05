extends Node
## Autoload sound bank. Every clip is synthesised by tools/gen_sfx.py (no recordings).
## Uses one polyphonic stream so rapid fire never cuts voices off.

const NAMES := [
	"rifle_shot", "pistol_shot", "shot_tail", "hitmarker", "headshot", "kill",
	"mag_out", "mag_in", "bolt", "dry_fire", "swap", "target_fall", "target_up",
	"impact", "footstep", "start", "finish", "countdown",
]

var _streams: Dictionary = {}
var _player: AudioStreamPlayer
var _muted := false


func _ready() -> void:
	for n in NAMES:
		_streams[n] = load("res://assets/sfx/%s.wav" % n)
	_player = AudioStreamPlayer.new()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 32
	_player.stream = poly
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_player.play()


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


## Positional-ish helper: attenuate by distance from the listener (camera).
func play_at(n: String, world_pos: Vector3, base_db := 0.0, pitch := 1.0, pitch_var := 0.0) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := 1.0
	if cam:
		d = maxf(1.0, cam.global_position.distance_to(world_pos))
	var att := -20.0 * log(d) / log(10.0) * 0.8
	play(n, base_db + att, pitch, pitch_var)
