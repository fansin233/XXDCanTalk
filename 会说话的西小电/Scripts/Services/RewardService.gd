extends RefCounted

const MAX_COUNTER := 1_000_000_000


func apply_bundle(draft: Dictionary, bundle: Dictionary) -> Dictionary:
	var stars := int(bundle.get("stars", 0))
	var xp := int(bundle.get("friendship_xp", 0))
	var item_counts: Variant = bundle.get("items", {})
	if stars < 0 or xp < 0 or typeof(item_counts) != TYPE_DICTIONARY:
		return {"ok": false, "code": "INVALID_REWARD", "message": "奖励内容无效。"}
	if int(draft.wallet.stars) + stars > MAX_COUNTER or int(draft.pet.friendship_xp) + xp > MAX_COUNTER:
		return {"ok": false, "code": "COUNTER_LIMIT", "message": "资源数量达到存档上限，无法领取。"}
	var item_changes: Dictionary = {}
	for item_id in item_counts:
		var count_variant: Variant = item_counts[item_id]
		var count_type: int = typeof(count_variant)
		if count_type != TYPE_INT and count_type != TYPE_FLOAT:
			return {"ok": false, "code": "INVALID_REWARD", "message": "奖励物品数量无效。"}
		var count_number: float = float(count_variant)
		if not is_finite(count_number) or count_number < 0.0 or count_number > float(MAX_COUNTER) or floorf(count_number) != count_number:
			return {"ok": false, "code": "INVALID_REWARD", "message": "奖励物品数量无效。"}
		var count: int = int(count_number)
		var current := int(draft.inventory.get(str(item_id), 0))
		if current + count > MAX_COUNTER:
			return {"ok": false, "code": "COUNTER_LIMIT", "message": "物品数量达到存档上限，无法领取。"}
		if count > 0:
			item_changes[str(item_id)] = count

	draft.wallet.stars = int(draft.wallet.stars) + stars
	draft.pet.friendship_xp = int(draft.pet.friendship_xp) + xp
	for item_id in item_changes:
		draft.inventory[item_id] = int(draft.inventory.get(item_id, 0)) + int(item_changes[item_id])
	return {"ok": true, "actual_changes": {"stars": stars, "friendship_xp": xp, "items": item_changes}}
