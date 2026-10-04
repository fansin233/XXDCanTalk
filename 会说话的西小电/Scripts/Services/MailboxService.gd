extends RefCounted

const MAX_CLAIMED_HISTORY := 100

var _store: RefCounted
var _catalog: RefCounted
var _rewards: RefCounted


func setup(store: RefCounted, catalog: RefCounted, reward_service: RefCounted) -> void:
	_store = store
	_catalog = catalog
	_rewards = reward_service


func get_mails(filter: String = "all") -> Array:
	var mails: Array = _store.get_snapshot().get("mailbox", []).duplicate(true)
	var visible: Array = []
	for mail in mails:
		if filter == "unclaimed" and bool(mail.get("claimed", false)):
			continue
		if filter == "unread" and bool(mail.get("read", false)):
			continue
		visible.append(mail)
	visible.reverse()
	return visible


func pending_count() -> int:
	var count := 0
	for mail in _store.get_snapshot().get("mailbox", []):
		if not bool(mail.get("claimed", false)):
			count += 1
	return count


func unread_count() -> int:
	var count := 0
	for mail in _store.get_snapshot().get("mailbox", []):
		if not bool(mail.get("read", false)):
			count += 1
	return count


func mark_read(mail_id: String, request_id: String = "") -> Dictionary:
	var command_id := request_id if not request_id.is_empty() else _new_id("read")
	return _store.transact("mail_mark_read", command_id, func(draft: Dictionary) -> Dictionary:
		for mail in draft.mailbox:
			if str(mail.get("mail_id", "")) != mail_id:
				continue
			if bool(mail.get("read", false)):
				return {"ok": true, "code": "ALREADY_READ", "actual_changes": {}}
			mail.read = true
			return {"ok": true, "code": "OK", "actual_changes": {"mail_id": mail_id, "read": true}}
		return {"ok": false, "code": "MAIL_NOT_FOUND", "message": "这封信已经不在收件箱里。"}
	)


func claim(mail_id: String, request_id: String) -> Dictionary:
	return _store.transact("mail_claim", request_id, func(draft: Dictionary) -> Dictionary:
		for mail in draft.mailbox:
			if str(mail.get("mail_id", "")) != mail_id:
				continue
			if bool(mail.get("claimed", false)):
				return {"ok": false, "code": "ALREADY_CLAIMED", "message": "这份附件已经收下了。"}
			var applied: Dictionary = _rewards.apply_bundle(draft, mail.get("reward_bundle", {}))
			if not bool(applied.get("ok", false)):
				return applied
			mail.claimed = true
			mail.read = true
			_archive_old_claimed(draft)
			return {"ok": true, "code": "OK", "actual_changes": applied.actual_changes, "mail_id": mail_id}
		return {"ok": false, "code": "MAIL_NOT_FOUND", "message": "这封信已经不在收件箱里。"}
	)


func claim_all(request_id: String) -> Dictionary:
	return _store.transact("mail_claim_all", request_id, func(draft: Dictionary) -> Dictionary:
		var total := {"stars": 0, "friendship_xp": 0, "items": {}}
		var claimed_ids: Array[String] = []
		for mail in draft.mailbox:
			if bool(mail.get("claimed", false)):
				continue
			var bundle: Dictionary = mail.get("reward_bundle", {})
			var next_stars := int(total.stars) + int(bundle.get("stars", 0))
			var next_xp := int(total.friendship_xp) + int(bundle.get("friendship_xp", 0))
			if next_stars > 1_000_000_000 or next_xp > 1_000_000_000:
				return {"ok": false, "code": "COUNTER_LIMIT", "message": "资源数量达到上限，附件仍会保留。"}
			total.stars = next_stars
			total.friendship_xp = next_xp
			for item_id in bundle.get("items", {}):
				var item_counts: Dictionary = total.items
				item_counts[str(item_id)] = int(item_counts.get(str(item_id), 0)) + int(bundle.items[item_id])
			total.items = total.items
			mail.claimed = true
			mail.read = true
			claimed_ids.append(str(mail.mail_id))
		if claimed_ids.is_empty():
			return {"ok": true, "code": "NOTHING_TO_CLAIM", "actual_changes": {"stars": 0, "friendship_xp": 0, "items": {}}}
		var applied: Dictionary = _rewards.apply_bundle(draft, total)
		if not bool(applied.get("ok", false)):
			return applied
		_archive_old_claimed(draft)
		return {"ok": true, "code": "OK", "actual_changes": applied.actual_changes, "mail_ids": claimed_ids}
	)


func _archive_old_claimed(draft: Dictionary) -> void:
	var mailbox: Array = draft.mailbox
	var completed: Array = []
	for index in range(mailbox.size()):
		var mail: Dictionary = mailbox[index]
		if bool(mail.get("read", false)) and bool(mail.get("claimed", false)):
			completed.append(index)
	var excess := completed.size() - MAX_CLAIMED_HISTORY
	if excess <= 0:
		return
	var remove_ids: Dictionary = {}
	for i in range(excess):
		var mail: Dictionary = mailbox[completed[i]]
		remove_ids[str(mail.mail_id)] = true
	var retained: Array = []
	for mail in mailbox:
		if not remove_ids.has(str(mail.get("mail_id", ""))):
			retained.append(mail)
	draft.mailbox = retained


func _new_id(prefix: String) -> String:
	return "%s:%d" % [prefix, Time.get_ticks_usec()]
