extends Node

signal state_changed(state: String, message: String)
signal auto_mode_changed(enabled: bool)
signal audio_level_changed(level: float)
signal echo_finished(duration_seconds: float)

const CAPTURE_BUS_NAME := "MicCapture"
const CAPTURE_SILENCE_BUS_NAME := "MicSilence"
const MAX_CLIP_SECONDS := 12.0
const MAX_AUTO_CLIP_SECONDS := 8.0
const MIN_CLIP_SECONDS := 0.32
const MIN_AUTO_CLIP_SECONDS := 0.20
const PRE_ROLL_SECONDS := 0.25
const AUTO_START_THRESHOLD := 0.009
const AUTO_STOP_THRESHOLD := 0.024
const AUTO_END_SILENCE_SECONDS := 0.58
const PITCH_SCALE := 1.6
const VOICE_PLAYBACK_VOLUME_DB := 3.0
const VOICE_TARGET_PEAK := 0.67
const VOICE_MAX_INPUT_GAIN := 2.5

var current_state := "off"
var current_message := "麦克风默认关闭；按住按钮说话，或开启自动聆听。"

var _capture_effect: AudioEffectCapture
var _capture_bus_index := -1
var _microphone_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _capture_active := false
var _auto_enabled := false
var _pause_tokens: Dictionary = {}
var _pause_serial := 0
var _legacy_pause_tokens: Array[String] = []
var _manual_held := false
var _permission_pending := false
var _pending_action := ""
var _recording := false
var _recording_mode := ""
var _sample_rate := 48000
var _recorded_samples := PackedFloat32Array()
var _pre_roll := PackedFloat32Array()
var _loud_frames := 0
var _silent_frames := 0
var _recording_elapsed := 0.0
var _last_clip_duration := 0.0
var _capture_wait_elapsed := 0.0
var _capture_input_warning_shown := false


func _ready() -> void:
	_sample_rate = int(AudioServer.get_mix_rate())
	_ensure_capture_bus()
	_microphone_player = AudioStreamPlayer.new()
	_microphone_player.name = "MicrophoneInput"
	_microphone_player.stream = AudioStreamMicrophone.new()
	_microphone_player.bus = CAPTURE_BUS_NAME
	add_child(_microphone_player)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "VoicePlayback"
	_voice_player.bus = "SFX"
	_voice_player.finished.connect(_on_voice_playback_finished)
	add_child(_voice_player)
	get_tree().on_request_permissions_result.connect(_on_permission_result)
	_emit_state("off", current_message)


func set_auto_mode(enabled: bool) -> void:
	if enabled == _auto_enabled and not _permission_pending:
		return
	_auto_enabled = enabled
	if not enabled:
		if _pending_action == "auto":
			_pending_action = ""
		if not _manual_held and not _recording:
			_stop_microphone()
			_emit_state("off", "自动聆听已关闭。")
		auto_mode_changed.emit(false)
		return
	if _pause_tokens.is_empty() and _request_or_start("auto"):
		auto_mode_changed.emit(true)
	else:
		auto_mode_changed.emit(true)


func start_manual_recording() -> void:
	if not _pause_tokens.is_empty():
		return
	_manual_held = true
	if _capture_active:
		return
	_request_or_start("manual")


func stop_manual_recording() -> void:
	_manual_held = false
	if _recording and _recording_mode == "manual":
		_finish_recording()
	elif not _auto_enabled and not _permission_pending:
		_stop_microphone()
		_emit_state("off", "松开了；下次按住就能再说。")


func cancel_all() -> void:
	_manual_held = false
	_auto_enabled = false
	_pause_tokens.clear()
	_legacy_pause_tokens.clear()
	_permission_pending = false
	_pending_action = ""
	_recording = false
	_recorded_samples.clear()
	_pre_roll.clear()
	_loud_frames = 0
	_silent_frames = 0
	_stop_microphone()
	if _voice_player != null:
		_voice_player.stop()
		_voice_player.stream = null
	_emit_state("off", "互动已暂停，麦克风已关闭。")
	auto_mode_changed.emit(false)


func suspend_for_feedback() -> void:
	_legacy_pause_tokens.append(acquire_suspend("character_feedback"))


func resume_after_feedback() -> void:
	if _legacy_pause_tokens.is_empty():
		return
	release_suspend(_legacy_pause_tokens.pop_back())


func acquire_suspend(reason: String) -> String:
	_pause_serial += 1
	var token := "%s:%d" % [reason, _pause_serial]
	var was_unpaused := _pause_tokens.is_empty()
	_pause_tokens[token] = reason
	if was_unpaused:
		_manual_held = false
		_recording = false
		_recording_mode = ""
		_recorded_samples.clear()
		_pre_roll.clear()
		if _voice_player != null and _voice_player.playing:
			_voice_player.stop()
			_voice_player.stream = null
		_stop_microphone()
		audio_level_changed.emit(0.0)
		_emit_state("off", "麦克风已暂时暂停；关闭面板后继续聆听。")
	return token


func release_suspend(token: String) -> void:
	if not _pause_tokens.has(token):
		return
	_pause_tokens.erase(token)
	if not _pause_tokens.is_empty() or not _auto_enabled:
		return
	if _manual_held:
		_request_or_start("manual")
	elif _auto_enabled:
		_request_or_start("auto")


func _process(delta: float) -> void:
	if not _pause_tokens.is_empty():
		audio_level_changed.emit(0.0)
		return
	if _recording:
		_recording_elapsed += delta
		var max_recording_seconds := MAX_AUTO_CLIP_SECONDS if _recording_mode == "auto" else MAX_CLIP_SECONDS
		if _recording_elapsed >= max_recording_seconds:
			_finish_recording()
			if not _capture_active:
				return
	if not _capture_active or _capture_effect == null:
		return
	var frames_available := _capture_effect.get_frames_available()
	if frames_available <= 0:
		_capture_wait_elapsed += delta
		if _capture_wait_elapsed >= 2.0 and not _capture_input_warning_shown:
			_capture_input_warning_shown = true
			_emit_state("input_unavailable", "麦克风暂时没有输入，请检查系统权限和输入设备。")
		audio_level_changed.emit(0.0)
		return
	var stereo_samples := _capture_effect.get_buffer(frames_available)
	if stereo_samples.is_empty():
		return
	_capture_wait_elapsed = 0.0
	if _capture_input_warning_shown:
		_capture_input_warning_shown = false
		_emit_state("listening" if _manual_held else "armed", "我在聽你說話，安靜一會兒就會模仿。")
	var mono_samples := PackedFloat32Array()
	mono_samples.resize(stereo_samples.size())
	var sum_squares := 0.0
	for i in range(stereo_samples.size()):
		# Some phone microphones provide meaningful audio on only one channel.
		# Taking the stronger channel also avoids phase cancellation when the
		# left and right samples differ.
		var left_sample: float = stereo_samples[i].x
		var right_sample: float = stereo_samples[i].y
		var sample := left_sample if absf(left_sample) >= absf(right_sample) else right_sample
		mono_samples[i] = sample
		sum_squares += sample * sample
	var rms := sqrt(sum_squares / float(stereo_samples.size()))
	audio_level_changed.emit(clampf(rms * 8.0, 0.0, 1.0))

	if _recording:
		_append_recorded(mono_samples)
		if _recording_mode == "auto":
			if rms < AUTO_STOP_THRESHOLD:
				_silent_frames += stereo_samples.size()
			else:
				_silent_frames = 0
			if _silent_frames >= int(_sample_rate * AUTO_END_SILENCE_SECONDS):
				_finish_recording()
		elif _recorded_samples.size() >= int(_sample_rate * MAX_CLIP_SECONDS):
			_finish_recording()
		return

	if _manual_held:
		_begin_recording("manual", false)
		_append_recorded(mono_samples)
		return
	if not _auto_enabled:
		return

	if rms >= AUTO_START_THRESHOLD:
		_loud_frames += stereo_samples.size()
		if _loud_frames >= int(_sample_rate * 0.10):
			_begin_recording("auto", true)
			_append_recorded(mono_samples)
			_loud_frames = 0
		else:
			_push_pre_roll(mono_samples)
	else:
		_loud_frames = 0
		_push_pre_roll(mono_samples)


func _request_or_start(action: String) -> bool:
	if not _pause_tokens.is_empty():
		return false
	if _permission_pending:
		return false
	if OS.has_feature("android"):
		_pending_action = action
		if OS.request_permission("android.permission.RECORD_AUDIO"):
			_pending_action = ""
			_start_action(action)
			return true
		_permission_pending = true
		_emit_state("permission_pending", "請允許麥克風，西小電才能聽見你。")
		return false
	if OS.has_feature("ios"):
		# OS.request_permission() is not implemented on iOS. Starting the
		# microphone stream lets iOS request the permission from the user.
		_start_action(action)
		return true
	_start_action(action)
	return true


func _on_permission_result(permission: String, granted: bool) -> void:
	if not _permission_pending:
		return
	if permission != "android.permission.RECORD_AUDIO":
		return
	_permission_pending = false
	var action := _pending_action
	_pending_action = ""
	if not granted:
		_auto_enabled = false
		auto_mode_changed.emit(false)
		_emit_state("permission_denied", "沒有麥克風權限也能繼續摸摸和照顧我。")
		return
	if not _pause_tokens.is_empty():
		return
	if action == "auto" and _auto_enabled:
		_start_action("auto")
	elif action == "manual" and _manual_held:
		_start_action("manual")


func _start_action(action: String) -> void:
	if not _pause_tokens.is_empty():
		return
	if action == "auto" and _auto_enabled:
		_start_microphone()
		_emit_state("armed", "我在聽你說話，安靜一會兒就會模仿。")
	elif action == "manual" and _manual_held:
		_start_microphone()
		_emit_state("listening", "我在聽你說話…")


func _ensure_capture_bus() -> void:
	var silence_bus_index := AudioServer.get_bus_index(CAPTURE_SILENCE_BUS_NAME)
	if silence_bus_index < 0:
		AudioServer.add_bus()
		silence_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(silence_bus_index, CAPTURE_SILENCE_BUS_NAME)
	AudioServer.set_bus_send(silence_bus_index, "Master")
	AudioServer.set_bus_mute(silence_bus_index, true)

	_capture_bus_index = AudioServer.get_bus_index(CAPTURE_BUS_NAME)
	if _capture_bus_index < 0:
		AudioServer.add_bus()
		_capture_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_capture_bus_index, CAPTURE_BUS_NAME)
	AudioServer.set_bus_send(_capture_bus_index, CAPTURE_SILENCE_BUS_NAME)
	AudioServer.set_bus_mute(_capture_bus_index, false)
	for effect_index in range(AudioServer.get_bus_effect_count(_capture_bus_index)):
		var effect := AudioServer.get_bus_effect(_capture_bus_index, effect_index)
		if effect is AudioEffectCapture:
			_capture_effect = effect
			return
	_capture_effect = AudioEffectCapture.new()
	_capture_effect.buffer_length = 0.35
	AudioServer.add_bus_effect(_capture_bus_index, _capture_effect, 0)


func _start_microphone() -> void:
	if _capture_active:
		return
	if _capture_effect != null:
		_capture_effect.clear_buffer()
	_microphone_player.play()
	_capture_active = true
	_capture_wait_elapsed = 0.0
	_capture_input_warning_shown = false
	_pre_roll.clear()
	_loud_frames = 0
	_silent_frames = 0


func _stop_microphone() -> void:
	if _microphone_player != null and _microphone_player.playing:
		_microphone_player.stop()
	_capture_active = false
	if _capture_effect != null:
		_capture_effect.clear_buffer()
	_pre_roll.clear()
	_loud_frames = 0
	_silent_frames = 0


func _begin_recording(mode: String, include_pre_roll: bool) -> void:
	_recording = true
	_recording_mode = mode
	_recording_elapsed = 0.0
	_recorded_samples = PackedFloat32Array()
	if include_pre_roll and not _pre_roll.is_empty():
		_recorded_samples.append_array(_pre_roll)
	_pre_roll.clear()
	_silent_frames = 0
	_emit_state("listening", "我在認真聽你說…")


func _append_recorded(samples: PackedFloat32Array) -> void:
	var max_seconds := MAX_AUTO_CLIP_SECONDS if _recording_mode == "auto" else MAX_CLIP_SECONDS
	var remaining := int(_sample_rate * max_seconds) - _recorded_samples.size()
	if remaining <= 0:
		_finish_recording()
		return
	if samples.size() >= remaining:
		_recorded_samples.append_array(samples.slice(0, remaining))
		_finish_recording()
	else:
		_recorded_samples.append_array(samples)


func _push_pre_roll(samples: PackedFloat32Array) -> void:
	_pre_roll.append_array(samples)
	var max_samples := int(_sample_rate * PRE_ROLL_SECONDS)
	if _pre_roll.size() > max_samples:
		_pre_roll = _pre_roll.slice(_pre_roll.size() - max_samples)


func _finish_recording() -> void:
	if not _recording:
		return
	_recording = false
	_recording_elapsed = 0.0
	var finished_mode := _recording_mode
	var clip := _recorded_samples
	_recorded_samples = PackedFloat32Array()
	_recording_mode = ""
	var duration := float(clip.size()) / float(maxi(_sample_rate, 1))
	var minimum_duration := MIN_AUTO_CLIP_SECONDS if finished_mode == "auto" else MIN_CLIP_SECONDS
	if duration < minimum_duration:
		if not _auto_enabled:
			_stop_microphone()
			_emit_state("off", "声音太短了，再试一次吧。")
		else:
			_emit_state("armed", "我在听你说话，安静一会儿就会模仿。")
		return
	_stop_microphone()
	var wav := _make_wav(clip)
	if wav == null:
		_emit_state("off", "这次没有听清，再试一次吧。")
		return
	_last_clip_duration = duration
	_voice_player.stream = wav
	_voice_player.pitch_scale = PITCH_SCALE
	_voice_player.volume_db = VOICE_PLAYBACK_VOLUME_DB
	_voice_player.play()
	_emit_state("repeating", "西小电正在用高音模仿你！")


func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	if samples.is_empty():
		return null
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	var input_gain := 1.0
	if peak > 0.001:
		input_gain = minf(VOICE_MAX_INPUT_GAIN, VOICE_TARGET_PEAK / peak)
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	var fade_samples := mini(int(_sample_rate * 0.025), int(floor(float(samples.size()) * 0.5)))
	for i in range(samples.size()):
		var fade := 1.0
		if fade_samples > 0 and i < fade_samples:
			fade = float(i) / float(fade_samples)
		elif fade_samples > 0 and i >= samples.size() - fade_samples:
			fade = float(samples.size() - 1 - i) / float(fade_samples)
		var value := clampf(samples[i] * input_gain * fade, -1.0, 1.0)
		pcm.encode_s16(i * 2, int(round(value * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _sample_rate
	wav.stereo = false
	wav.data = pcm
	return wav


func _on_voice_playback_finished() -> void:
	_voice_player.stream = null
	_voice_player.pitch_scale = 1.0
	if _auto_enabled:
		_emit_state("cooldown", "剛才那句學得真像！")
	else:
		_emit_state("off", "模仿完成，還想再說一句嗎？")
	echo_finished.emit(_last_clip_duration)
	_last_clip_duration = 0.0
	if _auto_enabled and _pause_tokens.is_empty():
		await get_tree().create_timer(0.55).timeout
		if _auto_enabled and _pause_tokens.is_empty():
			_start_microphone()
			_emit_state("armed", "我在聽你說話，安靜一會兒就會模仿。")


func _emit_state(next_state: String, message: String) -> void:
	current_state = next_state
	current_message = message
	state_changed.emit(current_state, current_message)
