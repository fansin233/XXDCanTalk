extends RefCounted

var _store: RefCounted
var _catalog: RefCounted


func setup(store: RefCounted, catalog: RefCounted) -> void:
	_store = store
	_catalog = catalog


func get_items(category: String = "all") -> Array:
	var snapshot: Dictionary = _store.get_snapshot()
	var result: Array = []
	for item_id in snapshot.get("inventory", {}):
		var count := int(snapshot.inventory[item_id])
		if count <= 0:
			continue
		var item: Dictionary = _catalog.get_item(str(item_id))
		if item.is_empty():
			item = {"id": str(item_id), "name": "旧版道具（%s）" % str(item_id), "category": "legacy", "icon": "?", "sort_order": 9999, "effects": {}, "usable": false}
		if category != "all" and str(item.get("category", "")) != category:
			continue
		item["count"] = count
		result.append(item)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("sort_order", 9999)) == int(b.get("sort_order", 9999)):
			return str(a.get("id", "")) < str(b.get("id", ""))
		return int(a.get("sort_order", 9999)) < int(b.get("sort_order", 9999))
	)
	return result


func preview_use(item_id: String, resting: bool) -> Dictionary:
	var item: Dictionary = _catalog.get_item(item_id)
	if item.is_empty() or str(item.get("category", "")) == "souvenir":
		return {"ok": false, "code": "INVALID_ITEM", "message": "这件物品不能使用。"}
	if _store.get_item_count(item_id) <= 0:
		return {"ok": false, "code": "NOT_ENOUGH_ITEMS", "message": "背包里没有这件物品。"}
	if resting and bool(item.get("requires_awake", false)):
		return {"ok": false, "code": "CHARACTER_RESTING", "message": "先叫醒西小电再使用。"}
	var snapshot: Dictionary = _store.get_snapshot()
	var pet: Dictionary = snapshot.pet
	var effects: Dictionary = item.get("effects", {})
	var actual := {
		"hunger": minf(float(effects.get("hunger", 0)), 100.0 - float(pet.hunger)),
		"energy": minf(float(effects.get("energy", 0)), 100.0 - float(pet.energy)),
		"mood": minf(float(effects.get("mood", 0)), 100.0 - float(pet.mood)),
		"friendship_xp": int(effects.get("friendship_xp", 0)),
	}
	actual.friendship_xp = mini(int(actual.friendship_xp), 1_000_000_000 - int(pet.friendship_xp))
	if actual.hunger <= 0.0 and actual.energy <= 0.0 and actual.mood <= 0.0 and int(actual.friendship_xp) <= 0:
		return {"ok": false, "code": "NO_EFFECT", "message": "当前使用没有效果。", "actual_changes": actual}
	return {"ok": true, "code": "OK", "item": item, "actual_changes": actual}


func use_item(item_id: String, request_id: String, resting: bool) -> Dictionary:
	var item: Dictionary = _catalog.get_item(item_id)
	if item.is_empty() or str(item.get("category", "")) == "souvenir":
		return _error("INVALID_ITEM", request_id, "这件物品不能使用。")
	return _store.transact("inventory_use", request_id, func(draft: Dictionary) -> Dictionary:
		if int(draft.inventory.get(item_id, 0)) < 1:
			return {"ok": false, "code": "NOT_ENOUGH_ITEMS", "message": "背包里没有这件物品。"}
		if resting and bool(item.get("requires_awake", false)):
			return {"ok": false, "code": "CHARACTER_RESTING", "message": "先叫醒西小电再使用。"}
		var effects: Dictionary = item.get("effects", {})
		var actual := {
			"hunger": minf(float(effects.get("hunger", 0)), 100.0 - float(draft.pet.hunger)),
			"energy": minf(float(effects.get("energy", 0)), 100.0 - float(draft.pet.energy)),
			"mood": minf(float(effects.get("mood", 0)), 100.0 - float(draft.pet.mood)),
			"friendship_xp": mini(int(effects.get("friendship_xp", 0)), 1_000_000_000 - int(draft.pet.friendship_xp)),
		}
		if actual.hunger <= 0.0 and actual.energy <= 0.0 and actual.mood <= 0.0 and int(actual.friendship_xp) <= 0:
			return {"ok": false, "code": "NO_EFFECT", "message": "当前使用没有效果。", "actual_changes": actual}
		draft.inventory[item_id] = int(draft.inventory[item_id]) - 1
		if int(draft.inventory[item_id]) == 0:
			draft.inventory.erase(item_id)
		for stat_name in ["hunger", "energy", "mood"]:
			draft.pet[stat_name] = minf(100.0, float(draft.pet[stat_name]) + float(actual[stat_name]))
		draft.pet.friendship_xp = int(draft.pet.friendship_xp) + int(actual.friendship_xp)
		return {"ok": true, "code": "OK", "actual_changes": actual, "item_id": item_id}
	)


func _error(code: String, request_id: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "request_id": request_id, "message": message, "actual_changes": {}}
