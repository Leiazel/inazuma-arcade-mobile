class_name ArcadeAudioManager
extends Node

## Procedural retro-arcade sound synthesizer and BGM controller.
## Generates lightweight 16-bit PCM AudioStreamWAV buffers in memory with zero external file dependencies.

const MIX_RATE: int = 22050
const SFX_POOL_SIZE: int = 6

var sfx_enabled: bool = true
var music_enabled: bool = true
var sfx_volume: float = 0.80
var music_volume: float = 0.35

static var _shared_pcm_cache: Dictionary = {}

var _streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _bgm_player: AudioStreamPlayer = null
var _is_dummy_driver: bool = false

static func clear_shared_cache() -> void:
	_shared_pcm_cache.clear()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_is_dummy_driver = (DisplayServer.get_name() == "headless")
	_build_players()
	_synthesize_library()

func _exit_tree() -> void:
	_stop_and_release_players()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_stop_and_release_players()
		_streams.clear()

func _stop_and_release_players() -> void:
	if is_instance_valid(_bgm_player):
		if _bgm_player.playing:
			_bgm_player.stop()
		_bgm_player.stream = null
	for p in _sfx_players:
		if is_instance_valid(p):
			if p.playing:
				p.stop()
			p.stream = null

func _build_players() -> void:
	if not _sfx_players.is_empty():
		return
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		add_child(p)
		_sfx_players.append(p)

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	add_child(_bgm_player)
	_apply_volumes()

func _apply_volumes() -> void:
	var sfx_db: float = linear_to_db(maxf(0.0001, sfx_volume)) if sfx_enabled and sfx_volume > 0.001 else -80.0
	for p in _sfx_players:
		if is_instance_valid(p):
			p.volume_db = sfx_db

	if is_instance_valid(_bgm_player):
		var bgm_db: float = linear_to_db(maxf(0.0001, music_volume * 0.45)) if music_enabled and music_volume > 0.001 else -80.0
		_bgm_player.volume_db = bgm_db
		if not music_enabled and _bgm_player.playing:
			_bgm_player.stop()

func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	_apply_volumes()

func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	_apply_volumes()
	if not _is_dummy_driver and music_enabled and is_instance_valid(_bgm_player) and _bgm_player.stream != null and not _bgm_player.playing:
		_bgm_player.play()

func set_sfx_volume(linear_vol: float) -> void:
	sfx_volume = clampf(linear_vol, 0.0, 1.0)
	_apply_volumes()

func set_music_volume(linear_vol: float) -> void:
	music_volume = clampf(linear_vol, 0.0, 1.0)
	_apply_volumes()

func has_sound(sfx_name: String) -> bool:
	if _streams.is_empty():
		_synthesize_library()
	return _streams.has(sfx_name)

func play_sfx(sfx_name: String, pitch_scale: float = 1.0) -> void:
	if not sfx_enabled or sfx_volume <= 0.001:
		return
	if _streams.is_empty():
		_synthesize_library()
	var stream: AudioStreamWAV = _streams.get(sfx_name) as AudioStreamWAV
	if stream == null or _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = null
	var pool_count: int = _sfx_players.size()
	for offset in range(pool_count):
		var candidate: AudioStreamPlayer = _sfx_players[(_sfx_cursor + offset) % pool_count]
		if is_instance_valid(candidate) and not candidate.playing:
			player = candidate
			_sfx_cursor = (_sfx_cursor + offset + 1) % pool_count
			break
	if player == null:
		player = _sfx_players[_sfx_cursor % pool_count]
		_sfx_cursor = (_sfx_cursor + 1) % pool_count
	if not is_instance_valid(player):
		return
	if player.playing:
		player.stop()
	player.stream = stream
	player.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	if not _is_dummy_driver:
		player.play()

func start_music() -> void:
	if _streams.is_empty():
		_synthesize_library()
	if not is_instance_valid(_bgm_player):
		return
	if _bgm_player.stream == null:
		_bgm_player.stream = _streams.get("bgm_match")
	_apply_volumes()
	if not _is_dummy_driver and music_enabled and _bgm_player.stream != null and not _bgm_player.playing:
		_bgm_player.play()

func stop_music() -> void:
	if is_instance_valid(_bgm_player) and _bgm_player.playing:
		_bgm_player.stop()

func _synthesize_library() -> void:
	if not _streams.is_empty():
		return
	if _shared_pcm_cache.is_empty():
		_shared_pcm_cache["ui_click"] = {"pcm": _make_sweep(0.055, 620.0, 940.0, 0.35, 0.0, false).data, "loop": false}
		_shared_pcm_cache["pass"] = {"pcm": _make_sweep(0.085, 195.0, 340.0, 0.48, 0.15, false).data, "loop": false}
		_shared_pcm_cache["charge"] = {"pcm": _make_sweep(0.13, 280.0, 560.0, 0.30, 0.0, true).data, "loop": false}
		_shared_pcm_cache["shot"] = {"pcm": _make_sweep(0.17, 175.0, 52.0, 0.68, 0.38, false).data, "loop": false}
		_shared_pcm_cache["slide"] = {"pcm": _make_sweep(0.19, 140.0, 80.0, 0.18, 0.62, false).data, "loop": false}
		_shared_pcm_cache["steal"] = {"pcm": _make_two_tone(0.13, 523.25, 783.99, 0.42).data, "loop": false}
		_shared_pcm_cache["hissatsu_start"] = {"pcm": _make_sweep(0.28, 220.0, 920.0, 0.55, 0.08, true).data, "loop": false}
		_shared_pcm_cache["hissatsu_hit"] = {"pcm": _make_sweep(0.30, 260.0, 44.0, 0.78, 0.45, true).data, "loop": false}
		_shared_pcm_cache["gk_save"] = {"pcm": _make_two_tone(0.22, 392.0, 587.33, 0.58).data, "loop": false}
		_shared_pcm_cache["whistle_kickoff"] = {"pcm": _make_whistle([0.26]).data, "loop": false}
		_shared_pcm_cache["whistle_golden"] = {"pcm": _make_whistle([0.16, 0.24]).data, "loop": false}
		_shared_pcm_cache["whistle_end"] = {"pcm": _make_whistle([0.15, 0.15, 0.32]).data, "loop": false}
		_shared_pcm_cache["goal"] = {"pcm": _make_fanfare().data, "loop": false}
		_shared_pcm_cache["bgm_match"] = {"pcm": _make_arcade_bgm_loop().data, "loop": true}
	for sfx_key in _shared_pcm_cache.keys():
		var entry: Dictionary = _shared_pcm_cache[sfx_key]
		_streams[sfx_key] = _wrap_wav(entry["pcm"] as PackedByteArray, bool(entry["loop"]))

func _make_sweep(duration: float, f_start: float, f_end: float, tone_gain: float, noise_gain: float, square_ish: bool) -> AudioStreamWAV:
	var count: int = maxi(1, int(duration * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f_start * 100.0 + f_end)

	for i in range(count):
		var t: float = float(i) / float(count)
		var env: float = pow(1.0 - t, 1.35)
		if t < 0.06:
			env *= (t / 0.06)
		var freq: float = lerpf(f_start, f_end, t)
		phase += TAU * freq / float(MIX_RATE)
		var wave: float = sin(phase)
		if square_ish:
			wave = signf(wave) * 0.65 + sin(phase * 2.0) * 0.35
		var noise: float = rng.randf_range(-1.0, 1.0) * (1.0 - t * 0.7)
		var sample: float = clampf((wave * tone_gain + noise * noise_gain) * env, -0.95, 0.95)
		var pcm: int = int(sample * 32767.0)
		data.encode_s16(i * 2, pcm)

	return _wrap_wav(data, false)

func _make_two_tone(duration: float, f1: float, f2: float, gain: float) -> AudioStreamWAV:
	var count: int = maxi(1, int(duration * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(count)
		var freq: float = f1 if t < 0.45 else f2
		var local_t: float = (t / 0.45) if t < 0.45 else ((t - 0.45) / 0.55)
		var env: float = (1.0 - local_t * 0.65)
		phase += TAU * freq / float(MIX_RATE)
		var wave: float = sin(phase) * 0.75 + sin(phase * 2.0) * 0.25
		var sample: float = clampf(wave * gain * env, -0.95, 0.95)
		data.encode_s16(i * 2, int(sample * 32767.0))
	return _wrap_wav(data, false)

func _make_whistle(blasts: Array) -> AudioStreamWAV:
	var gap: float = 0.06
	var total_dur: float = 0.0
	for b in blasts:
		total_dur += float(b) + gap
	var count: int = maxi(1, int(total_dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	var write_idx: int = 0

	for b in blasts:
		var b_samples: int = int(float(b) * MIX_RATE)
		for i in range(b_samples):
			if write_idx >= count:
				break
			var t: float = float(i) / float(maxi(1, b_samples))
			var env: float = 1.0
			if t < 0.08:
				env = t / 0.08
			elif t > 0.82:
				env = (1.0 - t) / 0.18
			var trill: float = sin(float(write_idx) * TAU * 34.0 / float(MIX_RATE))
			var freq: float = 2780.0 + trill * 95.0
			phase += TAU * freq / float(MIX_RATE)
			var sample: float = clampf(sin(phase) * 0.48 * env, -0.95, 0.95)
			data.encode_s16(write_idx * 2, int(sample * 32767.0))
			write_idx += 1
		var g_samples: int = int(gap * MIX_RATE)
		for _j in range(g_samples):
			if write_idx >= count:
				break
			data.encode_s16(write_idx * 2, 0)
			write_idx += 1

	return _wrap_wav(data, false)

func _make_fanfare() -> AudioStreamWAV:
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.50]
	var durs: Array[float] = [0.11, 0.11, 0.12, 0.42]
	var total: float = 0.76
	var count: int = int(total * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var phase1: float = 0.0
	var phase2: float = 0.0
	var cursor: int = 0

	for n_idx in range(notes.size()):
		var freq: float = notes[n_idx]
		var n_samples: int = int(durs[n_idx] * MIX_RATE)
		for i in range(n_samples):
			if cursor >= count:
				break
			var t: float = float(i) / float(maxi(1, n_samples))
			var env: float = 1.0 - t * (0.45 if n_idx == 3 else 0.25)
			phase1 += TAU * freq / float(MIX_RATE)
			phase2 += TAU * (freq * 0.5) / float(MIX_RATE)
			var synth: float = signf(sin(phase1)) * 0.32 + sin(phase1) * 0.30 + sin(phase2) * 0.22
			var crowd: float = rng.randf_range(-1.0, 1.0) * 0.10
			var sample: float = clampf((synth * env + crowd * (1.0 - float(cursor) / float(count))), -0.95, 0.95)
			data.encode_s16(cursor * 2, int(sample * 32767.0))
			cursor += 1

	return _wrap_wav(data, false)

func _make_arcade_bgm_loop() -> AudioStreamWAV:
	# 16-step energetic arcade soccer bass + lead riff @ 150 BPM (0.10s per 16th -> 1.6s bar * 2 = 3.2s seamless loop)
	var step_dur: float = 0.10
	var melody: Array[float] = [
		329.63, 0.0, 392.00, 440.00, 493.88, 0.0, 392.00, 329.63,
		293.66, 329.63, 392.00, 0.0, 440.00, 392.00, 329.63, 293.66,
		329.63, 0.0, 392.00, 493.88, 587.33, 0.0, 493.88, 392.00,
		440.00, 0.0, 392.00, 329.63, 293.66, 0.0, 246.94, 293.66
	]
	var bass: Array[float] = [
		82.41, 82.41, 164.81, 82.41, 82.41, 82.41, 164.81, 82.41,
		73.42, 73.42, 146.83, 73.42, 98.00, 98.00, 110.00, 98.00,
		82.41, 82.41, 164.81, 82.41, 123.47, 123.47, 146.83, 123.47,
		110.00, 110.00, 98.00, 98.00, 73.42, 73.42, 98.00, 123.47
	]
	var step_samples: int = int(step_dur * MIX_RATE)
	var total_samples: int = step_samples * melody.size()
	var data := PackedByteArray()
	data.resize(total_samples * 2)

	var lead_phase: float = 0.0
	var bass_phase: float = 0.0
	var idx: int = 0
	for s in range(melody.size()):
		var mf: float = melody[s]
		var bf: float = bass[s]
		for i in range(step_samples):
			var t: float = float(i) / float(step_samples)
			var lead_val: float = 0.0
			if mf > 0.0:
				lead_phase += TAU * mf / float(MIX_RATE)
				var l_env: float = (1.0 - t * 0.65)
				lead_val = (signf(sin(lead_phase)) * 0.45 + sin(lead_phase) * 0.55) * 0.24 * l_env
			bass_phase += TAU * bf / float(MIX_RATE)
			var b_env: float = 1.0 - t * 0.45
			var bass_val: float = sin(bass_phase) * 0.32 * b_env
			var hat: float = (sin(float(i) * 1.9) * 0.07 * (1.0 - t)) if (s % 2 == 1 and t < 0.25) else 0.0
			var sample: float = clampf(lead_val + bass_val + hat, -0.90, 0.90)
			data.encode_s16(idx * 2, int(sample * 32767.0))
			idx += 1

	return _wrap_wav(data, true)

func _wrap_wav(pcm_bytes: PackedByteArray, looped: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = pcm_bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(pcm_bytes.size() / 2)
	return wav

