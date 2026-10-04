extends RefCounted

const MAX_PENDING_MAIL := 200

var _store: RefCounted
var _catalog: RefCounted
var _reward_service: RefCounted


func setup(store: RefCounted, catalog: RefCounted, reward_service: RefCounted) -> void:
	_store = store
	_catalog = catalog
	_reward_service = reward_service


func get_snapshot() -> Dictionary:
	return _store.get_snapshot().get("travel", {}).duplicate(true)


func begin_tutorial(request_id: String) -> Dictionary:
	return _store.transact("travel_tutorial_depart", request_id, func(draft: Dictionary) -> Dictionary:
		if draft.travel.active_trip != null:
			return {"ok": false, "code": "TRIP_ALREADY_ACTIVE", "message": "西小电还在旅途中。"}
		if bool(draft.flags.get("tutorial_trip_started", false)):
			return {"ok": false, "code": "TUTORIAL_ALREADY_STARTED", "message": "快速引导旅程已经体验过了。"}
		if _pending_count(draft.mailbox) >= MAX_PENDING_MAIL:
			return {"ok": false, "code": "MAILBOX_FULL", "message": "先收好邮袋里的附件，再安排出行。"}
		var config: Dictionary = _catalog.progression.get("tutorial_trip", {})
		var sequence := int(draft.travel.next_trip_sequence)
		var trip_id := "trip_%06d" % sequence
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var start_unix := int(Time.get_unix_time_from_system())
		var elapsed := 0
		var events: Array = []
		for i in range(config.get("postcards", []).size()):
			var postcard: Dictionary = config.postcards[i]
			elapsed += rng.randi_range(int(config.min_segment_seconds), int(config.max_segment_seconds))
			var card: Dictionary = _catalog.get_card(str(postcard.template_id))
			if card.is_empty():
				return {"ok": false, "code": "INVALID_CATALOG", "message": "引导名片配置缺失。"}
			events.append({
				"event_id": "%s:postcard:%d" % [trip_id, i + 1],
				"kind": "postcard",
				"due_offset_sec": elapsed,
				"template_id": str(card.id),
				"destination_id": str(card.destination_id),
				"rarity": str(card.rarity),
				"text": str(card.text),
				"reward_bundle": postcard.get("bundle", {}).duplicate(true),
			})
		elapsed += rng.randi_range(int(config.min_segment_seconds), int(config.max_segment_seconds))
		events.append({
			"event_id": "%s:return" % trip_id,
			"kind": "return",
			"due_offset_sec": elapsed,
			"text": str(config.get("return_text", "西小电回来啦！")),
			"reward_bundle": config.get("return_bundle", {}).duplicate(true),
		})
		var trip := _make_trip(trip_id, "nearby_tutorial", true, "", start_unix, elapsed, events, str(rng.seed))
		draft.travel.active_trip = trip
		draft.travel.next_trip_sequence = sequence + 1
		draft.flags.tutorial_trip_started = true
		return {"ok": true, "code": "OK", "actual_changes": {"trip_id": trip_id, "total_duration_sec": elapsed}}
	)


func depart(route_id: String, supply_item_id: String, request_id: String) -> Dictionary:
	var route: Dictionary = _catalog.get_route(route_id)
	if route.is_empty():
		return _error("INVALID_ROUTE", request_id, "没有找到这条路线。")
	if not supply_item_id.is_empty() and supply_item_id != "picnic_bento":
		return _error("INVALID_ITEM", request_id, "目前只有野餐便当可以作为出行准备。")
	return _store.transact("travel_depart", request_id, func(draft: Dictionary) -> Dictionary:
		if draft.travel.active_trip != null:
			return {"ok": false, "code": "TRIP_ALREADY_ACTIVE", "message": "西小电还在旅途中。"}
		if _pending_count(draft.mailbox) >= MAX_PENDING_MAIL:
			return {"ok": false, "code": "MAILBOX_FULL", "message": "先收好邮袋里的附件，再安排出行。"}
		if not supply_item_id.is_empty() and int(draft.inventory.get(supply_item_id, 0)) < 1:
			return {"ok": false, "code": "NOT_ENOUGH_ITEMS", "message": "背包里已经没有野餐便当了。"}
		var sequence := int(draft.travel.next_trip_sequence)
		if sequence >= 1_000_000_000:
			return {"ok": false, "code": "COUNTER_LIMIT", "message": "旅程记录达到上限。"}
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var seed_text := str(rng.seed)
		var start_unix := int(Time.get_unix_time_from_system())
		var trip_id := "trip_%06d" % sequence
		var trip := _build_standard_trip(draft, route, trip_id, supply_item_id, start_unix, rng, seed_text)
		if trip.is_empty():
			return {"ok": false, "code": "INVALID_CATALOG", "message": "路线名片配置不完整，暂时无法出发。"}
		if not supply_item_id.is_empty():
			draft.inventory[supply_item_id] = int(draft.inventory[supply_item_id]) - 1
			if int(draft.inventory[supply_item_id]) == 0:
				draft.inventory.erase(supply_item_id)
		draft.travel.active_trip = trip
		draft.travel.next_trip_sequence = sequence + 1
		return {"ok": true, "code": "OK", "actual_changes": {"trip_id": trip_id, "route_id": route_id, "supply_item_id": supply_item_id, "total_duration_sec": trip.total_duration_sec}}
	)


func reconcile() -> Dictionary:
	var snapshot: Dictionary = _store.get_snapshot()
	var active: Variant = snapshot.get("travel", {}).get("active_trip")
	if typeof(active) != TYPE_DICTIONARY or str(active.get("state", "")) != "TRAVELLING":
		return {"ok": true, "code": "NO_DUE_EVENTS", "actual_changes": {"mail_count": 0}}
	var elapsed := float(active.get("elapsed_sec", 0.0))
	var cursor := int(active.get("delivery_cursor", 0))
	var events: Array = active.get("events", [])
	var due_count := 0
	for i in range(cursor, events.size()):
		if float(events[i].get("due_offset_sec", INF)) > elapsed:
			break
		due_count += 1
	if due_count == 0:
		return {"ok": true, "code": "NO_DUE_EVENTS", "actual_changes": {"mail_count": 0}}
	var trip_id := str(active.trip_id)
	return _store.transact("travel_reconcile", "travel_reconcile:%s:%d" % [trip_id, cursor], func(draft: Dictionary) -> Dictionary:
		var trip: Variant = draft.travel.get("active_trip")
		if typeof(trip) != TYPE_DICTIONARY or str(trip.get("trip_id", "")) != trip_id or str(trip.get("state", "")) != "TRAVELLING":
			return {"ok": true, "code": "ALREADY_RECONCILED", "actual_changes": {"mail_count": 0}}
		var added := 0
		var next_cursor := int(trip.delivery_cursor)
		var now_unix := int(Time.get_unix_time_from_system())
		while next_cursor < trip.events.size():
			var event: Dictionary = trip.events[next_cursor]
			if float(event.due_offset_sec) > float(trip.elapsed_sec):
				break
			var mail := _event_to_mail(trip, event, now_unix)
			if _mail_exists(draft.mailbox, str(mail.mail_id)):
				# A prior recovery may have committed the message before an older cursor snapshot.
				trip.delivery_cursor = next_cursor + 1
				next_cursor += 1
				continue
			draft.mailbox.append(mail)
			added += 1
			if str(event.kind) == "postcard":
				_add_to_album(draft, trip, event, now_unix)
				_create_collection_mails(draft, trip_id, now_unix)
			else:
				trip.state = "RETURNED"
				trip.returned_unix = now_unix
				var history: Array = draft.travel.get("recent_history", [])
				history.append({"trip_id": trip_id, "route_id": str(trip.route_id), "returned_unix": now_unix, "postcard_count": int(trip.delivery_cursor)})
				while history.size() > int(_catalog.progression.get("trip_history_limit", 20)):
					history.pop_front()
				draft.travel.recent_history = history
			trip.delivery_cursor = next_cursor + 1
			next_cursor += 1
		return {"ok": true, "code": "OK", "actual_changes": {"mail_count": added, "trip_id": trip_id, "state": str(trip.state)}}
	)


func acknowledge_return(request_id: String) -> Dictionary:
	return _store.transact("travel_acknowledge_return", request_id, func(draft: Dictionary) -> Dictionary:
		var active: Variant = draft.travel.get("active_trip")
		if typeof(active) != TYPE_DICTIONARY or str(active.get("state", "")) != "RETURNED":
			return {"ok": false, "code": "NOT_RETURNED", "message": "西小电还没有回来。"}
		var trip_id := str(active.trip_id)
		draft.travel.active_trip = null
		return {"ok": true, "code": "OK", "actual_changes": {"trip_id": trip_id, "acknowledged": true}}
	)


func _build_standard_trip(draft: Dictionary, route: Dictionary, trip_id: String, supply_item_id: String, start_unix: int, rng: RandomNumberGenerator, seed_text: String) -> Dictionary:
	var count := int(route.postcard_count)
	var destinations: Array = route.destinations.duplicate()
	var destination_cycle: Array = []
	var previous_destination := ""
	var used_templates: Dictionary = {}
	var events: Array = []
	var elapsed := 0
	var has_bento := supply_item_id == "picnic_bento"
	for index in range(count):
		if destination_cycle.is_empty():
			destination_cycle = destinations.duplicate()
			_shuffle_with_rng(destination_cycle, rng)
			if destination_cycle.size() > 1 and str(destination_cycle[0]) == previous_destination:
				for swap_index in range(1, destination_cycle.size()):
					if str(destination_cycle[swap_index]) != previous_destination:
						var swap_value = destination_cycle[0]
						destination_cycle[0] = destination_cycle[swap_index]
						destination_cycle[swap_index] = swap_value
						break
		var destination_id := str(destination_cycle.pop_front())
		previous_destination = destination_id
		var chance := float(_catalog.progression.get("rare_base_probability", 0.10))
		if has_bento and index == 0:
			chance = float(_catalog.progression.get("rare_with_bento_probability", 0.20))
		var pity := int(_catalog.progression.get("rare_guarantee_after_misses", 7))
		var is_rare := int(draft.travel.rare_miss_streak) >= pity or rng.randf() < chance
		var rarity := "rare" if is_rare else "common"
		var card := _choose_postcard(destinations, destination_id, rarity, used_templates, rng)
		if card.is_empty():
			return {}
		destination_id = str(card.get("destination_id", destination_id))
		used_templates[str(card.id)] = true
		if is_rare:
			draft.travel.rare_miss_streak = 0
		else:
			draft.travel.rare_miss_streak = int(draft.travel.rare_miss_streak) + 1
		elapsed += rng.randi_range(int(route.leg_min_seconds), int(route.leg_max_seconds))
		var bundle := {"stars": rng.randi_range(int(route.postcard_stars_min), int(route.postcard_stars_max)), "friendship_xp": 0, "items": {}}
		if rng.randf() < float(_catalog.rewards.get("base_item_drop_probability", 0.35)):
			_add_bundle_item(bundle, _draw_base_item(rng), 1)
		if rng.randf() < float(_catalog.rewards.get("souvenir_drop_probability", 0.20)):
			var souvenir_id := str(_catalog.rewards.get("souvenirs_by_destination", {}).get(destination_id, ""))
			if not souvenir_id.is_empty():
				_add_bundle_item(bundle, souvenir_id, 1)
		events.append({
			"event_id": "%s:postcard:%d" % [trip_id, index + 1],
			"kind": "postcard",
			"due_offset_sec": elapsed,
			"template_id": str(card.id),
			"destination_id": destination_id,
			"rarity": rarity,
			"text": str(card.text),
			"reward_bundle": bundle,
		})

	var return_leg := rng.randi_range(int(route.leg_min_seconds), int(route.leg_max_seconds))
	var return_bundle := {"stars": rng.randi_range(int(route.return_stars_min), int(route.return_stars_max)), "friendship_xp": int(route.return_xp), "items": {}}
	var base_item_count := int(route.return_base_items) + (1 if has_bento else 0)
	for _item_index in range(base_item_count):
		_add_bundle_item(return_bundle, _draw_base_item(rng), 1)
	elapsed += return_leg
	events.append({
		"event_id": "%s:return" % trip_id,
		"kind": "return",
		"due_offset_sec": elapsed,
		"text": "旅途结束啦！西小电带回了沿途的故事和小礼物。",
		"reward_bundle": return_bundle,
	})
	return _make_trip(trip_id, str(route.id), false, supply_item_id, start_unix, elapsed, events, seed_text)


func _make_trip(trip_id: String, route_id: String, tutorial: bool, supply_item_id: String, start_unix: int, total_seconds: int, events: Array, seed_text: String) -> Dictionary:
	return {
		"trip_id": trip_id,
		"route_id": route_id,
		"is_tutorial": tutorial,
		"content_version": int(_catalog.progression.get("content_version", 1)),
		"seed_string": seed_text,
		"departed_unix": start_unix,
		"supply_item_id": supply_item_id,
		"state": "TRAVELLING",
		"elapsed_sec": 0.0,
		"clock_checkpoint_unix": start_unix,
		"total_duration_sec": total_seconds,
		"delivery_cursor": 0,
		"events": events,
	}


func _choose_postcard(destinations: Array, selected_destination: String, rarity: String, used: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var candidates: Array = _catalog.get_cards_for(selected_destination, rarity)
	var unused: Array = []
	for card in candidates:
		if not used.has(str(card.id)):
			unused.append(card)
	if not unused.is_empty():
		return unused[rng.randi_range(0, unused.size() - 1)]
	var fallback: Array = []
	for destination_id in destinations:
		var route_cards: Array = _catalog.get_cards_for(str(destination_id), rarity)
		for card in route_cards:
			if not used.has(str(card.id)):
				fallback.append(card)
	if not fallback.is_empty():
		return fallback[rng.randi_range(0, fallback.size() - 1)]
	if not candidates.is_empty():
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	return {}


func _draw_base_item(rng: RandomNumberGenerator) -> String:
	var entries: Array = _catalog.rewards.base_items
	var total_weight := 0
	for entry in entries:
		total_weight += int(entry.weight)
	var draw := rng.randi_range(1, maxi(1, total_weight))
	for entry in entries:
		draw -= int(entry.weight)
		if draw <= 0:
			return str(entry.id)
	return str(entries.back().id) if not entries.is_empty() else "rice_ball"


func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value = values[index]
		values[index] = values[other]
		values[other] = value


func _add_bundle_item(bundle: Dictionary, item_id: String, amount: int) -> void:
	var items: Dictionary = bundle.get("items", {})
	items[item_id] = int(items.get(item_id, 0)) + amount
	bundle.items = items


func _event_to_mail(trip: Dictionary, event: Dictionary, received_unix: int) -> Dictionary:
	var is_postcard := str(event.kind) == "postcard"
	return {
		"mail_id": str(event.event_id),
		"trip_id": str(trip.trip_id),
		"kind": str(event.kind),
		"title": ("西小电寄来一张名片" if is_postcard else "西小电平安归来"),
		"template_id": str(event.get("template_id", "")),
		"destination_id": str(event.get("destination_id", "")),
		"rarity": str(event.get("rarity", "common")),
		"text": str(event.get("text", "")),
		"reward_bundle": event.get("reward_bundle", {}).duplicate(true),
		"planned_arrival_unix": int(trip.departed_unix) + int(event.due_offset_sec),
		"received_unix": received_unix,
		"read": false,
		"claimed": false,
	}


func _add_to_album(draft: Dictionary, trip: Dictionary, event: Dictionary, received_unix: int) -> void:
	var template_id := str(event.get("template_id", ""))
	if template_id.is_empty():
		return
	var album: Dictionary = draft.album
	if album.has(template_id):
		var entry: Dictionary = album[template_id]
		entry.last_received_unix = received_unix
		entry.received_count = int(entry.get("received_count", 1)) + 1
	else:
		album[template_id] = {
			"template_id": template_id,
			"trip_id": str(trip.trip_id),
			"destination_id": str(event.destination_id),
			"rarity": str(event.rarity),
			"text": str(event.text),
			"first_received_unix": received_unix,
			"last_received_unix": received_unix,
			"received_count": 1,
		}
	draft.album = album


func _create_collection_mails(draft: Dictionary, trip_id: String, now_unix: int) -> void:
	var thresholds: Array = _catalog.progression.get("collection_rewards", [])
	var count: int = draft.album.size()
	var generated: Array = draft.flags.get("collection_rewards_created", []).duplicate()
	for goal in thresholds:
		var threshold := int(goal.get("threshold", 0))
		var collection_id := "collection:%d" % threshold
		if count < threshold or generated.has(collection_id):
			continue
		generated.append(collection_id)
		draft.mailbox.append({
			"mail_id": collection_id,
			"trip_id": trip_id,
			"kind": "collection",
			"title": "名片收集奖励 · %d 张" % threshold,
			"template_id": "",
			"destination_id": "",
			"rarity": "common",
			"text": "你已经收集了 %d 张不同的旅行名片！" % threshold,
			"reward_bundle": goal.get("bundle", {}).duplicate(true),
			"planned_arrival_unix": now_unix,
			"received_unix": now_unix,
			"read": false,
			"claimed": false,
		})
	draft.flags.collection_rewards_created = generated


func _pending_count(mailbox: Array) -> int:
	var count := 0
	for mail in mailbox:
		if not bool(mail.get("claimed", false)):
			count += 1
	return count


func _mail_exists(mailbox: Array, mail_id: String) -> bool:
	for mail in mailbox:
		if str(mail.get("mail_id", "")) == mail_id:
			return true
	return false


func _error(code: String, request_id: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "request_id": request_id, "message": message, "actual_changes": {}}
