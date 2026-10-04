extends Node3D

const CHARACTER_SCRIPT = preload("res://Scripts/CharacterPresenter.gd")
const HUD_SCRIPT = preload("res://Scripts/HUD.gd")
const MINIGAME_SCRIPT = preload("res://Scripts/Minigame.gd")
const PET_STATE_SCRIPT = preload("res://Scripts/PetState.gd")
const VOICE_SERVICE_SCRIPT = preload("res://Scripts/VoiceService.gd")
const GAME_SERVICES_SCRIPT = preload("res://Scripts/Core/GameServices.gd")
const FEATURE_OVERLAY_SCRIPT = preload("res://Scripts/FeatureOverlay.gd")
const BGM_STREAM: AudioStreamWAV = preload("res://Assests/Audio/bgm_sunny_8bit.wav")
const LAUGH_STREAM: AudioStreamWAV = preload("res://Assests/Audio/NAILONGLaugh.wav")
const AUDIO_SETTINGS_PATH := "user://audio_settings.cfg"
const DEFAULT_MUSIC_PERCENT := 30.0
const AUDIO_SETTINGS_VERSION := 2

var _character: Node3D
var _hud: Control
var _pet_state: Node
var _game_services: Node
var _voice: Node
var _canvas: CanvasLayer
var _minigame: Node
var _music_player: AudioStreamPlayer
var _laugh_player: AudioStreamPlayer
var _sfx_bus_index := -1
var _resting := false
var _feature_overlay: Control
var _feature_voice_token := ""
var _laugh_voice_token := ""
var _minigame_voice_token := ""
var _background_voice_token := ""
var _minigame_run_id := ""


func _ready() -> void:
	get_tree().quit_on_go_back = false
	_build_room()
	_build_audio()
	_game_services = GAME_SERVICES_SCRIPT.new()
	_game_services.name = "GameServices"
	add_child(_game_services)
	_pet_state = PET_STATE_SCRIPT.new()
	_pet_state.name = "PetState"
	_pet_state.setup(_game_services.store, _game_services.ready_ok)
	add_child(_pet_state)
	_character = CHARACTER_SCRIPT.new()
	_character.name = "Xixiaodian"
	_character.position = Vector3(0.0, 0.04, 0.0)
	add_child(_character)
	_voice = VOICE_SERVICE_SCRIPT.new()
	_voice.name = "VoiceService"
	add_child(_voice)
	_canvas = CanvasLayer.new()
	_canvas.name = "HUDLayer"
	add_child(_canvas)
	_hud = HUD_SCRIPT.new()
	_hud.name = "HUD"
	_canvas.add_child(_hud)
	_feature_overlay = FEATURE_OVERLAY_SCRIPT.new()
	_feature_overlay.name = "FeatureOverlay"
	_feature_overlay.setup(_game_services)
	_canvas.add_child(_feature_overlay)
	_connect_gameplay()
	_hud.set_pet_state(_pet_state.get_snapshot())
	_hud.set_voice_status(_voice.current_message, _voice.current_state)
	var audio_settings := _load_audio_settings()
	_feature_overlay.set_audio_settings(audio_settings.music_percent, audio_settings.sfx_percent)
	_hud.set_mail_badges(_game_services.mailbox.pending_count() if _game_services.ready_ok else 0, _game_services.mailbox.unread_count() if _game_services.ready_ok else 0)
	_feature_overlay.set_mail_badges(_game_services.mailbox.pending_count() if _game_services.ready_ok else 0, _game_services.mailbox.unread_count() if _game_services.ready_ok else 0)
	if not _game_services.ready_ok:
		_hud.show_hint("存档或配置无法安全读取：%s" % _game_services.startup_error)
	_apply_audio_settings(audio_settings.music_percent, audio_settings.sfx_percent, false)
	call_deferred("_ensure_background_music")


func _connect_gameplay() -> void:
	_pet_state.state_changed.connect(_on_pet_state_changed)
	_game_services.state_changed.connect(_on_game_state_changed)
	_game_services.trip_mail_arrived.connect(_on_trip_mail_arrived)
	_voice.state_changed.connect(_on_voice_state_changed)
	_voice.audio_level_changed.connect(_hud.set_audio_level)
	_voice.echo_finished.connect(_on_echo_finished)
	_voice.auto_mode_changed.connect(_hud.set_auto_enabled)
	_hud.auto_listen_toggled.connect(_voice.set_auto_mode)
	_hud.hold_started.connect(_voice.start_manual_recording)
	_hud.hold_released.connect(_voice.stop_manual_recording)
	_hud.play_requested.connect(_on_play_requested)
	_hud.rest_requested.connect(_on_rest_requested)
	_hud.touch_requested.connect(_on_pet_requested)
	_hud.feature_open_requested.connect(_on_feature_open_requested)
	_feature_overlay.command_requested.connect(_on_feature_command)
	_feature_overlay.closed.connect(_on_feature_overlay_closed)
	_feature_overlay.audio_preview_changed.connect(_on_audio_preview_changed)
	_feature_overlay.audio_settings_changed.connect(_on_audio_settings_changed)


func _build_room() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#878dbd")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#e5dbff")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.78
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	_add_background()

	var camera := Camera3D.new()
	camera.name = "PortraitCamera"
	camera.position = Vector3(0.0, 1.10, 3.25)
	camera.fov = 35.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.32, 0.0), Vector3.UP)
	camera.current = true

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, -24.0, 0.0)
	key_light.light_color = Color("#fff0d7")
	key_light.light_energy = 0.56
	key_light.shadow_enabled = true
	add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-2.0, 1.6, 1.4)
	fill_light.light_color = Color("#a9b8ff")
	fill_light.light_energy = 0.14
	fill_light.omni_range = 5.0
	add_child(fill_light)

	var ground := MeshInstance3D.new()
	ground.name = "RoomFloor"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(30.0, 30.0)
	ground.mesh = ground_mesh
	ground.position.y = -0.14
	var ground_material := StandardMaterial3D.new()
	ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_material.albedo_color = Color("#515574")
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	add_child(ground)

	var lower_stage := _make_stage_disc(0.86, 0.12, Color("#5e5a80"))
	lower_stage.position.y = -0.08
	add_child(lower_stage)
	var upper_stage := _make_stage_disc(0.70, 0.055, Color("#897ba8"))
	upper_stage.position.y = 0.005
	add_child(upper_stage)


func _add_background() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	gradient.colors = PackedColorArray([
		Color("#f6d8dc"),
		Color("#c4bce8"),
		Color("#8496cf"),
	])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 4
	gradient_texture.height = 128
	gradient_texture.fill_from = Vector2(0.5, 0.0)
	gradient_texture.fill_to = Vector2(0.5, 1.0)
	var backdrop := MeshInstance3D.new()
	backdrop.name = "SoftGradientBackdrop"
	var backdrop_mesh := PlaneMesh.new()
	backdrop_mesh.size = Vector2(7.0, 6.0)
	backdrop.mesh = backdrop_mesh
	backdrop.position = Vector3(0.0, 1.45, -1.65)
	backdrop.rotation.x = PI * 0.5
	var backdrop_material := StandardMaterial3D.new()
	backdrop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop_material.albedo_texture = gradient_texture
	backdrop_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	backdrop.material_override = backdrop_material
	add_child(backdrop)

	_add_backdrop_disc(0.49, Color("#d6c8ed"), Vector3(0.0, 0.42, -0.88))
	_add_backdrop_disc(0.45, Color("#c4bce8"), Vector3(0.0, 0.42, -0.85))
	_add_background_orb(Vector3(-0.82, 1.42, -0.74), 0.105, Color("#ffe2b8"))
	_add_background_orb(Vector3(0.84, 1.23, -0.72), 0.085, Color("#f7c9df"))
	_add_background_orb(Vector3(-0.90, 0.82, -0.70), 0.065, Color("#e6e0ff"))
	_add_background_orb(Vector3(0.87, 0.75, -0.71), 0.11, Color("#f6e7bd"))


func _add_backdrop_disc(radius: float, color: Color, at: Vector3) -> void:
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.012
	cylinder.radial_segments = 48
	disc.mesh = cylinder
	disc.position = at
	disc.rotation.x = PI * 0.5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	disc.material_override = material
	add_child(disc)


func _add_background_orb(at: Vector3, radius: float, color: Color) -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 8
	orb.mesh = sphere
	orb.position = at
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	orb.material_override = material
	add_child(orb)


func _build_audio() -> void:
	_sfx_bus_index = _ensure_audio_bus("SFX")
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "BackgroundMusic"
	_music_player.bus = "Master"
	_music_player.autoplay = true
	var music_stream: AudioStreamWAV = BGM_STREAM.duplicate()
	music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music_stream.loop_begin = 0
	# Runtime WAV streams default loop_end to 0, which creates an empty loop.
	# Use the last valid sample so the complete 18-second track repeats.
	music_stream.loop_end = maxi(1, int(round(music_stream.get_length() * music_stream.mix_rate)) - 1)
	_music_player.stream = music_stream
	add_child(_music_player)
	_music_player.play()
	_laugh_player = AudioStreamPlayer.new()
	_laugh_player.name = "CharacterLaugh"
	_laugh_player.stream = LAUGH_STREAM
	_laugh_player.bus = "SFX"
	add_child(_laugh_player)


func _ensure_audio_bus(bus_name: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	return index


func _load_audio_settings() -> Dictionary:
	var config := ConfigFile.new()
	var load_error := config.load(AUDIO_SETTINGS_PATH)
	if load_error != OK:
		return {"music_percent": DEFAULT_MUSIC_PERCENT, "sfx_percent": 65.0}
	var music_percent := clampf(float(config.get_value("audio", "music_percent", DEFAULT_MUSIC_PERCENT)), 0.0, 100.0)
	var settings_version := int(config.get_value("audio", "settings_version", 0))
	if settings_version < AUDIO_SETTINGS_VERSION:
		music_percent = minf(music_percent, DEFAULT_MUSIC_PERCENT)
		config.set_value("audio", "music_percent", music_percent)
		config.set_value("audio", "settings_version", AUDIO_SETTINGS_VERSION)
		var migration_error := config.save(AUDIO_SETTINGS_PATH)
		if migration_error != OK:
			push_warning("无法更新声音设置：%s" % error_string(migration_error))
	return {
		"music_percent": music_percent,
		"sfx_percent": clampf(float(config.get_value("audio", "sfx_percent", 65.0)), 0.0, 100.0),
	}


func _on_audio_settings_changed(music_percent: float, sfx_percent: float) -> void:
	_apply_audio_settings(music_percent, sfx_percent)


func _on_audio_preview_changed(music_percent: float, sfx_percent: float) -> void:
	_apply_audio_settings(music_percent, sfx_percent, false)


func _apply_audio_settings(music_percent: float, sfx_percent: float, save_settings: bool = true) -> void:
	_set_player_volume(_music_player, music_percent)
	_set_bus_volume(_sfx_bus_index, sfx_percent)
	if not save_settings:
		return
	var config := ConfigFile.new()
	config.set_value("audio", "music_percent", clampf(music_percent, 0.0, 100.0))
	config.set_value("audio", "sfx_percent", clampf(sfx_percent, 0.0, 100.0))
	config.set_value("audio", "settings_version", AUDIO_SETTINGS_VERSION)
	var save_error := config.save(AUDIO_SETTINGS_PATH)
	if save_error != OK:
		push_warning("无法保存声音设置：%s" % error_string(save_error))


func _set_bus_volume(index: int, percent: float) -> void:
	if index < 0:
		return
	var normalized := clampf(percent, 0.0, 100.0) / 100.0
	AudioServer.set_bus_mute(index, normalized <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(normalized, 0.001)))


func _set_player_volume(player: AudioStreamPlayer, percent: float) -> void:
	if player == null:
		return
	var normalized := clampf(percent, 0.0, 100.0) / 100.0
	player.volume_db = linear_to_db(maxf(normalized, 0.001))


func _ensure_background_music() -> void:
	if _music_player != null and not _music_player.playing:
		_music_player.play()


func _make_stage_disc(radius: float, height: float, color: Color) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 64
	disc.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.roughness = 0.78
	disc.material_override = material
	return disc


func _on_pet_state_changed(snapshot: Dictionary) -> void:
	_hud.set_pet_state(snapshot)
	if bool(snapshot.get("resting", false)) != _resting:
		_resting = bool(snapshot.get("resting", false))
		_character.set_resting(_resting)
		_hud.set_resting(_resting)


func _on_game_state_changed(_snapshot: Dictionary) -> void:
	if _game_services.ready_ok:
		var pending: int = _game_services.mailbox.pending_count()
		var unread: int = _game_services.mailbox.unread_count()
		_hud.set_mail_badges(pending, unread)
		_feature_overlay.set_mail_badges(pending, unread)


func _on_trip_mail_arrived(count: int, _trip_id: String) -> void:
	if _hud != null:
		_hud.show_hint("西小电寄回了 %d 份旅行来信，收件箱有新消息。" % count)
	if _feature_overlay != null and _feature_overlay.visible:
		_feature_overlay.show_hint("新来信到啦：%d 封。" % count)


func _on_voice_state_changed(state: String, message: String) -> void:
	_hud.set_voice_status(message, state)
	match state:
		"listening":
			_character.set_state("listening")
		"repeating":
			_character.set_state("repeating")
		"armed", "cooldown":
			if not _resting:
				_character.set_state("listening")
		"off", "permission_pending", "permission_denied", "input_unavailable":
			if not _resting and _character.get_state() in ["listening", "repeating"]:
				_character.set_state("idle")


func _on_echo_finished(_duration_seconds: float) -> void:
	if _resting:
		_pet_state.set_resting(false)
		_resting = false
	var result: Dictionary = _pet_state.reward_echo()
	_character.celebrate()
	var stars_gained := int(result.get("actual_changes", {}).get("stars", 0))
	if stars_gained > 0:
		_hud.show_hint("模仿完成！获得 ✦ %d。" % stars_gained)


func _on_pet_requested(region: String) -> void:
	if _resting:
		_hud.show_hint("西小电在休息，按休息键叫醒它上早八。")
		return
	if _voice.current_state in ["listening", "repeating"]:
		_hud.show_hint("先听完这句话，再摸摸西小电吧。")
		return
	_pet_state.pet()
	match region:
		"body":
			_character.play_laugh()
			_play_laugh_sound()
			_hud.show_hint("哈哈哈！西小电捧着肚子大笑了起来。")
		"feet":
			_character.play_tickled()
			_play_laugh_sound()
			_hud.show_hint("哇袄")
		_:
			_character.tap()
			_hud.show_hint("摸摸头")


func _play_laugh_sound() -> void:
	if _laugh_player == null:
		_character.finish_feedback_animation()
		return
	if _laugh_player.playing:
		return
	_laugh_voice_token = _voice.acquire_suspend("character_feedback")
	_laugh_player.volume_db = 0.0
	_laugh_player.play()
	var sound_duration := maxf(0.1, _laugh_player.stream.get_length())
	var fade_duration := minf(0.12, sound_duration * 0.12)
	await get_tree().create_timer(maxf(0.0, sound_duration - fade_duration)).timeout
	if not is_instance_valid(_laugh_player):
		return
	if _laugh_player.playing:
		var fade := create_tween()
		fade.tween_property(_laugh_player, "volume_db", -32.0, fade_duration)
		await fade.finished
		_laugh_player.stop()
		_laugh_player.volume_db = 0.0
	if is_instance_valid(_character):
		_character.finish_feedback_animation()
	if not _laugh_voice_token.is_empty():
		_voice.release_suspend(_laugh_voice_token)
		_laugh_voice_token = ""


func _on_play_requested() -> void:
	if _resting:
		_hud.show_hint("先叫醒西小电再一起玩吧。")
		return
	if _minigame != null:
		return
	if _voice.current_state in ["listening", "repeating"]:
		_hud.show_hint("先听完这句话，再开始冲刺吧。")
		return
	if not _pet_state.start_minigame():
		_hud.show_hint("西小电累似了，休息一会儿再来。")
		return
	_minigame_voice_token = _voice.acquire_suspend("minigame")
	_minigame_run_id = "runner:%d:%d" % [Time.get_ticks_usec(), randi()]
	_minigame = MINIGAME_SCRIPT.new()
	_minigame.name = "EndlessRunner"
	_minigame.finished.connect(_on_minigame_finished)
	_canvas.add_child(_minigame)


func _on_minigame_finished(score: int, reward_stars: int, completed: bool) -> void:
	_minigame = null
	if not _minigame_voice_token.is_empty():
		_voice.release_suspend(_minigame_voice_token)
		_minigame_voice_token = ""
	if not completed:
		_hud.show_hint("这次冲刺没有结算奖励，下次再来挑战吧。")
		return
	var result: Dictionary = _pet_state.complete_minigame(reward_stars, _minigame_run_id)
	_character.celebrate()
	if not bool(result.get("ok", false)):
		_hud.show_hint(str(result.get("message", "这次奖励暂时没有保存成功。")))
		return
	var actual_stars := int(result.get("actual_changes", {}).get("stars", 0))
	if actual_stars > 0:
		_hud.show_hint("冲刺得分 %d，获得 ✦ %d！" % [score, actual_stars])
	else:
		_hud.show_hint("冲刺得分 %d，今日有奖次数已用完。" % score)


func _on_rest_requested() -> void:
	var next_resting := not _resting
	var result: Dictionary = _pet_state.set_resting(next_resting)
	if not bool(result.get("ok", false)):
		_hud.show_hint(str(result.get("message", "状态暂时无法保存。")))
		return
	_resting = next_resting
	_character.set_resting(_resting)
	_hud.set_resting(_resting)
	_hud.show_hint("西小电睡着啦，电量会慢慢恢复。" if _resting else "西小电醒来啦！")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if _voice != null and _background_voice_token.is_empty():
			_background_voice_token = _voice.acquire_suspend("app_background")
		if _game_services != null:
			_game_services.on_application_paused()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _game_services != null:
			_game_services.on_application_resumed()
		if _voice != null and not _background_voice_token.is_empty():
			_voice.release_suspend(_background_voice_token)
			_background_voice_token = ""
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _game_services != null:
			_game_services.flush()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _feature_overlay != null and _feature_overlay.handle_back():
			return
		if _game_services != null:
			_game_services.flush()
		get_tree().quit()


func _on_feature_open_requested(page: String) -> void:
	if not _game_services.ready_ok:
		_hud.show_hint(_game_services.startup_error)
		return
	if _feature_overlay == null:
		return
	if _feature_voice_token.is_empty():
		_feature_voice_token = _voice.acquire_suspend("overlay")
	_feature_overlay.open(page)


func _on_feature_overlay_closed() -> void:
	if not _feature_voice_token.is_empty():
		_voice.release_suspend(_feature_voice_token)
		_feature_voice_token = ""


func _on_feature_command(kind: String, arguments: Dictionary) -> void:
	if not _game_services.ready_ok:
		_feature_overlay.show_command_result({"ok": false, "message": _game_services.startup_error})
		return
	var request_id := str(arguments.get("request_id", "%s:%d:%d" % [kind, Time.get_ticks_usec(), randi()]))
	var result: Dictionary = {}
	match kind:
		"buy":
			result = _game_services.shop.buy(str(arguments.get("item_id", "")), arguments.get("quantity", 1), int(arguments.get("catalog_version", -1)), request_id)
		"use":
			result = _game_services.inventory.use_item(str(arguments.get("item_id", "")), request_id, _resting)
		"free_feed":
			if _resting:
				result = {"ok": false, "code": "CHARACTER_RESTING", "message": "先叫醒西小电再喂食吧。"}
			elif _pet_state.feed():
				result = _pet_state.last_result()
				_character.celebrate()
			else:
				result = _pet_state.last_result()
				if result.is_empty() or bool(result.get("ok", false)):
					result = {"ok": false, "message": "西小电刚吃过，等一会儿再来。"}
		"tutorial":
			result = _game_services.travel.begin_tutorial(request_id)
		"depart":
			result = _game_services.travel.depart(str(arguments.get("route_id", "nearby")), str(arguments.get("supply_item_id", "")), request_id)
		"ack_return":
			result = _game_services.travel.acknowledge_return(request_id)
		"mark_read":
			result = _game_services.mailbox.mark_read(str(arguments.get("mail_id", "")), request_id)
		"claim":
			result = _game_services.mailbox.claim(str(arguments.get("mail_id", "")), request_id)
		"claim_all":
			result = _game_services.mailbox.claim_all(request_id)
	var message := _feature_result_message(kind, result, arguments)
	_feature_overlay.show_command_result(result, message)


func _feature_result_message(kind: String, result: Dictionary, arguments: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return str(result.get("message", "操作没有完成，请刷新后重试。"))
	match kind:
		"buy":
			var item: Dictionary = _game_services.catalog.get_item(str(arguments.get("item_id", "")))
			var actual: Dictionary = result.get("actual_changes", {})
			return "已购买%s ×%d，花费 ✦ %d。" % [str(item.get("name", "道具")), int(actual.get("quantity", 1)), absi(int(actual.get("stars", 0)))]
		"use":
			var item: Dictionary = _game_services.catalog.get_item(str(arguments.get("item_id", "")))
			return "使用了%s，效果已加入西小电状态。" % str(item.get("name", "道具"))
		"free_feed":
			return "基础喂食成功，不消耗背包道具。"
		"tutorial":
			return "快速引导旅程出发啦！几分钟后记得看看名片。"
		"depart":
			return "出发计划已保存，西小电这就启程。"
		"ack_return":
			return "行李收好啦，随时可以安排下一趟。"
		"claim", "claim_all":
			var claim_actual: Dictionary = result.get("actual_changes", {})
			return "附件已收下：✦ %d，亲密经验 +%d。" % [int(claim_actual.get("stars", 0)), int(claim_actual.get("friendship_xp", 0))]
		"mark_read":
			return "信件已打开，附件需要单独收下。"
	return "操作完成。"
