extends Node

signal state_changed(snapshot: Dictionary)

var friendship_xp := 0
var stars := 0
var hunger := 82.0
var energy := 78.0
var mood := 85.0
var _store: RefCounted
var _enabled := false
var _resting := false
var _cooldowns: Dictionary = {"pet": 0.0, "feed": 0.0, "play": 0.0}
var _last_result: Dictionary = {}


func setup(store: RefCounted, enabled: bool = true) -> void:
	_store = store
	_enabled = enabled


func _ready() -> void:
	if _store == null:
		push_error("PetState 缺少 GameStore 注入。")
		return
	_store.state_changed.connect(_on_store_changed)
	_on_store_changed(_store.get_snapshot())


func _process(delta: float) -> void:
	for key in _cooldowns:
		_cooldowns[key] = maxf(0.0, float(_cooldowns[key]) - delta)


func get_snapshot() -> Dictionary:
	if _store == null:
		return {}
	return _store.get_pet_snapshot(_resting)


func pet() -> bool:
	if not _enabled:
		_last_result = {"ok": false, "code": "NOT_READY", "message": "存档还没有准备好。"}
		return false
	if float(_cooldowns.pet) > 0.0:
		_last_result = {"ok": false, "code": "COOLDOWN", "message": "西小电刚被摸过，等一会儿再来。"}
		return false
	_last_result = _store.pet()
	if not bool(_last_result.get("ok", false)):
		return false
	_cooldowns.pet = 10.0
	return true


func feed() -> bool:
	if not _enabled:
		_last_result = {"ok": false, "code": "NOT_READY", "message": "存档还没有准备好。"}
		return false
	if float(_cooldowns.feed) > 0.0:
		_last_result = {"ok": false, "code": "COOLDOWN", "message": "西小电刚吃过，等一会儿再来。"}
		return false
	_last_result = _store.feed()
	if not bool(_last_result.get("ok", false)):
		return false
	_cooldowns.feed = 15.0
	return true


func start_minigame() -> bool:
	if not _enabled:
		_last_result = {"ok": false, "code": "NOT_READY", "message": "存档还没有准备好。"}
		return false
	if float(_cooldowns.play) > 0.0:
		_last_result = {"ok": false, "code": "COOLDOWN", "message": "西小电需要缓一会儿再冲刺。"}
		return false
	_cooldowns.play = 25.0
	return true


func complete_minigame(reward_stars: int, run_id: String = "") -> Dictionary:
	if not _enabled:
		return {"ok": false, "code": "NOT_READY", "message": "存档还没有准备好。"}
	var request_id := run_id if not run_id.is_empty() else "run:%d:%d" % [Time.get_ticks_usec(), randi()]
	_last_result = _store.complete_minigame(request_id, reward_stars)
	return _last_result.duplicate(true)


func reward_echo() -> Dictionary:
	if not _enabled:
		return {"ok": false, "code": "NOT_READY", "message": "存档还没有准备好。"}
	_last_result = _store.reward_echo()
	return _last_result.duplicate(true)


func set_resting(resting: bool) -> Dictionary:
	if not _enabled:
		return {"ok": false, "code": "NOT_READY", "message": "存档还没有准备好。"}
	if resting == _resting:
		return {"ok": true, "code": "UNCHANGED", "actual_changes": {}}
	_last_result = _store.set_resting(resting, resting)
	if bool(_last_result.get("ok", false)):
		_resting = resting
		_publish()
	return _last_result.duplicate(true)


func last_result() -> Dictionary:
	return _last_result.duplicate(true)


func _on_store_changed(snapshot: Dictionary) -> void:
	var pet_data: Dictionary = snapshot.get("pet", {})
	hunger = float(pet_data.get("hunger", hunger))
	energy = float(pet_data.get("energy", energy))
	mood = float(pet_data.get("mood", mood))
	friendship_xp = int(pet_data.get("friendship_xp", friendship_xp))
	stars = int(snapshot.get("wallet", {}).get("stars", stars))
	_publish()


func _publish() -> void:
	state_changed.emit(get_snapshot())
