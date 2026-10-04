extends Node

signal state_changed(snapshot: Dictionary)
signal trip_mail_arrived(count: int, trip_id: String)

const REPOSITORY_SCRIPT = preload("res://Scripts/Core/SaveRepository.gd")
const STORE_SCRIPT = preload("res://Scripts/Core/GameStore.gd")
const CATALOG_SCRIPT = preload("res://Scripts/Data/Catalog.gd")
const REWARD_SCRIPT = preload("res://Scripts/Services/RewardService.gd")
const SHOP_SCRIPT = preload("res://Scripts/Services/ShopService.gd")
const INVENTORY_SCRIPT = preload("res://Scripts/Services/InventoryService.gd")
const TRAVEL_SCRIPT = preload("res://Scripts/Services/TravelService.gd")
const MAILBOX_SCRIPT = preload("res://Scripts/Services/MailboxService.gd")

var store: RefCounted
var catalog: RefCounted
var rewards: RefCounted
var shop: RefCounted
var inventory: RefCounted
var travel: RefCounted
var mailbox: RefCounted
var ready_ok := false
var startup_error := ""
var _repository: RefCounted
var _second_timer := 0.0
var _save_timer := 0.0


func _ready() -> void:
	catalog = CATALOG_SCRIPT.new()
	var catalog_result: Dictionary = catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		startup_error = str(catalog_result.get("error", "配置加载失败。"))
		push_error(startup_error)
		return
	_repository = REPOSITORY_SCRIPT.new()
	var loaded: Dictionary = _repository.load_latest()
	if not bool(loaded.get("ok", false)):
		startup_error = str(loaded.get("error", "无法安全读取存档。"))
		push_error(startup_error)
		return
	store = STORE_SCRIPT.new()
	store.initialize(_repository, loaded.snapshot)
	# A fresh process has no monotonic clock baseline from the previous run.
	# Recover one wall-clock interval before any transaction can move its checkpoint.
	store.resume_foreground()
	rewards = REWARD_SCRIPT.new()
	shop = SHOP_SCRIPT.new()
	shop.setup(store, catalog)
	inventory = INVENTORY_SCRIPT.new()
	inventory.setup(store, catalog)
	travel = TRAVEL_SCRIPT.new()
	travel.setup(store, catalog, rewards)
	mailbox = MAILBOX_SCRIPT.new()
	mailbox.setup(store, catalog, rewards)
	store.state_changed.connect(_on_store_changed)
	var pack_result := _ensure_welcome_pack()
	if not bool(pack_result.get("ok", false)):
		startup_error = str(pack_result.get("message", "首次礼包存档失败。"))
		push_error(startup_error)
		return
	ready_ok = true
	var reconcile_result: Dictionary = travel.reconcile()
	if bool(reconcile_result.get("ok", false)) and int(reconcile_result.get("actual_changes", {}).get("mail_count", 0)) > 0:
		trip_mail_arrived.emit(int(reconcile_result.actual_changes.mail_count), str(reconcile_result.actual_changes.get("trip_id", "")))
	store.publish()


func _process(delta: float) -> void:
	if not ready_ok:
		return
	store.tick_pet(delta)
	_second_timer += delta
	_save_timer += delta
	if _second_timer >= 1.0:
		_second_timer = fmod(_second_timer, 1.0)
		var result: Dictionary = travel.reconcile()
		if bool(result.get("ok", false)) and int(result.get("actual_changes", {}).get("mail_count", 0)) > 0:
			trip_mail_arrived.emit(int(result.actual_changes.mail_count), str(result.actual_changes.get("trip_id", "")))
		store.publish()
	if _save_timer >= 30.0:
		_save_timer = fmod(_save_timer, 30.0)
		var active_trip: Variant = store.get_snapshot().get("travel", {}).get("active_trip")
		if store.is_dirty() or typeof(active_trip) == TYPE_DICTIONARY:
			store.flush()


func on_application_paused() -> void:
	if not ready_ok:
		return
	var arrived: Dictionary = travel.reconcile()
	if bool(arrived.get("ok", false)) and int(arrived.get("actual_changes", {}).get("mail_count", 0)) > 0:
		trip_mail_arrived.emit(int(arrived.actual_changes.mail_count), str(arrived.actual_changes.get("trip_id", "")))
	store.pause_foreground()


func on_application_resumed() -> void:
	if not ready_ok:
		return
	store.resume_foreground()
	var arrived: Dictionary = travel.reconcile()
	if bool(arrived.get("ok", false)) and int(arrived.get("actual_changes", {}).get("mail_count", 0)) > 0:
		trip_mail_arrived.emit(int(arrived.actual_changes.mail_count), str(arrived.actual_changes.get("trip_id", "")))
	store.flush()


func flush() -> Dictionary:
	if not ready_ok:
		return {"status": "NOT_COMMITTED", "error": startup_error}
	return store.flush()


func _ensure_welcome_pack() -> Dictionary:
	var snapshot: Dictionary = store.get_snapshot()
	if bool(snapshot.get("flags", {}).get("welcome_pack_granted", false)):
		return {"ok": true, "code": "ALREADY_GRANTED"}
	var pack: Dictionary = catalog.progression.get("welcome_pack", {})
	return store.transact("welcome_pack", "welcome_pack:v1", func(draft: Dictionary) -> Dictionary:
		if bool(draft.flags.get("welcome_pack_granted", false)):
			return {"ok": true, "code": "ALREADY_GRANTED", "actual_changes": {}}
		var stars := int(pack.get("stars", 0))
		if int(draft.wallet.stars) + stars > 1_000_000_000:
			return {"ok": false, "code": "COUNTER_LIMIT", "message": "无法安全发放首次礼包。"}
		for item_id in pack.get("items", {}):
			var amount := int(pack.items[item_id])
			if int(draft.inventory.get(str(item_id), 0)) + amount > 1_000_000_000:
				return {"ok": false, "code": "COUNTER_LIMIT", "message": "无法安全发放首次礼包。"}
		draft.wallet.stars = int(draft.wallet.stars) + stars
		var actual_items: Dictionary = {}
		for item_id in pack.get("items", {}):
			var amount := int(pack.items[item_id])
			draft.inventory[str(item_id)] = int(draft.inventory.get(str(item_id), 0)) + amount
			actual_items[str(item_id)] = amount
		draft.flags.welcome_pack_granted = true
		return {"ok": true, "code": "OK", "actual_changes": {"stars": stars, "items": actual_items}}
	)


func _on_store_changed(snapshot: Dictionary) -> void:
	state_changed.emit(snapshot)
