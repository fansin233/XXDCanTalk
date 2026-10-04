extends RefCounted

var _store: RefCounted
var _catalog: RefCounted


func setup(store: RefCounted, catalog: RefCounted) -> void:
	_store = store
	_catalog = catalog


func get_offers() -> Array:
	var result: Array = []
	for item_id in _catalog.items:
		var item: Dictionary = _catalog.items[item_id]
		if str(item.get("category", "")) == "souvenir" or not bool(item.get("enabled", true)):
			continue
		var offer := item.duplicate(true)
		offer["owned"] = _store.get_item_count(str(item_id))
		result.append(offer)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("sort_order", 0)) == int(b.get("sort_order", 0)):
			return str(a.id) < str(b.id)
		return int(a.sort_order) < int(b.sort_order)
	)
	return result


func buy(item_id: String, quantity: Variant, catalog_version: int, request_id: String) -> Dictionary:
	if typeof(quantity) != TYPE_INT or int(quantity) < 1 or int(quantity) > 99:
		return _error("INVALID_QUANTITY", request_id, "请选择 1–99 件。")
	if catalog_version != int(_catalog.version):
		return _error("CATALOG_CHANGED", request_id, "商品信息已更新，请重新确认。")
	var item: Dictionary = _catalog.get_item(item_id)
	if item.is_empty() or str(item.get("category", "")) == "souvenir" or not bool(item.get("enabled", true)):
		return _error("INVALID_ITEM", request_id, "这个商品暂时无法购买。")
	var count := int(quantity)
	var price := int(item.price)
	var total := price * count
	return _store.transact("shop_buy", request_id, func(draft: Dictionary) -> Dictionary:
		if int(draft.wallet.stars) < total:
			return {"ok": false, "code": "INSUFFICIENT_STARS", "message": "星星不足，还差 %d 颗。" % (total - int(draft.wallet.stars))}
		var current := int(draft.inventory.get(item_id, 0))
		if current + count > 1_000_000_000:
			return {"ok": false, "code": "COUNTER_LIMIT", "message": "背包数量已达到上限。"}
		draft.wallet.stars = int(draft.wallet.stars) - total
		draft.inventory[item_id] = current + count
		return {"ok": true, "code": "OK", "actual_changes": {"stars": -total, "items": {item_id: count}, "unit_price": price, "quantity": count}}
	)


func _error(code: String, request_id: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "request_id": request_id, "message": message, "actual_changes": {}}
