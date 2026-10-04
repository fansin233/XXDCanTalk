extends RefCounted

const SAVE_PATH := "user://pet_save.json"
const TEMP_PATH := "user://pet_save.tmp"
const BACKUP_PATH := "user://pet_save.bak"
const PRE_V2_PATH := "user://pet_save.pre_v2.json"
const CORRUPT_PREFIX := "user://pet_save.corrupt."
const CURRENT_SCHEMA := 2

const MAX_COUNTER := 1_000_000_000
const MAX_UNIX_TIME := 10_000_000_000


func load_latest() -> Dictionary:
	var candidates: Array[Dictionary] = []
	var any_file := false
	for path in [SAVE_PATH, TEMP_PATH, BACKUP_PATH]:
		if not FileAccess.file_exists(path):
			continue
		any_file = true
		var candidate := _read_candidate(path)
		if bool(candidate.get("valid", false)):
			candidate["priority"] = 3 if path == SAVE_PATH else (2 if path == TEMP_PATH else 1)
			candidates.append(candidate)
		elif int(candidate.get("schema_version", 0)) > CURRENT_SCHEMA:
			return {
				"ok": false,
				"error": "未来版本存档，需要较新版本的游戏才能读取。",
			}

	if candidates.is_empty():
		if any_file:
			return {"ok": false, "error": "存档文件存在，但都无法安全读取。"}
		return {"ok": true, "is_new": true, "path": "", "snapshot": _new_snapshot()}

	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.revision) == int(b.revision):
				return int(a.priority) > int(b.priority)
			return int(a.revision) > int(b.revision)
	)
	var chosen: Dictionary = candidates[0]
	if int(chosen.schema_version) == 1:
		var source_path := str(chosen.path)
		if not FileAccess.file_exists(PRE_V2_PATH):
			var preserve_error := DirAccess.copy_absolute(
				ProjectSettings.globalize_path(source_path),
				ProjectSettings.globalize_path(PRE_V2_PATH)
			)
			if preserve_error != OK:
				return {"ok": false, "error": "无法保留升级前的存档副本。"}
		chosen["snapshot"] = migrate_v1(chosen.snapshot)
		chosen["migration_required"] = true
	else:
		chosen["migration_required"] = false
	chosen["ok"] = true
	chosen["is_new"] = false
	return chosen


func migrate_v1(old: Dictionary) -> Dictionary:
	var today := Time.get_date_string_from_system()
	return {
		"schema_version": CURRENT_SCHEMA,
		"save_revision": 0,
		"content_version": 1,
		"pet": {
			"hunger": clampf(float(old.get("hunger", 82.0)), 0.0, 100.0),
			"energy": clampf(float(old.get("energy", 78.0)), 0.0, 100.0),
			"mood": clampf(float(old.get("mood", 85.0)), 0.0, 100.0),
			"friendship_xp": clampi(int(old.get("friendship_xp", 0)), 0, MAX_COUNTER),
		},
		"wallet": {"stars": clampi(int(old.get("stars", 0)), 0, MAX_COUNTER)},
		"inventory": {},
		"daily": {
			"key": str(old.get("daily_key", today)),
			"echo_rewards": clampi(int(old.get("daily_echo_rewards", 0)), 0, 5),
			"care_rewards": clampi(int(old.get("daily_care_rewards", 0)), 0, 3),
			"minigame_rewards": clampi(int(old.get("daily_minigame_rewards", 0)), 0, 3),
		},
		"travel": _empty_travel(),
		"mailbox": [],
		"album": {},
		"flags": {
			"welcome_pack_granted": false,
			"tutorial_trip_started": false,
			"collection_rewards_created": [],
		},
		"recent_command_receipts": [],
	}


func new_snapshot() -> Dictionary:
	return _new_snapshot()


func commit(snapshot: Dictionary) -> Dictionary:
	if not _validate_snapshot(snapshot):
		return {"status": "NOT_COMMITTED", "error": "存档数据未通过完整性检查。"}
	var temp_file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp_file == null:
		return {"status": "NOT_COMMITTED", "error": "无法创建临时存档。"}
	temp_file.store_string(JSON.stringify(snapshot))
	temp_file.flush()
	var write_error := temp_file.get_error()
	temp_file.close()
	if write_error != OK:
		return _abort_temp("临时存档写入失败。")

	var verified := _read_candidate(TEMP_PATH)
	if not bool(verified.get("valid", false)):
		return _abort_temp("临时存档回读校验失败。")

	var base_exists := FileAccess.file_exists(SAVE_PATH)
	var backup_exists := FileAccess.file_exists(BACKUP_PATH)
	var base_candidate := _read_candidate(SAVE_PATH) if base_exists else {}
	var backup_candidate := _read_candidate(BACKUP_PATH) if backup_exists else {}
	var base_was_valid := bool(base_candidate.get("valid", false))
	var backup_was_valid := bool(backup_candidate.get("valid", false))
	var moved_base_to_backup := false
	var quarantined_base := ""

	if base_exists:
		if base_was_valid:
			if backup_exists:
				var remove_backup_error := _remove_if_exists(BACKUP_PATH)
				if remove_backup_error != OK:
					return _abort_temp("无法轮换旧备份。")
			var move_error := DirAccess.rename_absolute(
				ProjectSettings.globalize_path(SAVE_PATH),
				ProjectSettings.globalize_path(BACKUP_PATH)
			)
			if move_error != OK:
				return _abort_temp("无法备份当前存档。")
			moved_base_to_backup = true
		else:
			quarantined_base = CORRUPT_PREFIX + str(int(Time.get_unix_time_from_system())) + ".json"
			var copy_error := DirAccess.copy_absolute(
				ProjectSettings.globalize_path(SAVE_PATH),
				ProjectSettings.globalize_path(quarantined_base)
			)
			if copy_error != OK:
				return _abort_temp("无法隔离损坏的主存档。")
			var remove_base_error := _remove_if_exists(SAVE_PATH)
			if remove_base_error != OK:
				return _abort_temp("无法替换损坏的主存档。")

	var install_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	if install_error != OK:
		if moved_base_to_backup and FileAccess.file_exists(BACKUP_PATH):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(BACKUP_PATH),
				ProjectSettings.globalize_path(SAVE_PATH)
			)
		elif not quarantined_base.is_empty() and FileAccess.file_exists(quarantined_base):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(quarantined_base),
				ProjectSettings.globalize_path(SAVE_PATH)
			)
		var clean_error := _remove_if_exists(TEMP_PATH)
		if clean_error != OK:
			return {"status": "UNKNOWN", "error": "提交状态不确定，需要启动恢复流程。"}
		return {"status": "NOT_COMMITTED", "error": "无法提交正式存档。"}
	return {"status": "COMMITTED", "error": ""}


func _read_candidate(path: String) -> Dictionary:
	var result := {
		"path": path,
		"valid": false,
		"schema_version": 0,
		"revision": 0,
	}
	if path.is_empty() or not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return result
	var data: Dictionary = parser.data
	var schema := int(data.get("schema_version", 0))
	result["schema_version"] = schema
	if schema == 1:
		var v1_valid := true
		for key in ["hunger", "energy", "mood", "friendship_xp", "stars"]:
			if not _is_number(data.get(key)):
				v1_valid = false
		if not v1_valid:
			return result
		result["snapshot"] = data
		result["valid"] = true
		return result
	if schema != CURRENT_SCHEMA or not _validate_snapshot(data):
		return result
	result["snapshot"] = data
	result["revision"] = int(data.get("save_revision", 0))
	result["valid"] = true
	return result


func _validate_snapshot(data: Dictionary) -> bool:
	if int(data.get("schema_version", 0)) != CURRENT_SCHEMA:
		return false
	if not _is_int_in_range(data.get("save_revision"), 0, MAX_COUNTER):
		return false
	if not _is_int_in_range(data.get("content_version"), 1, MAX_COUNTER):
		return false
	var pet: Variant = data.get("pet")
	var wallet: Variant = data.get("wallet")
	var inventory: Variant = data.get("inventory")
	var daily: Variant = data.get("daily")
	var travel: Variant = data.get("travel")
	var mailbox: Variant = data.get("mailbox")
	var album: Variant = data.get("album")
	var flags: Variant = data.get("flags")
	var receipts: Variant = data.get("recent_command_receipts")
	if typeof(pet) != TYPE_DICTIONARY or typeof(wallet) != TYPE_DICTIONARY:
		return false
	if typeof(inventory) != TYPE_DICTIONARY or typeof(daily) != TYPE_DICTIONARY:
		return false
	if typeof(travel) != TYPE_DICTIONARY or typeof(mailbox) != TYPE_ARRAY:
		return false
	if typeof(album) != TYPE_DICTIONARY or typeof(flags) != TYPE_DICTIONARY:
		return false
	if typeof(receipts) != TYPE_ARRAY:
		return false
	for key in ["hunger", "energy", "mood"]:
		if not _is_number(pet.get(key)) or float(pet[key]) < 0.0 or float(pet[key]) > 100.0:
			return false
	if not _is_int_in_range(pet.get("friendship_xp"), 0, MAX_COUNTER):
		return false
	if not _is_int_in_range(wallet.get("stars"), 0, MAX_COUNTER):
		return false
	for item_id in inventory:
		if typeof(item_id) != TYPE_STRING or str(item_id).is_empty():
			return false
		if not _is_int_in_range(inventory[item_id], 0, MAX_COUNTER):
			return false
	if not _is_int_in_range(daily.get("echo_rewards"), 0, 5):
		return false
	for key in ["care_rewards", "minigame_rewards"]:
		if not _is_int_in_range(daily.get(key), 0, 3):
			return false
	if typeof(daily.get("key", "")) != TYPE_STRING:
		return false
	if not _is_int_in_range(travel.get("next_trip_sequence"), 1, MAX_COUNTER):
		return false
	if not _is_int_in_range(travel.get("rare_miss_streak"), 0, MAX_COUNTER):
		return false
	if typeof(travel.get("recent_history")) != TYPE_ARRAY:
		return false
	var active_trip: Variant = travel.get("active_trip")
	if active_trip != null and not _validate_trip(active_trip):
		return false
	var mail_ids: Dictionary = {}
	for mail in mailbox:
		if typeof(mail) != TYPE_DICTIONARY or str(mail.get("mail_id", "")).is_empty():
			return false
		if mail_ids.has(str(mail.mail_id)) or typeof(mail.get("read")) != TYPE_BOOL or typeof(mail.get("claimed")) != TYPE_BOOL:
			return false
		if not _validate_bundle(mail.get("reward_bundle", {})):
			return false
		mail_ids[str(mail.mail_id)] = true
	for template_id in album:
		var entry: Variant = album[template_id]
		if typeof(entry) != TYPE_DICTIONARY or str(entry.get("template_id", "")) != str(template_id):
			return false
		if not _is_int_in_range(entry.get("received_count"), 1, MAX_COUNTER):
			return false
	for key in ["welcome_pack_granted", "tutorial_trip_started"]:
		if typeof(flags.get(key)) != TYPE_BOOL:
			return false
	if typeof(flags.get("collection_rewards_created")) != TYPE_ARRAY:
		return false
	for receipt in receipts:
		if typeof(receipt) != TYPE_DICTIONARY or str(receipt.get("request_id", "")).is_empty():
			return false
		if typeof(receipt.get("result")) != TYPE_DICTIONARY:
			return false
	return true


func _validate_trip(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var trip: Dictionary = value
	if str(trip.get("trip_id", "")).is_empty() or typeof(trip.get("events")) != TYPE_ARRAY:
		return false
	if not _is_number(trip.get("elapsed_sec")) or float(trip.elapsed_sec) < 0.0:
		return false
	if not _is_int_in_range(trip.get("delivery_cursor"), 0, trip.events.size()):
		return false
	if not _is_number(trip.get("total_duration_sec")) or float(trip.total_duration_sec) < 0.0:
		return false
	if not _is_int_in_range(trip.get("clock_checkpoint_unix"), 0, MAX_UNIX_TIME):
		return false
	if not _is_int_in_range(trip.get("departed_unix"), 0, MAX_UNIX_TIME):
		return false
	if str(trip.get("state", "")) not in ["TRAVELLING", "RETURNED"] or trip.events.is_empty():
		return false
	var last_due := -1.0
	var event_ids: Dictionary = {}
	for index in range(trip.events.size()):
		var event: Variant = trip.events[index]
		if typeof(event) != TYPE_DICTIONARY:
			return false
		var event_id := str(event.get("event_id", ""))
		var due := float(event.get("due_offset_sec", -1.0))
		if event_id.is_empty() or event_ids.has(event_id) or not _is_number(event.get("due_offset_sec")) or due <= last_due:
			return false
		if str(event.get("kind", "")) not in ["postcard", "return"] or not _validate_bundle(event.get("reward_bundle", {})):
			return false
		if index == trip.events.size() - 1 and str(event.get("kind", "")) != "return":
			return false
		last_due = due
		event_ids[event_id] = true
	if int(trip.delivery_cursor) > trip.events.size() or float(trip.total_duration_sec) < last_due:
		return false
	return true


func _validate_bundle(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var bundle: Dictionary = value
	if not _is_int_in_range(bundle.get("stars", 0), 0, MAX_COUNTER):
		return false
	if not _is_int_in_range(bundle.get("friendship_xp", 0), 0, MAX_COUNTER):
		return false
	var items: Variant = bundle.get("items", {})
	if typeof(items) != TYPE_DICTIONARY:
		return false
	for item_id in items:
		if typeof(item_id) != TYPE_STRING or str(item_id).is_empty() or not _is_int_in_range(items[item_id], 0, MAX_COUNTER):
			return false
	return true


func _is_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


func _is_int_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if not _is_number(value):
		return false
	var number := float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floorf(number) == number


func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _abort_temp(message: String) -> Dictionary:
	var cleanup_error := _remove_if_exists(TEMP_PATH)
	if cleanup_error != OK:
		return {"status": "UNKNOWN", "error": "%s 临时文件无法清理，需要启动恢复流程。" % message}
	return {"status": "NOT_COMMITTED", "error": message}


func _new_snapshot() -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA,
		"save_revision": 0,
		"content_version": 1,
		"pet": {"hunger": 82.0, "energy": 78.0, "mood": 85.0, "friendship_xp": 0},
		"wallet": {"stars": 0},
		"inventory": {},
		"daily": {
			"key": Time.get_date_string_from_system(),
			"echo_rewards": 0,
			"care_rewards": 0,
			"minigame_rewards": 0,
		},
		"travel": _empty_travel(),
		"mailbox": [],
		"album": {},
		"flags": {
			"welcome_pack_granted": false,
			"tutorial_trip_started": false,
			"collection_rewards_created": [],
		},
		"recent_command_receipts": [],
	}


func _empty_travel() -> Dictionary:
	return {
		"next_trip_sequence": 1,
		"rare_miss_streak": 0,
		"active_trip": null,
		"recent_history": [],
	}
