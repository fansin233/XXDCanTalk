extends Control

signal auto_listen_toggled(enabled: bool)
signal hold_started
signal hold_released
signal touch_requested(region: String)
signal play_requested
signal rest_requested
signal feature_open_requested(page: String)

const DESIGN_SIZE := Vector2(720.0, 1280.0)
const SAFE_LAYOUT = preload("res://Scripts/UI/SafeAreaLayout.gd")
const FLAT_ICON = preload("res://Scripts/UI/FlatIcon.gd")
const INK := Color("#29283c")
const MUTED := Color("#68667a")
const CREAM := Color("#fffaf2")
const LAVENDER := Color("#7060c9")
const LAVENDER_TINT := Color("#eeeaf8")
const SURFACE := Color("#fffaf2")

var _design: Control
var _top_bar: PanelContainer
var _profile_label: Label
var _level_label: Label
var _star_button: Button
var _stat_labels: Dictionary = {}
var _stat_bars: Dictionary = {}
var _hint_panel: PanelContainer
var _hint_label: Label
var _hint_tween: Tween
var _auto_button: Button
var _hold_button: Button
var _level_meter: ProgressBar
var _status_label: Label
var _rest_button: Button
var _touch_zone: Control
var _main_dock: Control
var _feature_rail: Control
var _rail_buttons: Dictionary = {}
var _rail_badge: Label
var _rail_badge_panel: PanelContainer
var _safe_rect := Rect2(Vector2.ZERO, DESIGN_SIZE)
var _design_height := DESIGN_SIZE.y
var _resting := false
var _auto_enabled := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design = Control.new()
	_design.name = "ResponsiveDesignRoot"
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_design)
	_build()
	_fit_design()
	get_viewport().size_changed.connect(_fit_design)


func set_voice_status(message: String, state: String) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	var is_listening := state == "listening"
	_status_label.add_theme_color_override("font_color", Color("#985b19") if is_listening else MUTED)
	if _hold_button != null:
		_hold_button.text = "听见你说…" if is_listening else "按住说话"
		_hold_button.add_theme_stylebox_override(
			"normal", _button_style(Color("#c58a3d") if is_listening else LAVENDER, 18)
		)
		_hold_button.add_theme_color_override("font_color", CREAM)


func set_audio_level(level: float) -> void:
	if _level_meter != null:
		_level_meter.value = clampf(level, 0.0, 1.0) * 100.0


func set_auto_enabled(enabled: bool) -> void:
	_auto_enabled = enabled
	if _auto_button == null:
		return
	_auto_button.set_pressed_no_signal(enabled)
	_auto_button.text = "自动聆听　·　已开启" if enabled else "自动聆听　·　已关闭"
	_auto_button.add_theme_stylebox_override(
		"normal", _button_style(LAVENDER_TINT if not enabled else Color("#e3def7"), 16)
	)
	_auto_button.add_theme_color_override("font_color", INK)


func set_pet_state(snapshot: Dictionary) -> void:
	if _profile_label == null:
		return
	_profile_label.text = "西小电"
	_level_label.text = "Lv.%d" % int(snapshot.get("level", 1))
	_star_button.text = "✦  %d" % int(snapshot.get("stars", 0))
	_set_stat("饱腹", float(snapshot.get("hunger", 0.0)))
	_set_stat("电量", float(snapshot.get("energy", 0.0)))
	_set_stat("心情", float(snapshot.get("mood", 0.0)))
	_resting = bool(snapshot.get("resting", false))
	_update_rest_button()


func set_resting(resting: bool) -> void:
	_resting = resting
	_update_rest_button()


func show_hint(message: String) -> void:
	if _hint_label == null or _hint_panel == null:
		return
	if _hint_tween != null and _hint_tween.is_running():
		_hint_tween.kill()
	_hint_label.text = message
	_hint_panel.visible = true
	_hint_panel.modulate.a = 1.0
	_hint_tween = create_tween()
	_hint_tween.tween_interval(2.5)
	_hint_tween.tween_property(_hint_panel, "modulate:a", 0.0, 0.2)
	_hint_tween.tween_callback(func() -> void:
		if is_instance_valid(_hint_panel):
			_hint_panel.visible = false
		)


func set_mail_badges(pending_count: int, unread_count: int) -> void:
	if _rail_badge == null or _rail_badge_panel == null:
		return
	if pending_count > 0:
		_rail_badge.text = str(pending_count) if pending_count < 100 else "99+"
		_rail_badge_panel.visible = true
	elif unread_count > 0:
		_rail_badge.text = "●"
		_rail_badge_panel.visible = true
	else:
		_rail_badge.text = ""
		_rail_badge_panel.visible = false


func _build() -> void:
	_build_top_bar()
	_build_stats()
	_build_touch_zone()
	_build_feature_rail()
	_build_toast()
	_build_main_dock()


func _build_top_bar() -> void:
	_top_bar = _new_panel(CREAM, 22)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(_top_bar)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(row)
	var profile := VBoxContainer.new()
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.alignment = BoxContainer.ALIGNMENT_CENTER
	profile.add_theme_constant_override("separation", 1)
	profile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(profile)
	_profile_label = _add_label("西小电", 29, INK)
	profile.add_child(_profile_label)
	_level_label = _add_label("Lv.1 · 今天也在陪你", 18, MUTED)
	profile.add_child(_level_label)
	_star_button = _add_button("✦  0", Color("#fff0c8"), Color("#765015"), 23, 16)
	_star_button.custom_minimum_size = Vector2(142, 66)
	_star_button.pressed.connect(func() -> void: feature_open_requested.emit("shop"))
	row.add_child(_star_button)
	var settings_button := _add_icon_text_button("设置", &"settings", Color("#eeeaf8"), INK)
	settings_button.custom_minimum_size = Vector2(108, 66)
	settings_button.tooltip_text = "打开设置"
	settings_button.pressed.connect(_toggle_settings)
	row.add_child(settings_button)


func _build_stats() -> void:
	var colors := [Color("#d79a62"), Color("#58a789"), Color("#766be0")]
	for index in range(3):
		var wrapper := VBoxContainer.new()
		wrapper.add_theme_constant_override("separation", 5)
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_design.add_child(wrapper)
		var label_row := HBoxContainer.new()
		label_row.add_theme_constant_override("separation", 3)
		label_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(label_row)
		var names := ["饱腹", "电量", "心情"]
		var label := _add_label(names[index], 20, INK)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_row.add_child(label)
		var value_label := _add_label("0%", 18, MUTED)
		label_row.add_child(value_label)
		_stat_labels[names[index]] = {"title": label, "value": value_label, "root": wrapper}
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", _progress_style(Color("#e9e5e8")))
		bar.add_theme_stylebox_override("fill", _progress_style(colors[index]))
		wrapper.add_child(bar)
		_stat_bars[names[index]] = bar


func _build_touch_zone() -> void:
	_touch_zone = Control.new()
	_touch_zone.name = "CharacterTouchRegion"
	_touch_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_zone.gui_input.connect(_on_touch_zone_input)
	_design.add_child(_touch_zone)


func _build_feature_rail() -> void:
	_feature_rail = Control.new()
	_feature_rail.name = "FeatureRail"
	_feature_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(_feature_rail)
	for entry in [
		{"page": "shop", "label": "商店", "icon": &"store"},
		{"page": "inventory", "label": "背包", "icon": &"backpack"},
		{"page": "travel", "label": "探险", "icon": &"compass"},
	]:
		var button := Button.new()
		button.name = "Feature_%s" % str(entry.page)
		button.text = ""
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", _button_style(Color("#ffffff"), 20))
		button.add_theme_stylebox_override("pressed", _button_style(Color("#e8e3f5"), 20))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var stack := VBoxContainer.new()
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_theme_constant_override("separation", 2)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(stack)
		var icon_surface := _new_panel(Color("#fffaf2"), 20)
		icon_surface.custom_minimum_size = Vector2(88, 72)
		icon_surface.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_surface.add_child(center)
		var icon := _icon(str(entry.icon), Color("#6256ad"), Vector2(50, 50))
		center.add_child(icon)
		stack.add_child(icon_surface)
		var label := _add_label(str(entry.label), 23, INK, HORIZONTAL_ALIGNMENT_CENTER)
		label.custom_minimum_size = Vector2(0, 30)
		stack.add_child(label)
		button.pressed.connect(func() -> void: feature_open_requested.emit(str(entry.page)))
		_feature_rail.add_child(button)
		_rail_buttons[str(entry.page)] = button
		if str(entry.page) == "travel":
			_rail_badge = _add_badge(button)
	_rail_badge_panel.visible = false


func _build_toast() -> void:
	_hint_panel = _new_panel(CREAM, 18)
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.visible = false
	_hint_panel.modulate.a = 0.0
	_design.add_child(_hint_panel)
	_hint_label = _add_label("", 21, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_child(_hint_label)


func _build_main_dock() -> void:
	_main_dock = Control.new()
	_main_dock.name = "MainInteractionDock"
	_main_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(_main_dock)
	var panel := _new_panel(SURFACE, 26)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_dock.add_child(panel)
	var feed := _add_icon_text_button("喂食", &"food_rice", Color("#f8ebdc"), INK)
	feed.pressed.connect(func() -> void: feature_open_requested.emit("food"))
	_main_dock.add_child(feed)
	var play := _add_icon_text_button("玩耍", &"run", Color("#e9e7f8"), INK)
	play.pressed.connect(func() -> void: play_requested.emit())
	_main_dock.add_child(play)
	_rest_button = _add_icon_text_button("休息", &"star", Color("#e3efe8"), INK)
	_rest_button.pressed.connect(func() -> void: rest_requested.emit())
	_main_dock.add_child(_rest_button)
	_hold_button = _add_button("按住说话", LAVENDER, CREAM, 27, 18)
	_hold_button.button_down.connect(func() -> void: hold_started.emit())
	_hold_button.button_up.connect(func() -> void: hold_released.emit())
	_main_dock.add_child(_hold_button)
	_level_meter = ProgressBar.new()
	_level_meter.min_value = 0.0
	_level_meter.max_value = 100.0
	_level_meter.show_percentage = false
	_level_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_meter.add_theme_stylebox_override("background", _progress_style(Color("#e9e5ee")))
	_level_meter.add_theme_stylebox_override("fill", _progress_style(LAVENDER))
	_main_dock.add_child(_level_meter)
	_auto_button = _add_button("自动聆听　·　已关闭", LAVENDER_TINT, INK, 23, 16)
	_auto_button.toggle_mode = true
	_auto_button.toggled.connect(func(enabled: bool) -> void: auto_listen_toggled.emit(enabled))
	_main_dock.add_child(_auto_button)
	_status_label = _add_label("麦克风默认关闭", 20, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_dock.add_child(_status_label)


func _fit_design() -> void:
	if _design == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var scale_factor := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	if scale_factor <= 0.0:
		return
	_design_height = maxf(DESIGN_SIZE.y, viewport_size.y / scale_factor)
	_design.scale = Vector2.ONE * scale_factor
	_design.position = Vector2((viewport_size.x - DESIGN_SIZE.x * scale_factor) * 0.5, 0.0)
	_design.size = Vector2(DESIGN_SIZE.x, _design_height)
	_safe_rect = SAFE_LAYOUT.get_safe_rect(_design, _design_height).grow(-12.0)
	if _safe_rect.size.x < 460.0 or _safe_rect.size.y < 760.0:
		_safe_rect = Rect2(Vector2(12, 12), Vector2(DESIGN_SIZE.x - 24, _design_height - 24))
	_layout_elements()


func _layout_elements() -> void:
	var top_y := _safe_rect.position.y + 12.0
	_top_bar.position = Vector2(_safe_rect.position.x + 10.0, top_y)
	_top_bar.size = Vector2(_safe_rect.size.x - 20.0, 88.0)

	var stats_y := top_y + 104.0
	var stats_total_width := maxf(420.0, _safe_rect.size.x - 28.0)
	var stat_column_width := (stats_total_width - 40.0) / 3.0
	for index in range(3):
		var stat_name: String = ["饱腹", "电量", "心情"][index]
		var stat: Dictionary = _stat_labels[stat_name]
		var x := _safe_rect.position.x + 14.0 + index * (stat_column_width + 20.0)
		var wrapper: VBoxContainer = stat.root
		wrapper.position = Vector2(x, stats_y)
		wrapper.size = Vector2(stat_column_width, 48.0)
		var value_label: Label = stat.value
		value_label.custom_minimum_size = Vector2(42, 0)
		var bar: ProgressBar = _stat_bars[stat_name]
		bar.custom_minimum_size = Vector2(0, 7)

	var dock_height := 368.0
	var dock_y := _safe_rect.end.y - 24.0 - dock_height
	var dock_x := _safe_rect.position.x + 24.0
	var dock_width := _safe_rect.size.x - 48.0
	_main_dock.position = Vector2.ZERO
	_main_dock.size = Vector2(DESIGN_SIZE.x, _design_height)
	var panel: Control = _main_dock.get_child(0)
	panel.position = Vector2(dock_x, dock_y)
	panel.size = Vector2(dock_width, dock_height)
	var action_x := dock_x + 16.0
	var action_width := dock_width - 32.0
	var button_gap := 10.0
	var care_width := (action_width - button_gap * 2.0) / 3.0
	for index in range(3):
		var button: Control = _main_dock.get_child(index + 1)
		button.position = Vector2(action_x + index * (care_width + button_gap), dock_y + 12.0)
		button.size = Vector2(care_width, 92.0)
	_hold_button.position = Vector2(action_x, dock_y + 116.0)
	_hold_button.size = Vector2(action_width, 88.0)
	_level_meter.position = Vector2(action_x + 24.0, dock_y + 214.0)
	_level_meter.size = Vector2(action_width - 48.0, 6.0)
	_auto_button.position = Vector2(action_x, dock_y + 230.0)
	_auto_button.size = Vector2(action_width, 72.0)
	_status_label.position = Vector2(action_x, dock_y + 309.0)
	_status_label.size = Vector2(action_width, 34.0)

	var rail_x := _safe_rect.end.x - 112.0
	var rail_height := 112.0 * 3.0 + 16.0 * 2.0
	var stage_top := stats_y + 68.0
	var stage_bottom := dock_y - 86.0
	var rail_y := stage_top + maxf(8.0, (stage_bottom - stage_top - rail_height) * 0.5 - 24.0)
	rail_y = minf(rail_y, stage_bottom - rail_height)
	rail_y = maxf(stage_top + 8.0, rail_y)
	_feature_rail.position = Vector2(rail_x, rail_y)
	_feature_rail.size = Vector2(112.0, rail_height)
	for index in range(3):
		var page: String = ["shop", "inventory", "travel"][index]
		var button: Button = _rail_buttons[page]
		button.position = Vector2(0.0, index * 128.0)
		button.size = Vector2(112.0, 112.0)
	_hint_panel.position = Vector2(_safe_rect.position.x + 40.0, dock_y - 69.0)
	_hint_panel.size = Vector2(_safe_rect.size.x - 80.0, 50.0)

	_touch_zone.position = Vector2(_safe_rect.position.x + 12.0, stage_top)
	_touch_zone.size = Vector2(maxf(0.0, rail_x - _touch_zone.position.x - 16.0), maxf(0.0, dock_y - 88.0 - stage_top))


func _on_touch_zone_input(event: InputEvent) -> void:
	var viewport_position := Vector2.ZERO
	if event is InputEventScreenTouch:
		if not event.pressed:
			return
		viewport_position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			return
		viewport_position = event.position
	else:
		return
	var to_local := _touch_zone.get_global_transform_with_canvas().affine_inverse()
	var local_point: Vector2 = to_local * viewport_position
	var touch_ratio := clampf(local_point.y / maxf(_touch_zone.size.y, 1.0), 0.0, 1.0)
	var region := "head"
	if touch_ratio >= 0.62:
		region = "feet"
	elif touch_ratio >= 0.42:
		region = "body"
	touch_requested.emit(region)
	_touch_zone.accept_event()


func _add_badge(parent: Control) -> Label:
	var badge_panel := PanelContainer.new()
	badge_panel.name = "TravelBadge"
	badge_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge_panel.offset_left = -40.0
	badge_panel.offset_right = -2.0
	badge_panel.offset_top = 0.0
	badge_panel.offset_bottom = 30.0
	badge_panel.add_theme_stylebox_override("panel", _button_style(Color("#b83e58"), 14))
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := Label.new()
	badge.text = ""
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 17)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.add_child(badge)
	parent.add_child(badge_panel)
	_rail_badge_panel = badge_panel
	return badge


func _add_icon_text_button(text_value: String, icon_name: StringName, color: Color, text_color: Color) -> Button:
	var button := Button.new()
	button.text = ""
	button.add_theme_stylebox_override("normal", _button_style(color, 18))
	button.add_theme_stylebox_override("hover", _button_style(color.lightened(0.035), 18))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.04), 18))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := _icon(str(icon_name), text_color, Vector2(38, 38))
	row.add_child(icon)
	var label := _add_label(text_value, 25, text_color, HORIZONTAL_ALIGNMENT_CENTER)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	button.add_child(row)
	return button


func _icon(name: String, color: Color, icon_size: Vector2) -> Control:
	var icon: Control = FLAT_ICON.new()
	icon.set("icon_name", StringName(name))
	icon.set("icon_color", color)
	icon.custom_minimum_size = icon_size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _update_rest_button() -> void:
	if _rest_button != null:
		_rest_button.get_child(0).get_child(1).text = "叫醒" if _resting else "休息"


func _set_stat(stat_name: String, value: float) -> void:
	var stat: Dictionary = _stat_labels.get(stat_name, {})
	var label: Label = stat.get("value")
	var bar: ProgressBar = _stat_bars.get(stat_name)
	if label != null:
		label.text = "%d%%" % int(round(value))
	if bar != null:
		bar.value = clampf(value, 0.0, 100.0)


func _new_panel(color: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(color, radius))
	return panel


func _panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = Color("#ffffff")
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _button_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := _panel_style(color, radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _progress_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	return style


func _add_button(text_value: String, color: Color, text_color: Color, font_size: int, radius: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_stylebox_override("normal", _button_style(color, radius))
	button.add_theme_stylebox_override("hover", _button_style(color.lightened(0.035), radius))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.04), radius))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _add_label(text_value: String, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _toggle_settings() -> void:
	feature_open_requested.emit("settings")
