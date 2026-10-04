extends Control

signal command_requested(kind: String, arguments: Dictionary)
signal closed
signal audio_preview_changed(music_percent: float, sfx_percent: float)
signal audio_settings_changed(music_percent: float, sfx_percent: float)

const DESIGN_SIZE := Vector2(720.0, 1280.0)
const SAFE_LAYOUT = preload("res://Scripts/UI/SafeAreaLayout.gd")
const FLAT_ICON = preload("res://Scripts/UI/FlatIcon.gd")
const INK := Color("#29283c")
const MUTED := Color("#747489")
const CREAM := Color("#fffaf2")
const LAVENDER := Color("#766be0")
const PALE_LAVENDER := Color("#eeeafa")
const DESTINATION_NAMES := {
	"campus_gate": "校门口",
	"canteen": "食堂",
	"library": "图书馆",
	"riverbank": "河畔",
	"stargazing_hill": "观星山坡",
	"coast": "海边",
}

var _services: Node
var _design: Control
var _sheet: PanelContainer
var _dimmer: ColorRect
var _header: HBoxContainer
var _tabs: HBoxContainer
var _content: VBoxContainer
var _back_button: Button
var _title: Label
var _wallet_label: Label
var _message: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _footer: HBoxContainer
var _music_slider: HSlider
var _sfx_slider: HSlider
var _music_value_label: Label
var _sfx_value_label: Label
var _page := ""
var _travel_tab := "travel"
var _selected_shop_item := ""
var _shop_category := "all"
var _quantity := 1
var _selected_route := "nearby"
var _use_bento := false
var _inventory_category := "all"
var _selected_inventory_item := ""
var _selected_mail_id := ""
var _mail_page := 0
var _busy := false
var _travel_progress: ProgressBar
var _last_buy_signature := ""
var _last_buy_msec := 0
var _travel_signature := ""
var _mail_signature := ""
var _album_signature := ""
var _pending_badge_count := -1
var _unread_badge_count := -1
var _settings_music := 30.0
var _settings_sfx := 65.0
var _safe_rect := Rect2(Vector2.ZERO, DESIGN_SIZE)
var _design_height := DESIGN_SIZE.y
var _closing := false


func setup(services: Node) -> void:
	_services = services


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_design = Control.new()
	_design.name = "FeatureOverlayDesign"
	_design.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_design)
	_dimmer = ColorRect.new()
	_dimmer.name = "Dimmer"
	_dimmer.color = Color(0.12, 0.11, 0.19, 0.62)
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dimmer.gui_input.connect(_on_dimmer_input)
	_design.add_child(_dimmer)
	_sheet = PanelContainer.new()
	_sheet.name = "CenteredFeaturePanel"
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.add_theme_stylebox_override("panel", _panel_style(Color("#fffaf2"), 28, 1.0))
	_design.add_child(_sheet)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.add_child(_content)
	_build_header()
	_build_tabs()
	_message = _label("", Rect2(), 20, MUTED)
	_message.custom_minimum_size = Vector2(0, 28)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_message)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 12)
	_rows.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_rows)
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 10)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_footer)
	visible = false
	_fit_design()
	get_viewport().size_changed.connect(_fit_design)
	if _services != null and _services.has_signal("state_changed"):
		_services.state_changed.connect(_on_state_changed)


func _build_header() -> void:
	_header = HBoxContainer.new()
	_header.alignment = BoxContainer.ALIGNMENT_CENTER
	_header.add_theme_constant_override("separation", 8)
	_content.add_child(_header)
	_back_button = _icon_button("back", "返回上一层")
	_back_button.custom_minimum_size = Vector2(64, 64)
	_back_button.pressed.connect(_go_back)
	_header.add_child(_back_button)
	_title = _label("", Rect2(), 30, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title)
	_wallet_label = _label("✦ 0", Rect2(), 22, Color("#8c651c"))
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wallet_label.custom_minimum_size = Vector2(100, 0)
	_header.add_child(_wallet_label)
	var close := _icon_button("close", "关闭面板")
	close.custom_minimum_size = Vector2(64, 64)
	close.pressed.connect(_close)
	_header.add_child(close)


func _build_tabs() -> void:
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 64)
	_content.add_child(_tabs)


func open(page: String) -> void:
	_page = "inventory" if page == "food" else ("travel" if page == "more" else page)
	if page == "food":
		_inventory_category = "food"
		_selected_inventory_item = ""
	if page == "travel":
		_selected_mail_id = ""
	if page in ["mailbox", "album"]:
		_page = "travel"
		_travel_tab = page
	else:
		_travel_tab = "travel"
	_selected_mail_id = ""
	if page == "mailbox":
		_mail_page = 0
	_busy = false
	_closing = false
	if _message != null:
		_message.text = ""
	visible = true
	_render()
	_sheet.modulate.a = 0.0
	_sheet.scale = Vector2(0.97, 0.97)
	_sheet.pivot_offset = _sheet.size * 0.5
	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(_sheet, "modulate:a", 1.0, 0.17)
	entrance.tween_property(_sheet, "scale", Vector2.ONE, 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func show_command_result(result: Dictionary, message: String = "") -> void:
	_busy = false
	if not message.is_empty():
		_message.text = message
	else:
		_message.text = str(result.get("message", "操作完成。"))
	_message.add_theme_color_override("font_color", INK if bool(result.get("ok", false)) else Color("#b75164"))
	_render(false)


func close_overlay() -> void:
	_close()


func refresh() -> void:
	_render(false)


func show_hint(message: String) -> void:
	if not visible or _message == null:
		return
	_message.text = message
	_message.add_theme_color_override("font_color", Color("#6c5cb4"))
	_message.visible = true


func refresh_layout() -> void:
	_fit_design()


func set_audio_settings(music_percent: float, sfx_percent: float) -> void:
	_settings_music = clampf(music_percent, 0.0, 100.0)
	_settings_sfx = clampf(sfx_percent, 0.0, 100.0)
	if is_instance_valid(_music_slider):
		_music_slider.set_value_no_signal(_settings_music)
		_music_value_label.text = "%d%%" % int(round(_settings_music))
	if is_instance_valid(_sfx_slider):
		_sfx_slider.set_value_no_signal(_settings_sfx)
		_sfx_value_label.text = "%d%%" % int(round(_settings_sfx))


func set_mail_badges(pending_count: int, unread_count: int) -> void:
	if pending_count == _pending_badge_count and unread_count == _unread_badge_count:
		return
	_pending_badge_count = pending_count
	_unread_badge_count = unread_count
	if visible and _page == "travel":
		_rebuild_tabs()


func _render(update_message: bool = true) -> void:
	if not is_inside_tree() or _services == null or not _services.ready_ok:
		return
	if update_message and _message != null:
		_message.text = ""
	if update_message and _scroll != null:
		_scroll.scroll_vertical = 0
	_wallet_label.text = "✦ %d" % int(_services.store.get_snapshot().get("wallet", {}).get("stars", 0))
	_back_button.visible = _page == "travel" and _travel_tab == "mailbox" and not _selected_mail_id.is_empty()
	_rebuild_tabs()
	match _page:
		"more":
			_page = "travel"
			_travel_tab = "travel"
			_title.text = "西小电的旅行"
			_render_travel()
		"shop":
			_title.text = "星星商店"
			_render_shop()
		"food", "inventory":
			_page = "inventory"
			_title.text = "背包"
			_render_inventory()
		"travel":
			match _travel_tab:
				"mailbox":
					_title.text = "旅行来信"
					_render_mailbox()
				"album":
					_title.text = "旅行图鉴"
					_render_album()
				_:
					_title.text = "西小电的旅行"
					_render_travel()
		"settings":
			_title.text = "设置"
			_wallet_label.text = ""
			_render_settings()
	_renew_footer()
	_message.visible = not _message.text.is_empty()
	if _page == "settings":
		_tabs.visible = false
	else:
		_tabs.visible = true
	if is_instance_valid(_wallet_label):
		_wallet_label.visible = _page != "settings"


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var options: Array[Dictionary] = []
	if _page == "shop":
		options = [
			{"id": "all", "name": "全部"}, {"id": "food", "name": "食物"},
			{"id": "recovery", "name": "恢复"}, {"id": "growth", "name": "成长"},
		]
	elif _page == "inventory":
		options = [
			{"id": "all", "name": "全部"}, {"id": "food", "name": "食物"},
			{"id": "recovery", "name": "恢复"}, {"id": "growth", "name": "成长"},
			{"id": "souvenir", "name": "纪念"},
		]
	elif _page in ["travel", "mailbox", "album"]:
		var unread_count: int = _services.mailbox.unread_count()
		var inbox_label := "来信"
		if _services.mailbox.pending_count() > 0:
			inbox_label = "来信 %d" % _services.mailbox.pending_count()
		elif unread_count > 0:
			inbox_label = "来信 %d" % unread_count
		options = [
			{"id": "travel", "name": "出行"}, {"id": "mailbox", "name": inbox_label},
			{"id": "album", "name": "图鉴"},
		]
	else:
		return
	for option in options:
		var option_id := str(option.id)
		var is_active := (_shop_category == option_id and _page == "shop") or (_inventory_category == option_id and _page == "inventory") or (_travel_tab == option_id and _page in ["travel", "mailbox", "album"])
		var button := _button(str(option.name), Rect2(), LAVENDER if is_active else PALE_LAVENDER, CREAM if is_active else INK, 20)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 62)
		button.pressed.connect(_select_tab.bind(_page, option_id))
		_tabs.add_child(button)


func _render_shop() -> void:
	_clear_rows()
	_add_section_note("挑选一件小礼物。星星会从旅行和互动中慢慢攒起来。")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(grid)
	var visible_count := 0
	for item in _services.shop.get_offers():
		var category := str(item.get("category", ""))
		if _shop_category != "all" and category != _shop_category:
			continue
		visible_count += 1
		_add_catalog_tile(grid, item, _selected_shop_item == str(item.id), int(item.get("owned", 0)), _select_shop_item.bind(str(item.id)))
	if visible_count == 0:
		_add_section_note("这个分类暂时没有商品。")
	if not _selected_shop_item.is_empty():
		var selected: Dictionary = _services.catalog.get_item(_selected_shop_item)
		if not selected.is_empty():
			_add_section_note("%s：%s。购买数量可在下方调整。" % [str(selected.get("name", "道具")), _effect_description(selected.get("effects", {}))])


func _render_inventory() -> void:
	_clear_rows()
	_add_section_note("道具按种类整理。先点选查看效果，再从下方确认使用。")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(grid)
	var items: Array = _services.inventory.get_items(_inventory_category)
	for item in items:
		var item_id := str(item.id)
		var effect_text := _effect_description(item.get("effects", {}))
		var usable := str(item.get("category", "")) not in ["souvenir", "legacy"]
		if usable:
			var preview: Dictionary = _services.inventory.preview_use(item_id, _services.store.is_resting())
			if bool(preview.get("ok", false)):
				effect_text = _effect_description(preview.get("actual_changes", {}))
			else:
				effect_text = str(preview.get("message", effect_text))
		var card_item: Dictionary = item.duplicate(true)
		card_item["tile_detail"] = "持有 %d　·　%s" % [int(item.get("count", 0)), effect_text]
		_add_catalog_tile(grid, card_item, _selected_inventory_item == item_id, int(item.get("count", 0)), _select_inventory_item.bind(item_id))
	if items.is_empty():
		_add_section_note("这里还空着。可以去商店挑一点喜欢的道具。")
	if not _selected_inventory_item.is_empty():
		var selected: Dictionary = _services.catalog.get_item(_selected_inventory_item)
		if selected.is_empty():
			_add_section_note("这是旧版存档中的道具；数量已保留，目前没有可用效果。")
		elif str(selected.get("category", "")) == "souvenir":
			_add_section_note("旅行纪念品 · 持有 %d 件 · 可在图鉴中查看旅途故事。" % _services.store.get_item_count(_selected_inventory_item))
		else:
			var preview: Dictionary = _services.inventory.preview_use(_selected_inventory_item, _services.store.is_resting())
			_add_section_note("使用预览：%s" % ( _effect_description(preview.get("actual_changes", {})) if bool(preview.get("ok", false)) else str(preview.get("message", "当前无法使用。"))))


func _render_travel() -> void:
	_clear_rows()
	_travel_progress = null
	var travel_state: Dictionary = _services.travel.get_snapshot()
	var active: Variant = travel_state.get("active_trip")
	if typeof(active) == TYPE_DICTIONARY:
		var route: Dictionary = _services.catalog.get_route(str(active.route_id))
		var route_name := str(route.get("name", "快速引导旅程" if bool(active.get("is_tutorial", false)) else str(active.route_id)))
		_add_section_note("%s　·　%s" % [route_name, "已经回来" if str(active.state) == "RETURNED" else "正在旅途中"])
		_travel_progress = ProgressBar.new()
		_travel_progress.min_value = 0
		_travel_progress.max_value = maxf(1.0, float(active.total_duration_sec))
		_travel_progress.value = float(active.elapsed_sec)
		_travel_progress.custom_minimum_size = Vector2(0, 16)
		_rows.add_child(_travel_progress)
		_add_section_note("旅程进度：%s / %s" % [_format_duration(float(active.elapsed_sec)), _format_duration(float(active.total_duration_sec))])
		var arrived_count := int(active.delivery_cursor)
		_add_section_note("已经寄回 %d / %d 封，附件放在收件箱。" % [arrived_count, int(active.events.size())])
		for index in range(int(active.delivery_cursor), active.events.size()):
			var event: Dictionary = active.events[index]
			var remaining := maxf(0.0, float(event.due_offset_sec) - float(active.elapsed_sec))
			_add_section_note("%s　·　约 %s 后到达" % ["归来" if str(event.kind) == "return" else "旅行名片", _format_duration(remaining)])
		_travel_signature = "%s:%s:%d" % [str(active.get("trip_id", "")), str(active.get("state", "")), int(active.get("delivery_cursor", 0))]
		return
	_travel_signature = ""

	_add_section_note("选一条路线。西小电在出门期间仍会留在主界面陪你。")
	var tutorial_started := bool(_services.store.get_snapshot().flags.get("tutorial_trip_started", false))
	if not tutorial_started:
		_add_action_card("快速引导 · 约 2–4 分钟", "免费体验 2 张名片和一次归来，首次奖励固定。", "出发", func() -> void:
			if not _busy:
				_busy = true
				command_requested.emit("tutorial", {})
		)
	for route in _services.catalog.get_routes():
		var route_id := str(route.id)
		var name := str(route.name)
		var min_total := int(route.leg_min_seconds) * (int(route.postcard_count) + 1)
		var max_total := int(route.leg_max_seconds) * (int(route.postcard_count) + 1)
		var star_min := int(route.postcard_count) * int(route.postcard_stars_min) + int(route.return_stars_min)
		var star_max := int(route.postcard_count) * int(route.postcard_stars_max) + int(route.return_stars_max)
		var description := "%s\n%d 张名片　·　约 %s–%s　·　基础 ✦ %d–%d，另有随机道具" % [str(route.get("description", "")), int(route.postcard_count), _format_duration(min_total), _format_duration(max_total), star_min, star_max]
		_add_action_card(name, description, "已选择" if _selected_route == str(route_id) else "选择", _select_route.bind(str(route_id)))


func _render_mailbox() -> void:
	_clear_rows()
	var mails: Array = _services.mailbox.get_mails("all")
	_mail_signature = "%d:%d:%d" % [mails.size(), _services.mailbox.pending_count(), _services.mailbox.unread_count()]
	_add_section_note("未领取 %d　·　未读 %d" % [_services.mailbox.pending_count(), _services.mailbox.unread_count()])
	if not _selected_mail_id.is_empty():
		for mail in mails:
			if str(mail.mail_id) != _selected_mail_id:
				continue
			_add_section_note("%s　%s" % ["✦ 稀有名片" if str(mail.get("rarity", "")) == "rare" else "旅行小记", str(mail.get("title", "旅行来信"))])
			if str(mail.get("kind", "")) == "postcard":
				_add_postcard_image(str(mail.get("destination_id", "")))
			_add_wrapped_text(str(mail.get("text", "")), 16)
			_add_section_note(_bundle_description(mail.get("reward_bundle", {})))
			if bool(mail.get("claimed", false)):
				_add_section_note("附件已收下。")
			break
		return
	var page_count := maxi(1, int(ceil(float(mails.size()) / 20.0)))
	_mail_page = clampi(_mail_page, 0, page_count - 1)
	_add_section_note("第 %d / %d 页" % [_mail_page + 1, page_count])
	var page_start := _mail_page * 20
	var page_end := mini(mails.size(), page_start + 20)
	for mail_index in range(page_start, page_end):
		var mail: Dictionary = mails[mail_index]
		var marker := "● " if not bool(mail.get("read", false)) else ""
		var status := "已领取" if bool(mail.get("claimed", false)) else "有附件"
		_add_action_card(marker + str(mail.get("title", "旅行来信")), "%s　·　%s" % [status, _bundle_description(mail.get("reward_bundle", {}))], "查看", _open_mail.bind(str(mail.mail_id)))
	if mails.is_empty():
		_add_section_note("还没有旅行来信。先安排一次出发吧！")


func _render_album() -> void:
	_clear_rows()
	var snapshot: Dictionary = _services.store.get_snapshot()
	var album: Dictionary = snapshot.get("album", {})
	_album_signature = _make_album_signature(album)
	_add_section_note("已收集 %d / 18 张。未解锁的名片会在旅途中逐渐出现。" % album.size())
	for goal in _services.catalog.progression.get("collection_rewards", []):
		var threshold := int(goal.get("threshold", 0))
		var reward: Dictionary = goal.get("bundle", {})
		_add_section_note("%s %d 张　·　奖励 %s" % ["✓" if album.size() >= threshold else "○", threshold, _bundle_description(reward)])
	var keys: Array = _services.catalog.postcards.keys()
	keys.sort()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(grid)
	for template_id in keys:
		var card: Dictionary = _services.catalog.get_card(str(template_id))
		var entry: Dictionary = album.get(str(template_id), {})
		_add_album_tile(grid, card, entry)


func _add_album_tile(parent: Control, card: Dictionary, entry: Dictionary) -> void:
	var panel := _card()
	panel.custom_minimum_size = Vector2(0, 236)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	if entry.is_empty():
		var placeholder := CenterContainer.new()
		placeholder.custom_minimum_size = Vector2(0, 112)
		placeholder.add_child(_flat_icon(&"album", Color("#aaa5bb"), Vector2(70, 70)))
		column.add_child(placeholder)
		var locked := _label("未解锁名片", Rect2(), 21, MUTED)
		locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(locked)
		var hint := _label("继续旅行来收集", Rect2(), 17, MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(hint)
		return
	var destination_id := str(entry.get("destination_id", card.get("destination_id", "")))
	var image := _make_postcard_texture(destination_id, Vector2(260, 112))
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	column.add_child(image)
	var rarity := "稀有" if str(card.get("rarity", "")) == "rare" else "普通"
	var title := _label("%s　·　%s" % [str(DESTINATION_NAMES.get(destination_id, destination_id)), rarity], Rect2(), 20, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var body := _label(str(entry.get("text", card.get("text", ""))), Rect2(), 16, MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 43)
	column.add_child(body)
	var count := _label("收到 %d 次" % int(entry.get("received_count", 1)), Rect2(), 16, Color("#7666bd"))
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(count)


func _render_settings() -> void:
	_clear_rows()
	_add_section_note("把陪伴音量调到舒服的位置。设置会在重新打开游戏后保留。")
	_add_slider_card("背景音乐", "阳光像素小曲", _settings_music, true)
	_add_slider_card("音效与复述", "触摸、游戏和西小电复述音量", _settings_sfx, false)
	_add_section_note("麦克风只会在你启用自动聆听或按住说话时工作。")


func _add_slider_card(title: String, subtitle: String, value: float, is_music: bool) -> void:
	var panel := _card()
	panel.custom_minimum_size = Vector2(0, 168)
	_rows.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	var title_label := _label(title, Rect2(), 24, INK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	var value_label := _label("%d%%" % int(round(value)), Rect2(), 21, Color("#6c5cb4"))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(value_label)
	column.add_child(heading)
	var detail := _label(subtitle, Rect2(), 18, MUTED)
	column.add_child(detail)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 42)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(slider)
	if is_music:
		_music_slider = slider
		_music_value_label = value_label
		slider.value_changed.connect(func(next_value: float) -> void:
			_settings_music = next_value
			_music_value_label.text = "%d%%" % int(round(next_value))
			audio_preview_changed.emit(_settings_music, _settings_sfx)
		)
	else:
		_sfx_slider = slider
		_sfx_value_label = value_label
		slider.value_changed.connect(func(next_value: float) -> void:
			_settings_sfx = next_value
			_sfx_value_label.text = "%d%%" % int(round(next_value))
			audio_preview_changed.emit(_settings_music, _settings_sfx)
		)
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			audio_settings_changed.emit(_settings_music, _settings_sfx)
	)
	slider.focus_exited.connect(func() -> void:
		audio_settings_changed.emit(_settings_music, _settings_sfx)
	)


func _renew_footer() -> void:
	for child in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()
	if _page == "inventory":
		var free_feed := _button("免费喂食", Rect2(), Color("#f9ead6"), INK, 19)
		free_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		free_feed.custom_minimum_size = Vector2(0, 68)
		free_feed.pressed.connect(func() -> void:
			if not _busy:
				_busy = true
				command_requested.emit("free_feed", {})
		)
		_footer.add_child(free_feed)
		var selected: Dictionary = _services.catalog.get_item(_selected_inventory_item)
		if not selected.is_empty() and str(selected.get("category", "")) != "souvenir":
			if _selected_inventory_item == "picnic_bento":
				var trip_prep := _button("带上便当", Rect2(), Color("#e9e7f8"), INK, 19)
				trip_prep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				trip_prep.custom_minimum_size = Vector2(0, 68)
				trip_prep.pressed.connect(_prepare_bento_trip)
				_footer.add_child(trip_prep)
			else:
				var preview: Dictionary = _services.inventory.preview_use(_selected_inventory_item, _services.store.is_resting())
				var use_button := _button("使用一份", Rect2(), LAVENDER, CREAM, 19)
				use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				use_button.custom_minimum_size = Vector2(0, 68)
				use_button.disabled = not bool(preview.get("ok", false)) or _busy
				use_button.pressed.connect(func() -> void:
					if not _busy:
						_busy = true
						command_requested.emit("use", {"item_id": _selected_inventory_item})
				)
				_footer.add_child(use_button)
	elif _page == "shop":
		var offer: Dictionary = _services.catalog.get_item(_selected_shop_item)
		if offer.is_empty():
			var prompt := _label("先点选一件商品", Rect2(), 20, MUTED)
			prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_footer.add_child(prompt)
		else:
			var less := _button("−", Rect2(), PALE_LAVENDER, INK, 24)
			less.custom_minimum_size = Vector2(68, 68)
			less.pressed.connect(func() -> void: _quantity = maxi(1, _quantity - 1); _render(false))
			_footer.add_child(less)
			var amount := _label("%d 件\n✦ %d" % [_quantity, int(offer.price) * _quantity], Rect2(), 20, INK)
			amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_footer.add_child(amount)
			var more := _button("＋", Rect2(), PALE_LAVENDER, INK, 24)
			more.custom_minimum_size = Vector2(68, 68)
			more.pressed.connect(func() -> void: _quantity = mini(99, _quantity + 1); _render(false))
			_footer.add_child(more)
			var buy := _button("购买", Rect2(), LAVENDER, CREAM, 19)
			buy.custom_minimum_size = Vector2(142, 68)
			buy.disabled = int(offer.price) * _quantity > int(_services.store.get_snapshot().wallet.stars) or _busy
			buy.pressed.connect(_request_buy.bind(_selected_shop_item))
			_footer.add_child(buy)
	elif _page == "travel":
		if _travel_tab == "travel":
			var active: Variant = _services.travel.get_snapshot().get("active_trip")
			if typeof(active) == TYPE_DICTIONARY and str(active.get("state", "")) == "RETURNED":
				var ack := _button("收好行李", Rect2(), LAVENDER, CREAM, 20)
				ack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ack.custom_minimum_size = Vector2(0, 68)
				ack.pressed.connect(func() -> void:
					if not _busy:
						_busy = true
						command_requested.emit("ack_return", {})
				)
				_footer.add_child(ack)
			elif typeof(active) == TYPE_DICTIONARY:
				var inbox := _button("查看来信　%d" % _services.mailbox.pending_count(), Rect2(), PALE_LAVENDER, INK, 20)
				inbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				inbox.custom_minimum_size = Vector2(0, 68)
				inbox.pressed.connect(func() -> void: _select_tab("travel", "mailbox"))
				_footer.add_child(inbox)
			else:
				var bento_count: int = _services.store.get_item_count("picnic_bento")
				var bento := _button("%s 便当 × %d" % ["✓" if _use_bento else "＋", bento_count], Rect2(), Color("#f5ecda"), INK, 18)
				bento.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				bento.custom_minimum_size = Vector2(0, 68)
				bento.disabled = bento_count <= 0 and not _use_bento
				bento.pressed.connect(func() -> void: _use_bento = not _use_bento; _render(false))
				_footer.add_child(bento)
				var depart := _button("现在出发", Rect2(), LAVENDER, CREAM, 20)
				depart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				depart.custom_minimum_size = Vector2(0, 68)
				depart.disabled = _busy
				depart.pressed.connect(func() -> void:
					if not _busy:
						_busy = true
						command_requested.emit("depart", {"route_id": _selected_route, "supply_item_id": "picnic_bento" if _use_bento else ""})
						if typeof(_services.travel.get_snapshot().get("active_trip")) == TYPE_DICTIONARY:
							_use_bento = false
				)
				_footer.add_child(depart)
		elif _travel_tab == "mailbox":
			if not _selected_mail_id.is_empty():
				var selected_mail: Dictionary = {}
				for mail in _services.mailbox.get_mails("all"):
					if str(mail.get("mail_id", "")) == _selected_mail_id:
						selected_mail = mail
						break
				var claimed := bool(selected_mail.get("claimed", false))
				var claim := _button("附件已收下" if claimed else "收下附件", Rect2(), PALE_LAVENDER if claimed else LAVENDER, INK if claimed else CREAM, 20)
				claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				claim.custom_minimum_size = Vector2(0, 68)
				claim.disabled = selected_mail.is_empty() or claimed or _busy
				claim.pressed.connect(func() -> void:
					if not _busy:
						_busy = true
						command_requested.emit("claim", {"mail_id": _selected_mail_id})
				)
				_footer.add_child(claim)
			else:
				var mails: Array = _services.mailbox.get_mails("all")
				var page_count := maxi(1, int(ceil(float(mails.size()) / 20.0)))
				var previous := _button("上一页", Rect2(), PALE_LAVENDER, INK, 18)
				previous.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				previous.custom_minimum_size = Vector2(0, 68)
				previous.disabled = _mail_page <= 0
				previous.pressed.connect(func() -> void: _mail_page = maxi(0, _mail_page - 1); _render(false))
				_footer.add_child(previous)
				var claim_all := _button("全部收下", Rect2(), LAVENDER, CREAM, 18)
				claim_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				claim_all.custom_minimum_size = Vector2(0, 68)
				claim_all.disabled = _services.mailbox.pending_count() <= 0 or _busy
				claim_all.pressed.connect(func() -> void:
					if not _busy:
						_busy = true
						command_requested.emit("claim_all", {})
				)
				_footer.add_child(claim_all)
				var next := _button("下一页", Rect2(), PALE_LAVENDER, INK, 18)
				next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				next.custom_minimum_size = Vector2(0, 68)
				next.disabled = _mail_page >= page_count - 1
				next.pressed.connect(func() -> void: _mail_page = mini(page_count - 1, _mail_page + 1); _render(false))
				_footer.add_child(next)
		else:
			var inbox_button := _button("查看旅行来信", Rect2(), PALE_LAVENDER, INK, 20)
			inbox_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			inbox_button.custom_minimum_size = Vector2(0, 68)
			inbox_button.pressed.connect(func() -> void: _select_tab("travel", "mailbox"))
			_footer.add_child(inbox_button)
	elif _page == "settings":
		var reset := _button("恢复默认音量", Rect2(), PALE_LAVENDER, INK, 19)
		reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reset.custom_minimum_size = Vector2(0, 68)
		reset.pressed.connect(func() -> void:
			set_audio_settings(30.0, 65.0)
			audio_preview_changed.emit(_settings_music, _settings_sfx)
			audio_settings_changed.emit(_settings_music, _settings_sfx)
		)
		_footer.add_child(reset)


func _add_action_card(heading: String, description: String, action_text: String, action: Callable) -> void:
	var panel := _card()
	panel.custom_minimum_size = Vector2(0, 144)
	_rows.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(82, 82)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_panel.add_theme_stylebox_override("panel", _panel_style(Color("#f0edf9"), 20, 1.0))
	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.add_child(icon_center)
	icon_center.add_child(_flat_icon(_action_icon(heading), Color("#6256ad"), Vector2(56, 56)))
	row.add_child(icon_panel)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_label(heading, Rect2(), 23, INK))
	var body := _label(description, Rect2(), 18, MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 52)
	column.add_child(body)
	row.add_child(column)
	var button := _button(action_text, Rect2(), Color("#eeeafa"), INK, 19)
	button.custom_minimum_size = Vector2(106, 58)
	button.pressed.connect(action)
	row.add_child(button)


func _add_catalog_tile(parent: Control, item: Dictionary, selected: bool, amount: int, action: Callable) -> void:
	var item_id := str(item.get("id", ""))
	var tile := Button.new()
	tile.text = ""
	tile.custom_minimum_size = Vector2(0, 226)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("normal", _button_style(Color("#ffffff") if not selected else Color("#f0edff"), 20))
	tile.add_theme_stylebox_override("hover", _button_style(Color("#f7f5fc"), 20))
	tile.add_theme_stylebox_override("pressed", _button_style(Color("#e9e4fb"), 20))
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tile.pressed.connect(action)
	parent.add_child(tile)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 5)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(column)
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(0, 78)
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.add_theme_stylebox_override("panel", _panel_style(Color("#f4f0fa"), 18, 1.0))
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.add_child(center)
	center.add_child(_flat_icon(_catalog_icon(item_id), Color("#6256ad"), Vector2(60, 60)))
	column.add_child(icon_panel)
	var title := _label(str(item.get("name", "道具")), Rect2(), 21, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var detail_text := str(item.get("tile_detail", "✦ %d　·　持有 %d" % [int(item.get("price", 0)), amount]))
	var detail := _label(detail_text, Rect2(), 17, MUTED)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(0, 42)
	column.add_child(detail)
	var hint := _label("已选" if selected else "点按查看", Rect2(), 17, Color("#6f61ba") if selected else MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _catalog_icon(item_id: String) -> StringName:
	if item_id == "rice_ball":
		return &"food_rice"
	if item_id == "sunshine_milk":
		return &"food_milk"
	if item_id == "smile_cookie":
		return &"food_cookie"
	if item_id == "picnic_bento":
		return &"food_bento"
	if item_id == "energy_drink":
		return &"food_drink"
	if item_id == "joke_book" or item_id.ends_with("bookmark"):
		return &"food_book"
	if item_id.begins_with("souvenir_"):
		return &"souvenir"
	if item_id in ["study_card", "growth_notebook"]:
		return &"food_growth"
	return &"star"


func _action_icon(heading: String) -> StringName:
	if heading.contains("城市"):
		return &"route_city"
	if heading.contains("远方"):
		return &"route_far"
	if heading.contains("附近") or heading.contains("散步"):
		return &"route_nearby"
	if heading.contains("收件") or heading.contains("来信"):
		return &"mail"
	if heading.contains("图鉴") or heading.contains("名片"):
		return &"album"
	return &"compass"


func _flat_icon(icon_name: StringName, color: Color, icon_size: Vector2) -> Control:
	var icon: Control = FLAT_ICON.new()
	icon.set("icon_name", icon_name)
	icon.set("icon_color", color)
	icon.set("soft_color", Color("#dfd9f4"))
	icon.custom_minimum_size = icon_size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_album_signature(album: Dictionary) -> String:
	var keys: Array = album.keys()
	keys.sort()
	var parts: Array[String] = []
	for template_id in keys:
		var entry: Dictionary = album[template_id]
		parts.append("%s:%d" % [str(template_id), int(entry.get("received_count", 1))])
	return ",".join(parts)


func _add_section_note(text_value: String) -> void:
	var label := _label(text_value, Rect2(), 14, MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, 30)
	_rows.add_child(label)


func _add_wrapped_text(text_value: String, font_size: int) -> void:
	var label := _label(text_value, Rect2(), font_size, INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, 80)
	_rows.add_child(label)


func _add_postcard_image(destination_id: String) -> void:
	var texture_rect := _make_postcard_texture(destination_id, Vector2(560, 265))
	texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_rows.add_child(texture_rect)


func _make_postcard_texture(destination_id: String, size: Vector2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = size
	texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var art_path: String = _services.catalog.get_art(destination_id)
	if not art_path.is_empty() and ResourceLoader.exists(art_path):
		texture_rect.texture = load(art_path)
	return texture_rect


func _effect_description(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["hunger", "energy", "mood", "friendship_xp"]:
		var amount := int(effects.get(key, 0))
		if amount <= 0:
			continue
		var name: String = {"hunger": "饱腹", "energy": "电量", "mood": "心情", "friendship_xp": "亲密经验"}[key]
		parts.append("%s +%d" % [name, amount])
	return " / ".join(parts) if not parts.is_empty() else "旅行纪念品 · 可收藏"


func _bundle_description(bundle: Dictionary) -> String:
	var parts: Array[String] = []
	var stars := int(bundle.get("stars", 0))
	var xp := int(bundle.get("friendship_xp", 0))
	if stars > 0:
		parts.append("✦ %d" % stars)
	if xp > 0:
		parts.append("经验 +%d" % xp)
	for item_id in bundle.get("items", {}):
		var item: Dictionary = _services.catalog.get_item(str(item_id))
		parts.append("%s ×%d" % [str(item.get("name", item_id)), int(bundle.items[item_id])])
	return "　·　".join(parts) if not parts.is_empty() else "没有附件"


func _format_duration(seconds: float) -> String:
	var total_minutes := int(ceil(seconds / 60.0))
	if total_minutes < 60:
		return "%d 分钟" % total_minutes
	var hours := int(total_minutes / 60)
	var minutes := total_minutes % 60
	return "%d 小时 %d 分" % [hours, minutes] if minutes > 0 else "%d 小时" % hours


func _clear_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


func _card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#ffffff"), 16, 0.94))
	return panel


func _label(text_value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text_value: String, rect: Rect2, color: Color, text_color: Color, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_stylebox_override("normal", _button_style(color, 13))
	button.add_theme_stylebox_override("hover", _button_style(color.lightened(0.035), 13))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.05), 13))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _icon_button(icon_name: StringName, tooltip: String) -> Button:
	var button := Button.new()
	button.tooltip_text = tooltip
	button.add_theme_stylebox_override("normal", _button_style(PALE_LAVENDER, 18))
	button.add_theme_stylebox_override("hover", _button_style(Color("#e5e0f4"), 18))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#dad3ed"), 18))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_flat_icon(icon_name, Color("#6256ad"), Vector2(34, 34)))
	button.add_child(center)
	return button


func _panel_style(color: Color, radius: int, opacity: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, opacity)
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.9)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _button_style(color: Color, radius: int) -> StyleBoxFlat:
	return _panel_style(color, radius, 1.0)


func _on_state_changed(_snapshot: Dictionary) -> void:
	if not visible:
		return
	set_mail_badges(_services.mailbox.pending_count(), _services.mailbox.unread_count())
	if _page != "travel":
		return
	if _travel_tab == "mailbox":
		var mails: Array = _services.mailbox.get_mails("all")
		var mail_signature := "%d:%d:%d" % [mails.size(), _services.mailbox.pending_count(), _services.mailbox.unread_count()]
		if mail_signature != _mail_signature:
			_mail_signature = mail_signature
			_render(false)
		return
	if _travel_tab == "album":
		var album: Dictionary = _services.store.get_snapshot().get("album", {})
		if _make_album_signature(album) != _album_signature:
			_render(false)
		return
	if _travel_tab != "travel":
		return
	var active: Variant = _services.store.get_snapshot().get("travel", {}).get("active_trip")
	if typeof(active) == TYPE_DICTIONARY:
		var signature := "%s:%s:%d" % [str(active.get("trip_id", "")), str(active.get("state", "")), int(active.get("delivery_cursor", 0))]
		if signature != _travel_signature:
			_render(false)
			return
		if not is_instance_valid(_travel_progress):
			_render(false)
			return
		_travel_progress.max_value = maxf(1.0, float(active.get("total_duration_sec", 1.0)))
		_travel_progress.value = float(active.get("elapsed_sec", 0.0))
	elif is_instance_valid(_travel_progress):
		_render(false)


func _select_shop_item(item_id: String) -> void:
	_selected_shop_item = item_id
	_quantity = 1
	_message.text = ""
	_render(false)


func _request_buy(item_id: String) -> void:
	if _busy:
		return
	var now := Time.get_ticks_msec()
	var signature := "%s:%d" % [item_id, _quantity]
	if signature == _last_buy_signature and now - _last_buy_msec < 500:
		return
	_last_buy_signature = signature
	_last_buy_msec = now
	_busy = true
	command_requested.emit("buy", {
		"item_id": item_id,
		"quantity": _quantity,
		"catalog_version": int(_services.catalog.version),
		"request_id": "shop:%d:%d" % [now, randi()],
	})


func _select_inventory_item(item_id: String) -> void:
	_selected_inventory_item = item_id
	_message.text = ""
	_render(false)


func _prepare_bento_trip() -> void:
	_use_bento = true
	_page = "travel"
	_travel_tab = "travel"
	_selected_mail_id = ""
	_render(true)


func _select_route(route_id: String) -> void:
	_selected_route = route_id
	_message.text = ""
	_render(false)


func _open_mail(mail_id: String) -> void:
	_selected_mail_id = mail_id
	var mail: Dictionary = {}
	for entry in _services.mailbox.get_mails("all"):
		if str(entry.get("mail_id", "")) == mail_id:
			mail = entry
			break
	if not bool(mail.get("read", false)):
		_scroll.scroll_vertical = 0
		command_requested.emit("mark_read", {"mail_id": mail_id})
	else:
		_render(false)


func _select_tab(page: String, tab: String) -> void:
	_message.text = ""
	if page == "shop":
		_page = "shop"
		_shop_category = tab
		_selected_shop_item = ""
	elif page == "inventory":
		_page = "inventory"
		_inventory_category = tab
		_selected_inventory_item = ""
	else:
		_page = "travel"
		_travel_tab = tab
		_selected_mail_id = ""
		if tab == "mailbox":
			_mail_page = 0
	_render(true)


func _go_back() -> void:
	if _page == "travel" and _travel_tab == "mailbox" and not _selected_mail_id.is_empty():
		_selected_mail_id = ""
		_render(false)
		return
	_close()


func handle_back() -> bool:
	if not visible:
		return false
	if _page == "travel" and _travel_tab == "mailbox" and not _selected_mail_id.is_empty():
		_go_back()
	else:
		_close()
	return true


func _fit_design() -> void:
	if _design == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var fit_scale := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	if fit_scale <= 0.0:
		return
	_design_height = maxf(DESIGN_SIZE.y, viewport_size.y / fit_scale)
	_design.scale = Vector2.ONE * fit_scale
	_design.position = Vector2((viewport_size.x - DESIGN_SIZE.x * fit_scale) * 0.5, 0.0)
	_design.size = Vector2(DESIGN_SIZE.x, _design_height)
	_safe_rect = SAFE_LAYOUT.get_safe_rect(_design, _design_height).grow(-18.0)
	if _safe_rect.size.x < 480.0 or _safe_rect.size.y < 700.0:
		_safe_rect = Rect2(Vector2(18.0, 18.0), Vector2(DESIGN_SIZE.x - 36.0, _design_height - 36.0))
	var panel_width := minf(672.0, _safe_rect.size.x - 28.0)
	var panel_height := minf(1160.0, _safe_rect.size.y - 28.0)
	_sheet.size = Vector2(maxf(440.0, panel_width), maxf(640.0, panel_height))
	_sheet.position = _safe_rect.position + (_safe_rect.size - _sheet.size) * 0.5
	_sheet.pivot_offset = _sheet.size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_ESCAPE, KEY_BACKSPACE]:
		handle_back()
		get_viewport().set_input_as_handled()


func _close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_busy = false
	_travel_progress = null
	var exit_tween := create_tween()
	exit_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	exit_tween.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		_closing = false
		closed.emit()
	)


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_close()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close()
