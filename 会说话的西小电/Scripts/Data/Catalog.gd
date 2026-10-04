extends RefCounted

const DATA_FILES := {
	"items": "res://Data/items.json",
	"routes": "res://Data/travel_routes.json",
	"rewards": "res://Data/reward_tables.json",
	"progression": "res://Data/progression.json",
	"postcards": "res://Data/postcards.json",
	"art": "res://Data/art_map.json",
}

var version := 0
var items: Dictionary = {}
var routes: Dictionary = {}
var postcards: Dictionary = {}
var cards_by_destination: Dictionary = {}
var rewards: Dictionary = {}
var progression: Dictionary = {}
var destination_art: Dictionary = {}


func load_catalog() -> Dictionary:
	var loaded: Dictionary = {}
	for key in DATA_FILES:
		var file := FileAccess.open(str(DATA_FILES[key]), FileAccess.READ)
		if file == null:
			return {"ok": false, "error": "无法读取配置：%s" % DATA_FILES[key]}
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		file.close()
		if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
			return {"ok": false, "error": "配置格式错误：%s" % DATA_FILES[key]}
		loaded[key] = parser.data

	version = int(loaded["items"].get("catalog_version", 0))
	if version < 1:
		return {"ok": false, "error": "物品配置版本无效。"}
	for raw_item in loaded["items"].get("items", []):
		if typeof(raw_item) != TYPE_DICTIONARY:
			return {"ok": false, "error": "物品配置包含无效条目。"}
		var item: Dictionary = raw_item
		var item_id := str(item.get("id", ""))
		if item_id.is_empty() or items.has(item_id):
			return {"ok": false, "error": "物品 ID 为空或重复：%s" % item_id}
		if not _valid_nonnegative_int(item.get("price", -1)):
			return {"ok": false, "error": "物品价格无效：%s" % item_id}
		if typeof(item.get("effects")) != TYPE_DICTIONARY:
			return {"ok": false, "error": "物品效果无效：%s" % item_id}
		for effect_key in item.effects:
			if str(effect_key) not in ["hunger", "energy", "mood", "friendship_xp"] or not _valid_nonnegative_int(item.effects[effect_key]):
				return {"ok": false, "error": "物品效果数值无效：%s" % item_id}
		items[item_id] = item.duplicate(true)

	for raw_route in loaded["routes"].get("routes", []):
		if typeof(raw_route) != TYPE_DICTIONARY:
			return {"ok": false, "error": "路线配置包含无效条目。"}
		var route: Dictionary = raw_route
		var route_id := str(route.get("id", ""))
		if route_id.is_empty() or routes.has(route_id):
			return {"ok": false, "error": "路线 ID 为空或重复：%s" % route_id}
		if int(route.get("leg_min_seconds", 0)) <= 0 or int(route.get("leg_max_seconds", 0)) < int(route.get("leg_min_seconds", 0)):
			return {"ok": false, "error": "路线时长范围无效：%s" % route_id}
		if int(route.get("postcard_count", 0)) < 1 or typeof(route.get("destinations")) != TYPE_ARRAY:
			return {"ok": false, "error": "路线目的地配置无效：%s" % route_id}
		routes[route_id] = route.duplicate(true)

	for raw_card in loaded["postcards"].get("postcards", []):
		if typeof(raw_card) != TYPE_DICTIONARY:
			return {"ok": false, "error": "名片配置包含无效条目。"}
		var card: Dictionary = raw_card
		var card_id := str(card.get("id", ""))
		var destination_id := str(card.get("destination_id", ""))
		if card_id.is_empty() or postcards.has(card_id) or destination_id.is_empty():
			return {"ok": false, "error": "名片 ID 为空、重复或缺少地点：%s" % card_id}
		if str(card.get("rarity", "")) not in ["common", "rare"] or str(card.get("text", "")).is_empty():
			return {"ok": false, "error": "名片内容或稀有度无效：%s" % card_id}
		postcards[card_id] = card.duplicate(true)
		if not cards_by_destination.has(destination_id):
			cards_by_destination[destination_id] = []
		cards_by_destination[destination_id].append(card.duplicate(true))

	rewards = loaded["rewards"]
	progression = loaded["progression"]
	destination_art = loaded["art"].get("destination_art", {})
	if typeof(rewards.get("base_items")) != TYPE_ARRAY or typeof(progression.get("collection_rewards")) != TYPE_ARRAY:
		return {"ok": false, "error": "奖励或成长配置无效。"}
	for probability_key in ["base_item_drop_probability", "souvenir_drop_probability"]:
		var probability := float(rewards.get(probability_key, -1.0))
		if not is_finite(probability) or probability < 0.0 or probability > 1.0:
			return {"ok": false, "error": "奖励概率无效：%s" % probability_key}
	for probability_key in ["rare_base_probability", "rare_with_bento_probability"]:
		var rare_probability := float(progression.get(probability_key, -1.0))
		if not is_finite(rare_probability) or rare_probability < 0.0 or rare_probability > 1.0:
			return {"ok": false, "error": "稀有名片概率无效：%s" % probability_key}
	if int(progression.get("rare_guarantee_after_misses", 0)) < 0:
		return {"ok": false, "error": "稀有名片保底值无效。"}
	if typeof(destination_art) != TYPE_DICTIONARY:
		return {"ok": false, "error": "名片插图配置无效。"}
	for route_id in routes:
		for destination_id in routes[route_id].destinations:
			if not cards_by_destination.has(destination_id) or not destination_art.has(destination_id):
				return {"ok": false, "error": "路线引用了缺少名片或插图的地点：%s" % destination_id}
	for postcard_id in postcards:
		if not destination_art.has(str(postcards[postcard_id].get("destination_id", ""))):
			return {"ok": false, "error": "名片地点缺少插图：%s" % postcard_id}
	for weighted_item in rewards.base_items:
		if not items.has(str(weighted_item.get("id", ""))) or int(weighted_item.get("weight", 0)) <= 0:
			return {"ok": false, "error": "基础物品奖励池引用无效。"}
	for destination_id in rewards.get("souvenirs_by_destination", {}):
		var souvenir_id := str(rewards.souvenirs_by_destination[destination_id])
		if not items.has(souvenir_id) or str(items[souvenir_id].get("category", "")) != "souvenir":
			return {"ok": false, "error": "纪念品奖励引用无效：%s" % destination_id}
	for item_id in progression.get("welcome_pack", {}).get("items", {}):
		if not items.has(str(item_id)):
			return {"ok": false, "error": "首次礼包引用了未知道具：%s" % str(item_id)}
	for goal in progression.get("collection_rewards", []):
		if not _valid_bundle(goal.get("bundle", {})):
			return {"ok": false, "error": "名片收集奖励格式无效。"}
		for item_id in goal.bundle.get("items", {}):
			if not items.has(str(item_id)):
				return {"ok": false, "error": "名片收集奖励引用了未知道具：%s" % str(item_id)}
	var tutorial: Dictionary = progression.get("tutorial_trip", {})
	for postcard in tutorial.get("postcards", []):
		if not postcards.has(str(postcard.get("template_id", ""))) or not _valid_bundle(postcard.get("bundle", {})):
			return {"ok": false, "error": "快速引导名片配置无效。"}
	if not _valid_bundle(tutorial.get("return_bundle", {})):
		return {"ok": false, "error": "快速引导归来奖励无效。"}
	return {"ok": true, "error": ""}


func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {}).duplicate(true)


func get_route(route_id: String) -> Dictionary:
	return routes.get(route_id, {}).duplicate(true)


func get_routes() -> Array:
	var result: Array = []
	for route_id in routes:
		result.append(routes[route_id].duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("sort_order", 0)) == int(b.get("sort_order", 0)):
			return str(a.get("id", "")) < str(b.get("id", ""))
		return int(a.get("sort_order", 0)) < int(b.get("sort_order", 0))
	)
	return result


func get_card(card_id: String) -> Dictionary:
	return postcards.get(card_id, {}).duplicate(true)


func get_cards_for(destination_id: String, rarity: String) -> Array:
	var result: Array = []
	for card in cards_by_destination.get(destination_id, []):
		if str(card.rarity) == rarity:
			result.append(card.duplicate(true))
	return result


func get_art(destination_id: String) -> String:
	return str(destination_art.get(destination_id, ""))


func _valid_nonnegative_int(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and floorf(number) == number and number <= 1_000_000_000.0


func _valid_bundle(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var bundle: Dictionary = value
	if not _valid_nonnegative_int(bundle.get("stars", 0)) or not _valid_nonnegative_int(bundle.get("friendship_xp", 0)):
		return false
	if typeof(bundle.get("items", {})) != TYPE_DICTIONARY:
		return false
	for item_id in bundle.get("items", {}):
		if not _valid_nonnegative_int(bundle.items[item_id]):
			return false
	return true
