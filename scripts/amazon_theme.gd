class_name AmazonTheme
extends RefCounted
## Gerador procedural da Trilha Sonora Tema "Floresta Amazônica" do Lobby.
## Cria um AudioStreamWAV 16-bit estéreo com instrumentos tribais, flauta indígena e ambiência de selva.

static func generate_amazon_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 8.0 # 8 segundos em loop perfeito (16 batidas a 120 BPM)
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples * 4) # 16-bit stereo (4 bytes por amostra)

	# Frequências da escala pentatônica amazônica (La menor pentatônica)
	var notes = [220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25]
	# Padrão melódico da flauta (compasso de 16 passos de 0.5s cada)
	var flute_melody = [
		{"t_start": 0.0, "dur": 0.9, "freq": 440.0},
		{"t_start": 1.0, "dur": 0.45, "freq": 392.0},
		{"t_start": 1.5, "dur": 0.45, "freq": 329.63},
		{"t_start": 2.0, "dur": 0.9, "freq": 293.66},
		{"t_start": 3.0, "dur": 0.8, "freq": 329.63},
		{"t_start": 4.0, "dur": 0.9, "freq": 523.25},
		{"t_start": 5.0, "dur": 0.45, "freq": 440.0},
		{"t_start": 5.5, "dur": 0.45, "freq": 392.0},
		{"t_start": 6.0, "dur": 0.9, "freq": 440.0},
		{"t_start": 7.0, "dur": 0.8, "freq": 329.63}
	]

	# Padrão percussivo da marimba de madeira
	var marimba_notes = [
		{"t": 0.0, "freq": 220.0}, {"t": 0.5, "freq": 261.63}, {"t": 1.0, "freq": 329.63},
		{"t": 2.0, "freq": 293.66}, {"t": 2.5, "freq": 392.0}, {"t": 3.0, "freq": 440.0},
		{"t": 4.0, "freq": 261.63}, {"t": 4.5, "freq": 329.63}, {"t": 5.0, "freq": 392.0},
		{"t": 6.0, "freq": 220.0}, {"t": 6.5, "freq": 293.66}, {"t": 7.0, "freq": 261.63}
	]

	var inv_sr := 1.0 / float(sample_rate)

	for i in range(total_samples):
		var t := float(i) * inv_sr
		var left := 0.0
		var right := 0.0

		# 1. Tambor de Tronco / Batida Tribal (a cada 1.0s e 2.0s)
		var beat_time := fmod(t, 1.0)
		var drum_env := exp(-beat_time * 14.0)
		var drum_sound := sin(2.0 * PI * (65.0 - beat_time * 25.0) * beat_time) * drum_env * 0.32
		left += drum_sound
		right += drum_sound

		# Chocalho / Maracá de sementes em semicolcheias (a cada 0.25s)
		var rattle_time := fmod(t, 0.25)
		var rattle_env := exp(-rattle_time * 28.0)
		var rattle_noise := (sin(float(i * 17 % 100)) * 0.5) * rattle_env * 0.06
		left += rattle_noise * 0.8
		right += rattle_noise * 1.2

		# 2. Flauta Indígena Amazônica (Pífano com vibrato de sopro)
		for fn in flute_melody:
			var t_note: float = t - float(fn["t_start"])
			var dur: float = float(fn["dur"])
			if t_note >= 0.0 and t_note < dur:
				var note_env := sin(PI * (t_note / dur)) # Envelope em sino suave
				var vibrato := 1.0 + 0.015 * sin(2.0 * PI * 5.2 * t_note)
				var base_freq: float = float(fn["freq"]) * vibrato
				# Sopro com harmônicos quentes
				var flute_wave := sin(2.0 * PI * base_freq * t_note) * 0.7 + sin(2.0 * PI * base_freq * 2.0 * t_note) * 0.22
				var s_flute := flute_wave * note_env * 0.24
				left += s_flute * 0.95
				right += s_flute * 1.05

		# 3. Marimba de Madeira (Notas curtas e secas de madeira da selva)
		for mn in marimba_notes:
			var t_marimba: float = t - float(mn["t"])
			if t_marimba >= 0.0 and t_marimba < 0.4:
				var m_env := exp(-t_marimba * 12.0)
				var m_freq: float = float(mn["freq"])
				var m_wave := (sin(2.0 * PI * m_freq * t_marimba) + sin(2.0 * PI * m_freq * 3.0 * t_marimba) * 0.2) * m_env * 0.2
				left += m_wave * 1.1
				right += m_wave * 0.9

		# 4. Pássaros Tropicais e Vento na Floresta
		# Pássaro 1 em t=1.2s
		if t >= 1.2 and t < 1.6:
			var pt := t - 1.2
			var p_freq := 2400.0 + sin(pt * 40.0) * 600.0
			var bird := sin(2.0 * PI * p_freq * pt) * exp(-pt * 8.0) * 0.08
			left += bird * 0.4
			right += bird * 1.3

		# Pássaro 2 em t=5.2s
		if t >= 5.2 and t < 5.65:
			var pt := t - 5.2
			var p_freq := 2800.0 - pt * 800.0
			var bird := sin(2.0 * PI * p_freq * pt) * exp(-pt * 7.0) * 0.07
			left += bird * 1.3
			right += bird * 0.4

		# Brisa suave contínua
		var wind := sin(2.0 * PI * 0.3 * t) * 0.02
		left += wind
		right += wind

		# Converte para 16-bit inteiro com clamp
		var l_clamped := int(clampf(left, -1.0, 1.0) * 32767.0)
		var r_clamped := int(clampf(right, -1.0, 1.0) * 32767.0)

		var idx := i * 4
		data.encode_s16(idx, l_clamped)
		data.encode_s16(idx + 2, r_clamped)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = true
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = total_samples
	stream.data = data
	return stream
