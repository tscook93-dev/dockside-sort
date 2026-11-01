extends RefCounted

## Local progress for Milestone 2. user:// is IndexedDB on web and app storage on Android.

const SAVE_PATH := "user://progress.cfg"
const COINS_PER_STAR := 10
## Undos past the 3-star limit, up to this many more, still count as a light assist.
const LIGHT_EXTRA_UNDOS := 2

var path := SAVE_PATH
var coins := 0
var unlocked_through := 1
var sound_on := true
var haptics_on := true
var best_stars := {}


static func stars_for(undos: int, undo_limit: int, temp_slot_used: bool) -> int:
	if undos <= undo_limit and not temp_slot_used:
		return 3
	if undos <= undo_limit + LIGHT_EXTRA_UNDOS:
		return 2
	return 1


func best_for(level_id: int) -> int:
	return int(best_stars.get(str(level_id), 0))


func is_unlocked(index: int) -> bool:
	return index < unlocked_through


func load_file() -> void:
	var web := _read_web()
	if web != "":
		var parsed: Variant = JSON.parse_string(web)
		if typeof(parsed) == TYPE_DICTIONARY:
			_apply_dict(parsed)
			return
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	coins = int(cfg.get_value("player", "coins", 0))
	unlocked_through = maxi(1, int(cfg.get_value("player", "unlocked_through", 1)))
	sound_on = bool(cfg.get_value("settings", "sound", true))
	haptics_on = bool(cfg.get_value("settings", "haptics", true))
	best_stars = {}
	var raw: Variant = cfg.get_value("player", "stars", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for key in raw:
			best_stars[str(key)] = int(raw[key])


func save_file() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "unlocked_through", unlocked_through)
	cfg.set_value("player", "stars", best_stars)
	cfg.set_value("settings", "sound", sound_on)
	cfg.set_value("settings", "haptics", haptics_on)
	cfg.save(path)
	_write_web()


func _apply_dict(data: Dictionary) -> void:
	coins = int(data.get("coins", 0))
	unlocked_through = maxi(1, int(data.get("unlocked_through", 1)))
	sound_on = bool(data.get("sound_on", true))
	haptics_on = bool(data.get("haptics_on", true))
	best_stars = {}
	var raw: Variant = data.get("best_stars", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for key in raw:
			best_stars[str(key)] = int(raw[key])


func _snapshot() -> String:
	return JSON.stringify({
		"coins": coins,
		"unlocked_through": unlocked_through,
		"sound_on": sound_on,
		"haptics_on": haptics_on,
		"best_stars": best_stars,
	})


func _write_web() -> void:
	if not OS.has_feature("web"):
		return
	# localStorage is synchronous, so a reload in the same tab cannot outrun the save.
	JavaScriptBridge.eval("localStorage.setItem('dockside_progress', %s);" % JSON.stringify(_snapshot()), true)


func _read_web() -> String:
	if not OS.has_feature("web"):
		return ""
	var value: Variant = JavaScriptBridge.eval("localStorage.getItem('dockside_progress')", true)
	if value == null:
		return ""
	return str(value)


func record_clear(level_index: int, level_id: int, level_count: int, undos: int, undo_limit: int, temp_slot_used: bool) -> Dictionary:
	var stars := stars_for(undos, undo_limit, temp_slot_used)
	var gained := stars * COINS_PER_STAR
	coins += gained
	var key := str(level_id)
	if stars > int(best_stars.get(key, 0)):
		best_stars[key] = stars
	if level_index + 1 == unlocked_through and level_index + 1 < level_count:
		unlocked_through += 1
	save_file()
	return {
		"stars": stars,
		"coins": gained,
		"balance": coins,
		"undos": undos,
		"undo_limit": undo_limit,
		"temp_slot_used": temp_slot_used,
	}
