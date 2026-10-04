extends Control

signal finished(score: int, reward_stars: int, completed: bool)

const DESIGN_SIZE := Vector2(720.0, 1280.0)
const BEST_SCORE_PATH := "user://runner_best.cfg"
const START_SPEED := 300.0
const MAX_SPEED := 520.0
const GRAVITY := 1700.0
const JUMP_SPEED := 650.0
const PLAYER_X := 96.0

class RunnerField extends Control:
	var ground_y := 296.0
	var scroll_offset := 0.0
	var player_x := 96.0
	var jump_height := 0.0

	func _draw() -> void:
		var w := size.x
		draw_rect(Rect2(Vector2.ZERO, size), Color("#dcf3ff"))
		draw_circle(Vector2(w - 72.0, 62.0), 25.0, Color("#ffe6a8"))

		var cloud_shift := fposmod(scroll_offset * 0.12, w + 190.0)
		for cloud_index in range(3):
			var cloud_x := fposmod(float(cloud_index) * 235.0 - cloud_shift, w + 100.0) - 30.0
			var cloud_y := 70.0 + float(cloud_index % 2) * 48.0
			draw_circle(Vector2(cloud_x, cloud_y), 15.0, Color("#ffffff"))
			draw_circle(Vector2(cloud_x + 17.0, cloud_y - 8.0), 19.0, Color("#ffffff"))
			draw_circle(Vector2(cloud_x + 37.0, cloud_y), 14.0, Color("#ffffff"))

		var hill_shift := fposmod(scroll_offset * 0.20, 210.0)
		for hill_index in range(5):
			var hill_x := float(hill_index) * 210.0 - hill_shift
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(hill_x - 110.0, ground_y + 4.0),
					Vector2(hill_x + 10.0, ground_y - 70.0),
					Vector2(hill_x + 120.0, ground_y + 4.0),
				]),
				Color("#b8dfd1") if hill_index % 2 == 0 else Color("#c8e9dc")
			)

		draw_rect(Rect2(0.0, ground_y, w, size.y - ground_y), Color("#f7e7ce"))
		draw_line(Vector2(0.0, ground_y), Vector2(w, ground_y), Color("#86bd9e"), 5.0, true)
		draw_line(Vector2(0.0, ground_y + 7.0), Vector2(w, ground_y + 7.0), Color("#ffffff"), 2.0, true)

		var dash_shift := fposmod(scroll_offset, 68.0)
		for dash_index in range(11):
			var dash_x := float(dash_index) * 68.0 - dash_shift
			draw_line(Vector2(dash_x, ground_y + 36.0), Vector2(dash_x + 25.0, ground_y + 36.0), Color("#d5c3a7"), 4.0, true)

		var shadow_width := lerpf(28.0, 18.0, clampf(jump_height / 145.0, 0.0, 1.0))
		var shadow_center := Vector2(player_x + 38.0, ground_y + 1.0)
		draw_colored_polygon(
			PackedVector2Array([
				shadow_center + Vector2(-shadow_width, 0.0),
				shadow_center + Vector2(-shadow_width * 0.5, -5.0),
				shadow_center + Vector2(shadow_width * 0.5, -5.0),
				shadow_center + Vector2(shadow_width, 0.0),
			]),
			Color(0.35, 0.43, 0.50, 0.16)
		)


class RunnerCharacter extends Control:
	var phase := 0.0
	var airborne := false
	var _body_style := StyleBoxFlat.new()
	var _face_style := StyleBoxFlat.new()

	func _init() -> void:
		_body_style.bg_color = Color("#fffaf2")
		_body_style.set_corner_radius_all(19)
		_body_style.border_color = Color("#e5d9d6")
		_body_style.set_border_width_all(2)
		_face_style.bg_color = Color("#71dded")
		_face_style.set_corner_radius_all(13)

	func _draw() -> void:
		var stride := sin(phase * 13.0) * 13.0 if not airborne else 5.0
		var leg_y := 79.0
		draw_line(Vector2(30.0, leg_y), Vector2(25.0 - stride, 94.0), Color("#fffaf2"), 8.0, true)
		draw_line(Vector2(48.0, leg_y), Vector2(51.0 + stride, 94.0), Color("#fffaf2"), 8.0, true)
		draw_line(Vector2(25.0 - stride, 94.0), Vector2(34.0 - stride, 94.0), Color("#df788b"), 5.0, true)
		draw_line(Vector2(51.0 + stride, 94.0), Vector2(60.0 + stride, 94.0), Color("#df788b"), 5.0, true)

		var arm_swing := sin(phase * 13.0 + PI) * 10.0 if not airborne else -5.0
		draw_line(Vector2(19.0, 54.0), Vector2(8.0 + arm_swing, 68.0), Color("#fffaf2"), 7.0, true)
		draw_line(Vector2(59.0, 54.0), Vector2(70.0 - arm_swing, 68.0), Color("#fffaf2"), 7.0, true)

		draw_style_box(_body_style, Rect2(19.0, 48.0, 40.0, 38.0))
		draw_circle(Vector2(39.0, 30.0), 27.0, Color("#fffaf2"))
		draw_circle(Vector2(13.0, 28.0), 8.0, Color("#f17e9b"))
		draw_circle(Vector2(65.0, 28.0), 8.0, Color("#f17e9b"))
		draw_style_box(_face_style, Rect2(20.0, 18.0, 38.0, 27.0))
		draw_circle(Vector2(31.0, 30.0), 3.6, Color("#283149"))
		draw_circle(Vector2(47.0, 30.0), 3.6, Color("#283149"))
		draw_circle(Vector2(39.0, 38.0), 3.2, Color("#e8798d"))
		draw_circle(Vector2(39.0, 66.0), 4.5, Color("#f2c769"))


class RunnerObstacle extends Control:
	var kind := 0

	func _draw() -> void:
		var body := StyleBoxFlat.new()
		body.bg_color = Color("#ef8890") if kind == 0 else Color("#8178d5")
		body.set_corner_radius_all(9)
		body.border_color = Color("#ffffff")
		body.set_border_width_all(2)
		draw_style_box(body, Rect2(3.0, 11.0, size.x - 6.0, size.y - 11.0))
		draw_rect(Rect2(size.x * 0.36, 1.0, size.x * 0.28, 13.0), Color("#f7c76b"))
		if kind == 0:
			draw_line(Vector2(size.x * 0.28, size.y * 0.52), Vector2(size.x * 0.72, size.y * 0.52), Color("#fff5d9"), 4.0, true)
		else:
			draw_circle(Vector2(size.x * 0.5, size.y * 0.56), 5.0, Color("#dbf7ff"))


class RunnerPickup extends Control:
	var kind := 0
	var phase := 0.0

	func _process(delta: float) -> void:
		phase += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := sin(phase * 5.0) * 2.0
		if kind == 0:
			draw_circle(Vector2(20.0, 20.0), 18.0 + pulse, Color(1.0, 0.80, 0.43, 0.25))
			var points := PackedVector2Array()
			for point_index in range(10):
				var angle := -PI * 0.5 + float(point_index) * PI / 5.0
				var radius := 15.0 if point_index % 2 == 0 else 7.0
				points.append(Vector2(20.0, 20.0) + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(points, Color("#ffc95e"))
			draw_circle(Vector2(20.0, 20.0), 4.0, Color("#fff7dc"))
		else:
			var battery := StyleBoxFlat.new()
			battery.bg_color = Color("#7bd6b3")
			battery.set_corner_radius_all(6)
			battery.border_color = Color("#ffffff")
			battery.set_border_width_all(2)
			draw_circle(Vector2(20.0, 20.0), 19.0 + pulse, Color(0.43, 0.83, 0.68, 0.20))
			draw_style_box(battery, Rect2(7.0, 6.0, 26.0, 28.0))
			draw_rect(Rect2(15.0, 3.0, 10.0, 5.0), Color("#67bd9c"))
			draw_colored_polygon(
				PackedVector2Array([Vector2(22.0, 10.0), Vector2(15.0, 21.0), Vector2(20.0, 21.0), Vector2(17.0, 29.0), Vector2(27.0, 17.0), Vector2(22.0, 17.0)]),
				Color("#fff8da")
			)


var _design: Control
var _score_label: Label
var _best_label: Label
var _pickup_label: Label
var _playfield: Control
var _field: RunnerField
var _runner: RunnerCharacter
var _exit_button: Button
var _jump_button: Button
var _obstacles: Array[Control] = []
var _pickups: Array[Control] = []
var _state_overlay: Control
var _rng := RandomNumberGenerator.new()
var _elapsed := 0.0
var _distance := 0.0
var _score := 0
var _best_score := 0
var _collected_stars := 0
var _collected_cells := 0
var _speed := START_SPEED
var _obstacle_timer := 1.35
var _pickup_timer := 0.85
var _jump_height := 0.0
var _jump_velocity := 0.0
var _game_over := false
var _finished := false


func _ready() -> void:
	_rng.randomize()
	_best_score = _load_best_score()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_design = Control.new()
	_design.size = DESIGN_SIZE
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_design)
	_build_ui()
	_reset_run()
	_fit_design()
	get_viewport().size_changed.connect(_fit_design)


func _build_ui() -> void:
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.06, 0.08, 0.16, 0.82)
	dimmer.size = DESIGN_SIZE
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_design.add_child(dimmer)
	_add_panel(Rect2(24.0, 278.0, 672.0, 724.0))
	_add_label("步道乐跑", Rect2(50.0, 299.0, 390.0, 46.0), 30, Color("#29283d"))
	_add_label("躲开障碍，收集绩点星和半步电台能量电池", Rect2(52.0, 346.0, 510.0, 30.0), 16, Color("#77778d"))
	_exit_button = _make_button("退出", Rect2(574.0, 300.0, 98.0, 44.0), Color("#eeeafa"), Color("#37334e"), 16)
	_exit_button.pressed.connect(func() -> void: _finish(false))
	_score_label = _add_label("得分  0000", Rect2(52.0, 382.0, 190.0, 34.0), 19, Color("#554aa5"))
	_best_label = _add_label("最佳  0000", Rect2(264.0, 382.0, 190.0, 34.0), 17, Color("#74738a"), HORIZONTAL_ALIGNMENT_CENTER)
	_pickup_label = _add_label("绩点 0  ·  电池 0", Rect2(472.0, 382.0, 196.0, 34.0), 16, Color("#a8732b"), HORIZONTAL_ALIGNMENT_RIGHT)

	var field_style := PanelContainer.new()
	field_style.position = Vector2(48.0, 431.0)
	field_style.size = Vector2(624.0, 384.0)
	field_style.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#eaf6ff")
	style.set_corner_radius_all(22)
	style.border_color = Color("#ffffff")
	style.set_border_width_all(2)
	field_style.add_theme_stylebox_override("panel", style)
	_design.add_child(field_style)

	_playfield = Control.new()
	_playfield.position = field_style.position + Vector2(8.0, 8.0)
	_playfield.size = field_style.size - Vector2(16.0, 16.0)
	_playfield.clip_contents = true
	_playfield.mouse_filter = Control.MOUSE_FILTER_STOP
	_playfield.gui_input.connect(_on_playfield_input)
	_design.add_child(_playfield)
	_field = RunnerField.new()
	_field.size = _playfield.size
	_field.ground_y = _field.size.y - 68.0
	_field.clip_contents = true
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playfield.add_child(_field)
	_runner = RunnerCharacter.new()
	_runner.name = "XixiaodianRunner"
	_runner.size = Vector2(78.0, 100.0)
	_runner.position = Vector2(PLAYER_X, _field.ground_y - _runner.size.y)
	_runner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playfield.add_child(_runner)

	_add_label("点击跑道或按跳跃，越过障碍收集道具", Rect2(55.0, 825.0, 610.0, 30.0), 15, Color("#77778d"), HORIZONTAL_ALIGNMENT_CENTER)
	_jump_button = _make_button("跳  跃", Rect2(208.0, 866.0, 304.0, 72.0), Color("#766be0"), Color("#fffaf2"), 22)
	_jump_button.pressed.connect(_jump)
	_add_label("碰到水雷就会结束本局；分数越高，回家奖励越多。", Rect2(58.0, 947.0, 604.0, 28.0), 14, Color("#8a8797"), HORIZONTAL_ALIGNMENT_CENTER)


func _process(delta: float) -> void:
	if _game_over or _finished:
		return
	_elapsed += delta
	_distance += _speed * delta
	_speed = minf(MAX_SPEED, START_SPEED + _elapsed * 5.0)
	_obstacle_timer -= delta
	_pickup_timer -= delta
	if _obstacle_timer <= 0.0:
		_spawn_obstacle()
		_obstacle_timer = _rng.randf_range(1.25, 1.65)
	if _pickup_timer <= 0.0:
		_spawn_pickup()
		_pickup_timer = _rng.randf_range(1.35, 2.05)

	if _jump_height > 0.0 or _jump_velocity > 0.0:
		_jump_velocity -= GRAVITY * delta
		_jump_height += _jump_velocity * delta
		if _jump_height <= 0.0:
			_jump_height = 0.0
			_jump_velocity = 0.0
	_runner.position.y = _field.ground_y - _runner.size.y - _jump_height
	_runner.phase = _elapsed
	_runner.airborne = _jump_height > 0.0
	_runner.queue_redraw()
	_field.scroll_offset = _distance
	_field.jump_height = _jump_height
	_field.queue_redraw()

	if _advance_objects(delta):
		return
	_score = int(_distance / 10.0) + _collected_stars * 25 + _collected_cells * 60
	_update_hud()


func _advance_objects(delta: float) -> bool:
	for index in range(_obstacles.size() - 1, -1, -1):
		var obstacle := _obstacles[index]
		obstacle.position.x -= _speed * delta
		if obstacle.position.x + obstacle.size.x < -8.0:
			obstacle.queue_free()
			_obstacles.remove_at(index)
			continue
		var player_rect := Rect2(_runner.position + Vector2(16.0, 22.0), Vector2(46.0, 65.0))
		var obstacle_rect := Rect2(obstacle.position + Vector2(4.0, 10.0), obstacle.size - Vector2(8.0, 10.0))
		if player_rect.intersects(obstacle_rect):
			_end_run()
			return true

	for index in range(_pickups.size() - 1, -1, -1):
		var pickup := _pickups[index]
		pickup.position.x -= _speed * delta
		if pickup.position.x + pickup.size.x < -8.0:
			pickup.queue_free()
			_pickups.remove_at(index)
			continue
		var player_rect := Rect2(_runner.position + Vector2(10.0, 14.0), Vector2(58.0, 78.0))
		var pickup_rect := Rect2(pickup.position + Vector2(4.0, 4.0), pickup.size - Vector2(8.0, 8.0))
		if player_rect.intersects(pickup_rect):
			if int(pickup.get_meta("kind", 0)) == 0:
				_collected_stars += 1
			else:
				_collected_cells += 1
			pickup.queue_free()
			_pickups.remove_at(index)
	return false


func _spawn_obstacle() -> void:
	var obstacle := RunnerObstacle.new()
	obstacle.kind = _rng.randi_range(0, 1)
	obstacle.size = Vector2(_rng.randf_range(34.0, 48.0), _rng.randf_range(42.0, 72.0))
	obstacle.position = Vector2(_field.size.x + 16.0, _field.ground_y - obstacle.size.y)
	obstacle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playfield.add_child(obstacle)
	_obstacles.append(obstacle)


func _spawn_pickup() -> void:
	var pickup := RunnerPickup.new()
	var kind := 1 if _rng.randf() < 0.22 else 0
	pickup.set_meta("kind", kind)
	pickup.kind = kind
	pickup.size = Vector2(40.0, 40.0)
	pickup.position = Vector2(
		_field.size.x + 18.0,
		_field.ground_y - _rng.randf_range(76.0, 166.0)
	)
	pickup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playfield.add_child(pickup)
	_pickups.append(pickup)


func _jump() -> void:
	if _game_over or _finished or _jump_height > 0.0:
		return
	_jump_velocity = JUMP_SPEED


func _on_playfield_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_jump()
		_playfield.accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_jump()
		_playfield.accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_UP, KEY_W]:
			_jump()
			get_viewport().set_input_as_handled()


func _end_run() -> void:
	if _game_over or _finished:
		return
	_game_over = true
	_exit_button.visible = false
	_score = int(_distance / 10.0) + _collected_stars * 25 + _collected_cells * 60
	if _score > _best_score:
		_best_score = _score
		_save_best_score()
	_update_hud()
	_show_result_overlay()


func _show_result_overlay() -> void:
	_state_overlay = Control.new()
	_state_overlay.size = _playfield.size
	_state_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_state_overlay.z_index = 10
	_playfield.add_child(_state_overlay)
	var dimmer := ColorRect.new()
	dimmer.size = _state_overlay.size
	dimmer.color = Color(0.15, 0.17, 0.28, 0.68)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_state_overlay.add_child(dimmer)
	var panel := PanelContainer.new()
	panel.position = Vector2(38.0, 82.0)
	panel.size = Vector2(_state_overlay.size.x - 76.0, 190.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#fffaf2")
	panel_style.set_corner_radius_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	_state_overlay.add_child(panel)
	_add_label("冲刺结束", Rect2(55.0, 98.0, _state_overlay.size.x - 110.0, 36.0), 26, Color("#29283d"), HORIZONTAL_ALIGNMENT_CENTER, _state_overlay)
	_add_label("得分 %d  ·  绩点 %d  ·  电池 %d" % [_score, _collected_stars, _collected_cells], Rect2(55.0, 139.0, _state_overlay.size.x - 110.0, 30.0), 16, Color("#77778d"), HORIZONTAL_ALIGNMENT_CENTER, _state_overlay)
	var reward := clampi(1 + int(floor(float(_score) / 300.0)), 1, 5)
	_add_label("回家可领取 %d 绩点" % reward, Rect2(55.0, 170.0, _state_overlay.size.x - 110.0, 28.0), 17, Color("#a8732b"), HORIZONTAL_ALIGNMENT_CENTER, _state_overlay)
	var restart_button := _make_button("再跑一局", Rect2(58.0, 218.0, 220.0, 52.0), Color("#e9e7f8"), Color("#37334e"), 16, _state_overlay)
	restart_button.pressed.connect(_reset_run)
	var home_button := _make_button("回家领奖", Rect2(310.0, 218.0, 220.0, 52.0), Color("#766be0"), Color("#fffaf2"), 16, _state_overlay)
	home_button.pressed.connect(func() -> void: _finish(true))


func _reset_run() -> void:
	for obstacle in _obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	_obstacles.clear()
	for pickup in _pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	_pickups.clear()
	if is_instance_valid(_state_overlay):
		_state_overlay.queue_free()
	_state_overlay = null
	_elapsed = 0.0
	_distance = 0.0
	_score = 0
	_collected_stars = 0
	_collected_cells = 0
	_speed = START_SPEED
	_obstacle_timer = 1.35
	_pickup_timer = 0.85
	_jump_height = 0.0
	_jump_velocity = 0.0
	_game_over = false
	if _exit_button != null:
		_exit_button.visible = true
	if _runner != null:
		_runner.position = Vector2(PLAYER_X, _field.ground_y - _runner.size.y)
		_runner.phase = 0.0
		_runner.airborne = false
		_runner.queue_redraw()
	if _field != null:
		_field.scroll_offset = 0.0
		_field.jump_height = 0.0
		_field.queue_redraw()
	_update_hud()


func _finish(completed: bool) -> void:
	if _finished:
		return
	_finished = true
	var reward := clampi(1 + int(floor(float(_score) / 300.0)), 1, 5) if completed else 0
	finished.emit(_score, reward, completed)
	queue_free()


func _update_hud() -> void:
	if _score_label != null:
		_score_label.text = "得分  %04d  ·  %dm" % [_score, int(_distance / 100.0)]
	if _best_label != null:
		_best_label.text = "最佳  %04d" % _best_score
	if _pickup_label != null:
		_pickup_label.text = "電星 %d  ·  電池 %d" % [_collected_stars, _collected_cells]
	if _jump_button != null:
		_jump_button.disabled = _game_over


func _load_best_score() -> int:
	var config := ConfigFile.new()
	if config.load(BEST_SCORE_PATH) != OK:
		return 0
	return maxi(0, int(config.get_value("runner", "best_score", 0)))


func _save_best_score() -> void:
	var config := ConfigFile.new()
	config.set_value("runner", "best_score", _best_score)
	var save_error := config.save(BEST_SCORE_PATH)
	if save_error != OK:
		push_warning("无法保存跑酷最佳分数：%s" % error_string(save_error))


func _add_panel(rect: Rect2) -> void:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fffaf1")
	style.set_corner_radius_all(30)
	style.shadow_color = Color(0.02, 0.02, 0.08, 0.25)
	style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", style)
	_design.add_child(panel)


func _add_label(
	text_value: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	parent: Control = null
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var target: Control = parent if parent != null else _design
	target.add_child(label)
	return label


func _make_button(
	text_value: String,
	rect: Rect2,
	color: Color,
	font_color: Color,
	font_size: int,
	parent: Control = null
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(20)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var target: Control = parent if parent != null else _design
	target.add_child(button)
	return button


func _fit_design() -> void:
	if _design == null:
		return
	var viewport_size := get_viewport_rect().size
	var fit_scale := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	fit_scale = maxf(0.5, fit_scale)
	_design.scale = Vector2.ONE * fit_scale
	_design.position = (viewport_size - DESIGN_SIZE * fit_scale) * 0.5
