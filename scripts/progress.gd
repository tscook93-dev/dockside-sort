extends RefCounted

## Local progress for Milestone 2. user:// is IndexedDB on web and app storage on Android.

const SAVE_PATH := "user://progress.cfg"
const COINS_PER_STAR := 10
## Undos past the 3-star limit, up to this many more, still count as a light assist.
const LIGHT_EXTRA_UNDOS := 2

const HOLD_PRICE := 300
const DAILY_REWARD := 30
## Unix UTC day (floor of UTC unix seconds / 86400) modulo 7.
## 0 → level 18, 1 → 19, 2 → 20, 3 → 21, 4 → 22, 5 → 23, 6 → 24.
const DAILY_LEVELS := [18, 19, 20, 21, 22, 23, 24]
const STREAK_REWARDS := [10, 10, 15, 15, 20, 20, 30]

var path := SAVE_PATH
var coins := 0
var unlocked_through := 1
var sound_on := true
var haptics_on := true
var best_stars := {}
var ftue_seen := {}
var second_hold := false
var upgrade_unlocked := false
var highest_utc_day := -1
var streak_next := 1
var streak_last_day := -1
var freeze_tokens := 0
var daily_cleared_day := -1
## Local test ledger only. Not a store receipt and not a production entitlement.
var test_no_forced_ads := false
var test_transactions := {}
var temp_level_id := -1
var temp_is_daily := false
var interstitial_armed := false
var interstitial_count := 0
var last_ad_ms := -1
## Tests inject a millisecond clock. -1 uses the device clock. Never written to the save.
var test_now_ms := -1
const UNDO_PRICE := 50
const TEMP_PRICE := 100
const FREE_UNDOS := 3
const AD_GAP_MS := 90000
const PACKS := {
	"S": {"coins": 500, "usd": "1.99", "aud": "2.99"},
	"M": {"coins": 1500, "usd": "4.99", "aud": "7.99"},
	"L": {"coins": 3500, "usd": "9.99", "aud": "14.99"},
}
const NO_ADS_USD := "9.99"
const NO_ADS_AUD := "14.99"
## Tests inject a UTC day number. -1 uses the device clock. Never written to the save.
var test_utc_day := -1


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


func seen_ftue(level_id: int) -> bool:
	return bool(ftue_seen.get(str(level_id), false))


func mark_ftue(level_id: int) -> void:
	ftue_seen[str(level_id)] = true


func load_file() -> void:
	var web := _read_web()
	if web != "":
		var parsed: Variant = JSON.parse_string(web)
		if typeof(parsed) == TYPE_DICTIONARY:
			_apply_dict(parsed)
			_read_ftue(parsed.get("ftue", {}))
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
	_read_ftue(cfg.get_value("player", "ftue", {}))
	_read_meta_cfg(cfg)
	_sync_upgrade_flag()
	_sync_interstitial()


func save_file() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "unlocked_through", unlocked_through)
	cfg.set_value("player", "stars", best_stars)
	cfg.set_value("player", "ftue", ftue_seen)
	cfg.set_value("player", "second_hold", second_hold)
	cfg.set_value("player", "upgrade_unlocked", upgrade_unlocked)
	cfg.set_value("player", "highest_utc_day", highest_utc_day)
	cfg.set_value("player", "streak_next", streak_next)
	cfg.set_value("player", "streak_last_day", streak_last_day)
	cfg.set_value("player", "freeze_tokens", freeze_tokens)
	cfg.set_value("player", "daily_cleared_day", daily_cleared_day)
	cfg.set_value("test_monetisation", "no_forced_ads", test_no_forced_ads)
	cfg.set_value("test_monetisation", "transactions", test_transactions)
	cfg.set_value("test_monetisation", "temp_level_id", temp_level_id)
	cfg.set_value("test_monetisation", "temp_is_daily", temp_is_daily)
	cfg.set_value("test_monetisation", "interstitial_armed", interstitial_armed)
	cfg.set_value("test_monetisation", "interstitial_count", interstitial_count)
	cfg.set_value("test_monetisation", "last_ad_ms", last_ad_ms)
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
	second_hold = bool(data.get("second_hold", false))
	upgrade_unlocked = bool(data.get("upgrade_unlocked", false))
	highest_utc_day = int(data.get("highest_utc_day", -1))
	streak_next = clampi(int(data.get("streak_next", 1)), 1, 7)
	streak_last_day = int(data.get("streak_last_day", -1))
	freeze_tokens = clampi(int(data.get("freeze_tokens", 0)), 0, 1)
	daily_cleared_day = int(data.get("daily_cleared_day", -1))
	_read_test_ledger(data.get("test_monetisation", {}))
	_sync_upgrade_flag()


func _read_meta_cfg(cfg: ConfigFile) -> void:
	second_hold = bool(cfg.get_value("player", "second_hold", false))
	upgrade_unlocked = bool(cfg.get_value("player", "upgrade_unlocked", false))
	highest_utc_day = int(cfg.get_value("player", "highest_utc_day", -1))
	streak_next = clampi(int(cfg.get_value("player", "streak_next", 1)), 1, 7)
	streak_last_day = int(cfg.get_value("player", "streak_last_day", -1))
	freeze_tokens = clampi(int(cfg.get_value("player", "freeze_tokens", 0)), 0, 1)
	daily_cleared_day = int(cfg.get_value("player", "daily_cleared_day", -1))
	temp_level_id = int(cfg.get_value("test_monetisation", "temp_level_id", -1))
	temp_is_daily = bool(cfg.get_value("test_monetisation", "temp_is_daily", false))
	interstitial_armed = bool(cfg.get_value("test_monetisation", "interstitial_armed", false))
	interstitial_count = int(cfg.get_value("test_monetisation", "interstitial_count", 0))
	last_ad_ms = int(cfg.get_value("test_monetisation", "last_ad_ms", -1))
	test_no_forced_ads = bool(cfg.get_value("test_monetisation", "no_forced_ads", false))
	test_transactions = {}
	var txs: Variant = cfg.get_value("test_monetisation", "transactions", {})
	if typeof(txs) == TYPE_DICTIONARY:
		for key in txs:
			if bool(txs[key]):
				test_transactions[str(key)] = true


func _sync_upgrade_flag() -> void:
	if best_for(15) > 0:
		upgrade_unlocked = true


func utc_day() -> int:
	if test_utc_day >= 0:
		return test_utc_day
	return int(floor(float(Time.get_unix_time_from_system()) / 86400.0))


func observed_day() -> int:
	var device := utc_day()
	if highest_utc_day < 0:
		return device
	return maxi(device, highest_utc_day)


func daily_level_id() -> int:
	var day := observed_day()
	var slot := day % 7
	if slot < 0:
		slot += 7
	return int(DAILY_LEVELS[slot])


func daily_unlocked() -> bool:
	return best_for(5) > 0


func daily_done_today() -> bool:
	return daily_cleared_day >= 0 and daily_cleared_day == observed_day()


func _read_ftue(raw: Variant) -> void:
	ftue_seen = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for key in raw:
		if bool(raw[key]):
			ftue_seen[str(key)] = true


func _snapshot() -> String:
	return JSON.stringify({
		"coins": coins,
		"unlocked_through": unlocked_through,
		"sound_on": sound_on,
		"haptics_on": haptics_on,
		"best_stars": best_stars,
		"ftue": ftue_seen,
		"second_hold": second_hold,
		"upgrade_unlocked": upgrade_unlocked,
		"highest_utc_day": highest_utc_day,
		"streak_next": streak_next,
		"streak_last_day": streak_last_day,
		"freeze_tokens": freeze_tokens,
		"daily_cleared_day": daily_cleared_day,
		"test_monetisation": {
			"no_forced_ads": test_no_forced_ads,
			"transactions": test_transactions,
			"temp_level_id": temp_level_id,
			"temp_is_daily": temp_is_daily,
			"interstitial_armed": interstitial_armed,
			"interstitial_count": interstitial_count,
			"last_ad_ms": last_ad_ms,
		},
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
	var key := str(level_id)
	var previous := int(best_stars.get(key, 0))
	var new_stars := maxi(0, stars - previous)
	var gained := new_stars * COINS_PER_STAR
	coins += gained
	if stars > previous:
		best_stars[key] = stars
	if level_index + 1 == unlocked_through and level_index + 1 < level_count:
		unlocked_through += 1
	if level_id == 15 and best_for(15) > 0:
		upgrade_unlocked = true
	save_file()
	return {
		"stars": stars,
		"coins": gained,
		"balance": coins,
		"undos": undos,
		"undo_limit": undo_limit,
		"temp_slot_used": temp_slot_used,
	}


func try_spend(amount: int) -> bool:
	if amount <= 0 or coins < amount:
		return false
	coins -= amount
	save_file()
	return true


func _read_test_ledger(raw: Variant) -> void:
	test_no_forced_ads = false
	test_transactions = {}
	temp_level_id = -1
	temp_is_daily = false
	interstitial_armed = false
	interstitial_count = 0
	last_ad_ms = -1
	if typeof(raw) != TYPE_DICTIONARY:
		_sync_interstitial()
		return
	test_no_forced_ads = bool(raw.get("no_forced_ads", false))
	temp_level_id = int(raw.get("temp_level_id", -1))
	temp_is_daily = bool(raw.get("temp_is_daily", false))
	interstitial_armed = bool(raw.get("interstitial_armed", false))
	interstitial_count = int(raw.get("interstitial_count", 0))
	last_ad_ms = int(raw.get("last_ad_ms", -1))
	var txs: Variant = raw.get("transactions", {})
	if typeof(txs) == TYPE_DICTIONARY:
		for key in txs:
			if bool(txs[key]):
				test_transactions[str(key)] = true
	_sync_interstitial()


func _sync_interstitial() -> void:
	if best_for(10) > 0:
		interstitial_armed = true


func now_ms() -> int:
	if test_now_ms >= 0:
		return test_now_ms
	return int(Time.get_unix_time_from_system() * 1000.0)


func stamp_ad() -> void:
	last_ad_ms = now_ms()
	save_file()


func temp_active(level_id: int, is_daily: bool) -> bool:
	return temp_level_id == level_id and temp_is_daily == is_daily


func clear_temp_for_other(level_id: int, is_daily: bool) -> void:
	if temp_level_id < 0:
		return
	if temp_active(level_id, is_daily):
		return
	temp_level_id = -1
	temp_is_daily = false
	save_file()


func finish_temp() -> void:
	if temp_level_id < 0:
		return
	temp_level_id = -1
	temp_is_daily = false
	save_file()


func buy_temp(level_id: int, is_daily: bool) -> Dictionary:
	if temp_active(level_id, is_daily):
		return {"ok": false, "reason": "active"}
	if not try_spend(TEMP_PRICE):
		return {"ok": false, "reason": "coins"}
	temp_level_id = level_id
	temp_is_daily = is_daily
	save_file()
	return {"ok": true, "reason": ""}


func grant_temp(level_id: int, is_daily: bool) -> Dictionary:
	if temp_active(level_id, is_daily):
		return {"ok": false, "reason": "active"}
	temp_level_id = level_id
	temp_is_daily = is_daily
	save_file()
	return {"ok": true, "reason": ""}


## Returns whether a simulated interstitial should show before the results.
func on_main_clear(level_id: int) -> bool:
	if not interstitial_armed:
		if level_id == 10 and best_for(10) > 0:
			interstitial_armed = true
			interstitial_count = 0
			save_file()
		return false
	interstitial_count += 1
	var due := interstitial_count >= 3
	if due:
		interstitial_count = 0
	var show := false
	if due and not test_no_forced_ads:
		if last_ad_ms < 0 or now_ms() - last_ad_ms >= AD_GAP_MS:
			show = true
	save_file()
	return show


func buy_second_hold() -> Dictionary:
	if second_hold:
		return {"ok": false, "reason": "owned", "coins": coins}
	if not upgrade_unlocked:
		return {"ok": false, "reason": "locked", "coins": coins}
	if coins < HOLD_PRICE:
		return {"ok": false, "reason": "coins", "coins": coins}
	coins -= HOLD_PRICE
	second_hold = true
	save_file()
	return {"ok": true, "reason": "", "coins": coins}


func record_daily_clear() -> Dictionary:
	var device := utc_day()
	if highest_utc_day >= 0 and device < highest_utc_day:
		return {"paid": false, "coins": 0, "reason": "backward", "balance": coins}
	if not daily_unlocked():
		return {"paid": false, "coins": 0, "reason": "locked", "balance": coins}
	var day := observed_day()
	if device > highest_utc_day:
		highest_utc_day = device
	if daily_cleared_day == day:
		return {"paid": false, "coins": 0, "reason": "repeat", "balance": coins}
	daily_cleared_day = day
	coins += DAILY_REWARD
	save_file()
	return {"paid": true, "coins": DAILY_REWARD, "reason": "", "balance": coins}


## Credits the streak once per UTC day. Returns a short notice. Does not remove coins.
func on_hub_visit() -> String:
	var device := utc_day()
	if highest_utc_day < 0:
		highest_utc_day = device
	elif device > highest_utc_day:
		highest_utc_day = device
	elif device < highest_utc_day:
		return "Clock is behind the last day seen. No new streak or daily reward. Days change at 00:00 UTC."
	if streak_last_day == device:
		return "Streak already credited today. Days change at 00:00 UTC."
	return _credit_streak(device)


func _credit_streak(today: int) -> String:
	var step := 1
	var used_token := false
	if streak_last_day < 0:
		step = 1
	else:
		var gap := today - streak_last_day
		if gap == 1:
			step = streak_next
		elif gap == 2 and freeze_tokens > 0:
			freeze_tokens = 0
			used_token = true
			step = streak_next
		else:
			step = 1
	step = clampi(step, 1, 7)
	var reward := int(STREAK_REWARDS[step - 1])
	coins += reward
	streak_last_day = today
	var gained_token := false
	if step == 7:
		if freeze_tokens < 1:
			freeze_tokens = 1
			gained_token = true
		streak_next = 1
	else:
		streak_next = step + 1
	save_file()
	var note := "Streak day %d · +%d coins." % [step, reward]
	if used_token:
		note = "Freeze token used. " + note
	if gained_token:
		note += " Freeze token 1."
	return note + " Days change at 00:00 UTC."
