extends RefCounted

signal state_changed(snapshot: Dictionary)

const MAX_COUNTER := 1_000_000_000
const MAX_RECEIPTS := 256

var _repository: RefCounted
var _data: Dictionary = {}
var _initialized := false
var _uncertain := false
var _dirty := false
var _resting := false
var _foreground := true
var _tick_anchor_msec := 0


func initialize(repository: RefCounted, snapshot: Dictionary) -> void:
	_repository = repository
	_data = snapshot.duplicate(true)
	_initialized = true
	_foreground = false
	_tick_anchor_msec = Time.get_ticks_msec()


func is_ready() -> bool:
	return _initialized and not _uncertain


func get_snapshot() -> Dictionary:
	if not _initialized:
		return {}
	return _effective_data()


func get_pet_snapshot(resting: bool = false) -> Dictionary:
	var snapshot := get_snapshot()
	if snapshot.is_empty():
		return {}
	var pet: Dictionary = snapshot.pet
	var result := pet.duplicate(true)
	result["level"] = calculate_level(int(pet.get("friendship_xp", 0)))
	result["stars"] = int(snapshot.wallet.get("stars", 0))
	result["resting"] = resting
	return result


func get_item_count(item_id: String) -> int:
	return int(_data.get("inventory", {}).get(item_id, 0))


func is_resting() -> bool:
	return _resting


func transact(command: String, request_id: String, mutator: Callable) -> Dictionary:
	if not _initialized:
		return _result(false, "NOT_READY", request_id, "游戏数据尚未准备好。")
	if _uncertain:
		return _result(false, "SAVE_UNCERTAIN", request_id, "正在恢复存档，请稍后重试。")
	if not request_id.is_empty():
		var previous := _find_receipt(request_id)
		if not previous.is_empty():
			var previous_result: Dictionary = previous.get("result", {}).duplicate(true)
			previous_result["duplicate"] = true
			return previous_result

	var now_msec := Time.get_ticks_msec()
	var draft := _effective_data(now_msec)
	draft["save_revision"] = int(_data.get("save_revision", 0)) + 1
	_set_trip_checkpoint(draft, int(Time.get_unix_time_from_system()))
	var outcome_variant: Variant = mutator.call(draft)
	if typeof(outcome_variant) != TYPE_DICTIONARY:
		return _result(false, "INVALID_COMMAND", request_id, "操作没有返回有效结果。")
	var outcome: Dictionary = outcome_variant
	if not bool(outcome.get("ok", false)):
		outcome["request_id"] = request_id
		return outcome
	if not request_id.is_empty():
		var receipts: Array = draft.get("recent_command_receipts", []).duplicate(true)
		receipts.append({
			"request_id": request_id,
			"command": command,
			"result": outcome.duplicate(true),
		})
		while receipts.size() > MAX_RECEIPTS:
			receipts.pop_front()
		draft["recent_command_receipts"] = receipts
	var commit_result: Dictionary = _repository.commit(draft)
	if str(commit_result.get("status", "")) == "COMMITTED":
		_data = draft
		_tick_anchor_msec = now_msec
		_dirty = false
		_publish()
		outcome["request_id"] = request_id
		outcome["save_revision"] = int(draft.save_revision)
		return outcome
	if str(commit_result.get("status", "")) == "UNKNOWN":
		_uncertain = true
		var recovered: Dictionary = _repository.load_latest()
		if bool(recovered.get("ok", false)) and not bool(recovered.get("is_new", false)):
			_data = recovered.snapshot.duplicate(true)
			_tick_anchor_msec = Time.get_ticks_msec()
			_uncertain = false
			var receipt := _find_receipt(request_id)
			if not receipt.is_empty():
				var recovered_result: Dictionary = receipt.get("result", {}).duplicate(true)
				recovered_result["request_id"] = request_id
				recovered_result["save_revision"] = int(_data.get("save_revision", 0))
				recovered_result["recovered"] = true
				_publish()
				return recovered_result
			_publish()
		return _result(false, "SAVE_FAILED", request_id, "存档未确认提交，请检查当前状态后重试。")
	return _result(false, "SAVE_FAILED", request_id, str(commit_result.get("error", "无法保存本次操作。")))


func flush() -> Dictionary:
	if not _initialized:
		return {"status": "NOT_COMMITTED", "error": "游戏数据尚未准备好。"}
	if _uncertain:
		return {"status": "UNKNOWN", "error": "存档状态正在恢复。"}
	var now_msec := Time.get_ticks_msec()
	var draft := _effective_data(now_msec)
	draft["save_revision"] = int(_data.get("save_revision", 0)) + 1
	_set_trip_checkpoint(draft, int(Time.get_unix_time_from_system()))
	var result: Dictionary = _repository.commit(draft)
	if str(result.get("status", "")) == "COMMITTED":
		_data = draft
		_tick_anchor_msec = now_msec
		_dirty = false
		_publish()
	elif str(result.get("status", "")) == "UNKNOWN":
		_uncertain = true
		var recovered: Dictionary = _repository.load_latest()
		if bool(recovered.get("ok", false)) and not bool(recovered.get("is_new", false)):
			_data = recovered.snapshot.duplicate(true)
			_tick_anchor_msec = Time.get_ticks_msec()
			_uncertain = false
			_publish()
	return result


func tick_pet(delta: float) -> void:
	if not _initialized or delta <= 0.0:
		return
	var pet: Dictionary = _data.pet
	var before := [float(pet.hunger), float(pet.energy), float(pet.mood)]
	pet.hunger = maxf(20.0, float(pet.hunger) - 0.15 * delta / 60.0)
	if _resting:
		pet.energy = minf(100.0, float(pet.energy) + 20.0 * delta / 60.0)
	else:
		pet.energy = maxf(20.0, float(pet.energy) - 0.20 * delta / 60.0)
	pet.mood = maxf(20.0, float(pet.mood) - 0.10 * delta / 60.0)
	if before[0] != pet.hunger or before[1] != pet.energy or before[2] != pet.mood:
		_dirty = true


func publish() -> void:
	_publish()


func pause_foreground() -> Dictionary:
	if not _foreground:
		return {"status": "COMMITTED", "error": ""}
	var result := flush()
	_foreground = false
	return result


func resume_foreground() -> void:
	if _foreground or not _initialized:
		return
	var now_unix := int(Time.get_unix_time_from_system())
	var active: Variant = _data.travel.get("active_trip")
	if typeof(active) == TYPE_DICTIONARY:
		var offline_delta := maxi(0, now_unix - int(active.get("clock_checkpoint_unix", now_unix)))
		active.elapsed_sec = minf(
			float(active.get("total_duration_sec", 0.0)),
			float(active.get("elapsed_sec", 0.0)) + float(offline_delta)
		)
		active.clock_checkpoint_unix = now_unix
		_dirty = true
	_foreground = true
	_tick_anchor_msec = Time.get_ticks_msec()
	_publish()


func set_resting(resting: bool, award_care: bool = true) -> Dictionary:
	if not resting or not award_care:
		_resting = resting
		_publish()
		return {"ok": true, "code": "OK", "actual_changes": {}}
	var result := _award_care("resting", "")
	if bool(result.get("ok", false)):
		_resting = true
		_publish()
	return result


func pet() -> Dictionary:
	return transact("pet", _new_request_id("pet"), func(draft: Dictionary) -> Dictionary:
		_reset_daily(draft)
		var old_mood := float(draft.pet.mood)
		draft.pet.mood = minf(100.0, old_mood + 4.0)
		var xp_awarded := _award_care_in_draft(draft)
		return {"ok": true, "code": "OK", "actual_changes": {"mood": float(draft.pet.mood) - old_mood, "friendship_xp": xp_awarded}}
	)


func feed() -> Dictionary:
	return transact("free_feed", _new_request_id("feed"), func(draft: Dictionary) -> Dictionary:
		_reset_daily(draft)
		var old_hunger := float(draft.pet.hunger)
		var old_mood := float(draft.pet.mood)
		draft.pet.hunger = minf(100.0, old_hunger + 25.0)
		draft.pet.mood = minf(100.0, old_mood + 3.0)
		var xp_awarded := _award_care_in_draft(draft)
		return {"ok": true, "code": "OK", "actual_changes": {"hunger": float(draft.pet.hunger) - old_hunger, "mood": float(draft.pet.mood) - old_mood, "friendship_xp": xp_awarded}}
	)


func reward_echo() -> Dictionary:
	return transact("echo_reward", _new_request_id("echo"), func(draft: Dictionary) -> Dictionary:
		_reset_daily(draft)
		var old_mood := float(draft.pet.mood)
		draft.pet.mood = minf(100.0, old_mood + 2.0)
		var stars_gained := 0
		var xp_gained := 0
		if int(draft.daily.echo_rewards) < 5:
			draft.daily.echo_rewards = int(draft.daily.echo_rewards) + 1
			stars_gained = mini(1, MAX_COUNTER - int(draft.wallet.stars))
			xp_gained = mini(4, MAX_COUNTER - int(draft.pet.friendship_xp))
			draft.wallet.stars = mini(MAX_COUNTER, int(draft.wallet.stars) + stars_gained)
			draft.pet.friendship_xp = mini(MAX_COUNTER, int(draft.pet.friendship_xp) + xp_gained)
		return {"ok": true, "code": "OK", "actual_changes": {"stars": stars_gained, "friendship_xp": xp_gained, "mood": float(draft.pet.mood) - old_mood}}
	)


func complete_minigame(request_id: String, reward_stars: int) -> Dictionary:
	return transact("minigame_reward", request_id, func(draft: Dictionary) -> Dictionary:
		_reset_daily(draft)
		var old_mood := float(draft.pet.mood)
		var old_energy := float(draft.pet.energy)
		draft.pet.mood = minf(100.0, old_mood + 8.0)
		draft.pet.energy = maxf(20.0, old_energy - 5.0)
		var awarded_stars := 0
		var awarded_xp := 0
		if int(draft.daily.minigame_rewards) < 3:
			draft.daily.minigame_rewards = int(draft.daily.minigame_rewards) + 1
			awarded_stars = mini(clampi(reward_stars, 1, 5), MAX_COUNTER - int(draft.wallet.stars))
			awarded_xp = mini(8, MAX_COUNTER - int(draft.pet.friendship_xp))
			draft.wallet.stars = mini(MAX_COUNTER, int(draft.wallet.stars) + awarded_stars)
			draft.pet.friendship_xp = mini(MAX_COUNTER, int(draft.pet.friendship_xp) + awarded_xp)
		return {"ok": true, "code": "OK", "actual_changes": {"stars": awarded_stars, "friendship_xp": awarded_xp, "mood": float(draft.pet.mood) - old_mood, "energy": float(draft.pet.energy) - old_energy}}
	)


func set_pet_stat(stat_name: String, value: float) -> void:
	if not _data.has("pet") or stat_name not in ["hunger", "energy", "mood"]:
		return
	_data.pet[stat_name] = clampf(value, 0.0, 100.0)
	_dirty = true


func is_dirty() -> bool:
	return _dirty


func calculate_level(xp: int) -> int:
	var remaining := xp
	var level := 1
	var threshold := 60
	while remaining >= threshold and level < 10:
		remaining -= threshold
		level += 1
		threshold += 20
	return level


func _award_care(reason: String, request_id: String) -> Dictionary:
	return transact(reason, request_id if not request_id.is_empty() else _new_request_id(reason), func(draft: Dictionary) -> Dictionary:
		_reset_daily(draft)
		var xp := _award_care_in_draft(draft)
		return {"ok": true, "code": "OK", "actual_changes": {"friendship_xp": xp}}
	)


func _award_care_in_draft(draft: Dictionary) -> int:
	if int(draft.daily.care_rewards) >= 3:
		return 0
	draft.daily.care_rewards = int(draft.daily.care_rewards) + 1
	var xp_awarded := mini(5, MAX_COUNTER - int(draft.pet.friendship_xp))
	draft.pet.friendship_xp = int(draft.pet.friendship_xp) + xp_awarded
	return xp_awarded


func _reset_daily(draft: Dictionary) -> void:
	var today := Time.get_date_string_from_system()
	if str(draft.daily.get("key", "")) == today:
		return
	draft.daily.key = today
	draft.daily.echo_rewards = 0
	draft.daily.care_rewards = 0
	draft.daily.minigame_rewards = 0


func _effective_data(now_msec: int = -1) -> Dictionary:
	var result := _data.duplicate(true)
	if now_msec < 0:
		now_msec = Time.get_ticks_msec()
	if _foreground:
		var active: Variant = result.get("travel", {}).get("active_trip")
		if typeof(active) == TYPE_DICTIONARY:
			var elapsed := maxf(0.0, float(now_msec - _tick_anchor_msec) / 1000.0)
			active.elapsed_sec = minf(float(active.total_duration_sec), float(active.elapsed_sec) + elapsed)
	return result


func _set_trip_checkpoint(snapshot: Dictionary, now_unix: int) -> void:
	var active: Variant = snapshot.get("travel", {}).get("active_trip")
	if typeof(active) == TYPE_DICTIONARY:
		active.clock_checkpoint_unix = now_unix


func _find_receipt(request_id: String) -> Dictionary:
	if request_id.is_empty():
		return {}
	for receipt in _data.get("recent_command_receipts", []):
		if typeof(receipt) == TYPE_DICTIONARY and str(receipt.get("request_id", "")) == request_id:
			return receipt.duplicate(true)
	return {}


func _publish() -> void:
	state_changed.emit(get_snapshot())


func _result(ok: bool, code: String, request_id: String, message: String) -> Dictionary:
	return {"ok": ok, "code": code, "request_id": request_id, "message": message, "actual_changes": {}}


func _new_request_id(prefix: String) -> String:
	return "%s:%d:%d" % [prefix, Time.get_ticks_usec(), randi()]
