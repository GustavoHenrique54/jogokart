class_name AudioManager
extends Node
## Gerenciador de Áudio in-game do jogo de rolimã.
## Carrega arquivos de áudio de 'res://audio/' caso existam, ou gera sintetizadores
## procedurais seguros (AudioStreamWAV) em memória caso nenhum arquivo tenha sido importado.

const SOUND_PATHS := {
	"countdown_low": "res://audio/countdown_beep.wav",
	"countdown_go": "res://audio/countdown_go.wav",
	"wheel_roll": "res://audio/wheel_roll.wav",
	"kart_impact": "res://audio/kart_impact.wav",
	"skill_q": "res://audio/skill_q.wav",
	"skill_e": "res://audio/skill_e.wav",
	"skill_r": "res://audio/skill_r.wav",
}

static var _stream_cache: Dictionary = {}


static func get_stream(key: String) -> AudioStream:
	if _stream_cache.has(key):
		return _stream_cache[key]

	# 1. Tenta carregar do disco caso exista
	var path: String = SOUND_PATHS.get(key, "")
	if path != "" and (FileAccess.file_exists(path) or ResourceLoader.exists(path)):
		var res := load(path)
		if res is AudioStream:
			_stream_cache[key] = res
			return res

	# 2. Fallback procedural sintético de alta qualidade
	var stream: AudioStreamWAV = null
	match key:
		"countdown_low":
			stream = _generate_beep_stream(440.0, 0.16, false)
		"countdown_go":
			stream = _generate_beep_stream(880.0, 0.55, true)
		"wheel_roll":
			stream = _generate_wheel_roll_stream()
		"kart_impact":
			stream = _generate_impact_stream()
		"skill_q":
			stream = _generate_skill_q_stream()
		"skill_e":
			stream = _generate_skill_e_stream()
		"skill_r":
			stream = _generate_skill_r_stream()
		_:
			stream = _generate_beep_stream(500.0, 0.1, false)

	_stream_cache[key] = stream
	return stream


static func play_sound_2d(caller: Node, key: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	if caller == null or not caller.is_inside_tree():
		return null
	var player := AudioStreamPlayer.new()
	player.stream = get_stream(key)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = &"Master"
	caller.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player


static func play_sound_3d(caller: Node, key: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	if caller == null or not caller.is_inside_tree():
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = get_stream(key)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = 65.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.bus = &"Master"
	caller.get_tree().current_scene.add_child(player)
	player.global_position = pos
	player.finished.connect(player.queue_free)
	player.play()
	return player


static func play_countdown_beep(caller: Node, is_go: bool) -> void:
	var key := "countdown_go" if is_go else "countdown_low"
	var vol := 2.0 if is_go else -1.0
	play_sound_2d(caller, key, vol, 1.0)


# =========================================================== GERADORES SINTÉTICOS DE ÁUDIO

static func _generate_beep_stream(freq: float, duration: float, is_chord: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples * 2) # 16-bit mono
	var inv_sr := 1.0 / float(sample_rate)

	for i in total_samples:
		var t := float(i) * inv_sr
		var env := exp(-t * (4.5 if is_chord else 14.0))
		var sample := 0.0
		if is_chord:
			# Acorde triunfante maior (fundamental + terça maior + quinta justa + oitava)
			sample = (sin(TAU * freq * t) * 0.40
				+ sin(TAU * freq * 1.2599 * t) * 0.32
				+ sin(TAU * freq * 1.4983 * t) * 0.28
				+ sin(TAU * freq * 2.0 * t) * 0.15) * env
		else:
			sample = (sin(TAU * freq * t) * 0.85 + sin(TAU * freq * 2.0 * t) * 0.15) * env

		var s16 := clampi(int(sample * 28000.0), -32768, 32767)
		data.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func _generate_wheel_roll_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 1.2
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	var inv_sr := 1.0 / float(sample_rate)

	var seed_val := 42
	for i in total_samples:
		var t := float(i) * inv_sr
		# Ruído com textura de asfalto
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_val % 1000) / 500.0 - 1.0

		# Ressonância metálica do rolamento de ferro
		var bearing_whine := sin(TAU * 1450.0 * t) * 0.18 + sin(TAU * 720.0 * t) * 0.22
		var asphalt_rumble := sin(TAU * 85.0 * t + noise * 0.5) * 0.35

		var sample := (noise * 0.32 + bearing_whine + asphalt_rumble) * 0.45

		# Fade suave nas pontas para garantir loop 100% contínuo sem estalos
		var fade := 1.0
		var edge_samples := int(sample_rate * 0.05)
		if i < edge_samples:
			fade = float(i) / float(edge_samples)
		elif i > total_samples - edge_samples:
			fade = float(total_samples - i) / float(edge_samples)

		var s16 := clampi(int(sample * fade * 24000.0), -32768, 32767)
		data.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = total_samples
	stream.data = data
	return stream


static func _generate_impact_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.4
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	var inv_sr := 1.0 / float(sample_rate)

	var seed_val := 1337
	for i in total_samples:
		var t := float(i) * inv_sr
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_val % 1000) / 500.0 - 1.0

		var sub_freq := lerpf(130.0, 35.0, clampf(t / 0.18, 0.0, 1.0))
		var sub_thud := sin(TAU * sub_freq * t) * exp(-t * 18.0) * 0.7
		var crunch := noise * exp(-t * 26.0) * 0.55

		var sample := (sub_thud + crunch) * 0.8
		var s16 := clampi(int(sample * 29000.0), -32768, 32767)
		data.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func _generate_skill_q_stream() -> AudioStreamWAV:
	# Som ofensivo de ataque/disparo
	var sample_rate := 22050
	var duration := 0.3
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	var inv_sr := 1.0 / float(sample_rate)

	for i in total_samples:
		var t := float(i) * inv_sr
		var f := lerpf(860.0, 180.0, clampf(t / 0.22, 0.0, 1.0))
		var env := exp(-t * 10.0)
		var sample := (sin(TAU * f * t) * 0.75 + (0.25 if sin(TAU * f * 3.0 * t) > 0.0 else -0.25)) * env * 0.7
		var s16 := clampi(int(sample * 28000.0), -32768, 32767)
		data.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func _generate_skill_e_stream() -> AudioStreamWAV:
	# Som de mobilidade / salto rasante / propulsão
	var sample_rate := 22050
	var duration := 0.4
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	var inv_sr := 1.0 / float(sample_rate)

	var seed_val := 777
	for i in total_samples:
		var t := float(i) * inv_sr
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_val % 1000) / 500.0 - 1.0

		var f := lerpf(300.0, 750.0, clampf(t / 0.35, 0.0, 1.0))
		var sweep := sin(TAU * f * t) * 0.5
		var env := sin(clampf(t / duration, 0.0, 1.0) * PI)
		var sample := (sweep + noise * 0.3) * env * 0.65
		var s16 := clampi(int(sample * 28000.0), -32768, 32767)
		data.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func _generate_skill_r_stream() -> AudioStreamWAV:
	# Som de poder ancestral / ultimate
	var sample_rate := 22050
	var duration := 0.6
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	var inv_sr := 1.0 / float(sample_rate)

	for i in total_samples:
		var t := float(i) * inv_sr
		var vib := sin(TAU * 6.0 * t) * 8.0
		var sample := (sin(TAU * (220.0 + vib) * t) * 0.38
			+ sin(TAU * (330.0 + vib) * t) * 0.32
			+ sin(TAU * (440.0 + vib) * t) * 0.30) * exp(-t * 5.0) * 0.75
		var s16 := clampi(int(sample * 28000.0), -32768, 32767)
		data.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
