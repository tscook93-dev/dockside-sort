extends SceneTree

const PuzzleScript := preload("res://scripts/puzzle.gd")
const ProgressScript := preload("res://scripts/progress.gd")
const OffersScript := preload("res://scripts/offers.gd")

var failures := 0


func _init() -> void:
	_run()
	if failures == 0:
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("CHECKS FAILED: %d" % failures)
		quit(1)


func _run() -> void:
	var paths := PuzzleScript.list_level_paths()
	_check(paths.size() == 30, "thirty level files, got %d" % paths.size())
	if paths.size() != 30:
		return
	var levels: Array = []
	for path in paths:
		levels.append(PuzzleScript.load_level(path))
	_check(str(levels[0].get("title", "")) == "Morning Shift", "level 1 title")
	_check(str(levels[7].get("title", "")) == "The Key", "level 8 title")
	_check(str(levels[12].get("title", "")) == "Double High", "level 13 title")
	_check(str(levels[29].get("title", "")) == "Sydney Mix", "level 30 title")
	_check_progress_to_30()

	_play_script(levels[0], _level1_win(), true, false, "level 1 scripted win")
	_play_script(levels[2], _level2_win(), true, false, "level 3 scripted win")
	_play_script(levels[2], _level2_fail(), false, true, "level 3 scripted soft fail")
	_play_script(levels[3], _level3_win(), true, false, "level 4 scripted win")
	_play_script(levels[3], _level3_fail(), false, true, "level 4 scripted soft fail")
	_check_undo_depth(levels[2])
	_check_illegal_does_not_record(levels[0])
	_check_scoring_and_save()
	_check_m4(levels[0], levels[2])
	_check_m5()

	var open1 := _search(levels[0], true)
	_check(int(open1["solution"]) == 9, "level 1 solution length %s" % str(open1["solution"]))
	_check(int(open1["fail"]) < 0, "level 1 has no reachable soft fail")
	var no_hold1 := _search(levels[0], false)
	_check(int(no_hold1["solution"]) == 9, "level 1 solvable without the hold")

	for i in [2, 3]:
		var with_hold: Dictionary = _search(levels[i], true)
		var no_hold: Dictionary = _search(levels[i], false)
		_check(int(with_hold["solution"]) > 0, "level %d solvable" % (i + 1))
		_check(int(with_hold["fail"]) > 0, "level %d soft-fail reachable" % (i + 1))
		_check(int(no_hold["solution"]) < 0, "level %d requires the hold" % (i + 1))


func _play_script(data: Dictionary, moves: Array, expect_win: bool, expect_fail: bool, label: String) -> void:
	var puzzle = PuzzleScript.new()
	puzzle.setup(data)
	for move in moves:
		var err: String = puzzle.apply_move(move)
		if err != "":
			_check(false, "%s rejected %s (%s)" % [label, str(move), err])
			return
	_check(puzzle.is_win() == expect_win, "%s win=%s" % [label, str(puzzle.is_win())])
	_check(puzzle.is_soft_fail() == expect_fail, "%s fail=%s" % [label, str(puzzle.is_soft_fail())])


func _check_undo_depth(data: Dictionary) -> void:
	var puzzle = PuzzleScript.new()
	puzzle.setup(data)
	var start: String = puzzle.state_key()
	for move in _level2_win():
		var err: String = puzzle.apply_move(move)
		_check(err == "", "undo setup move %s" % err)
	_check(puzzle.history.size() >= 10, "history depth %d" % puzzle.history.size())
	_check(puzzle.is_win(), "undo setup reached a win")
	for _i in puzzle.history.size():
		_check(puzzle.undo(), "undo step")
	_check(puzzle.state_key() == start, "ten-plus undos restore the start")
	_check(puzzle.moves_done == 0, "undo restores the move count")
	_check(not puzzle.undo(), "empty history does not undo")


func _check_illegal_does_not_record(data: Dictionary) -> void:
	var puzzle = PuzzleScript.new()
	puzzle.setup(data)
	var before: String = puzzle.state_key()
	var err: String = puzzle.move_column_to_berth(0, 1)
	_check(err != "", "wrong colour is rejected")
	_check(puzzle.history.is_empty(), "rejected move is not recorded")
	_check(puzzle.state_key() == before, "rejected move does not change the board")


func _search(data: Dictionary, allow_hold: bool) -> Dictionary:
	var puzzle = PuzzleScript.new()
	puzzle.setup(data)
	var start: Dictionary = puzzle.snapshot()
	var queue: Array = [start]
	var seen := {puzzle.state_key(): true}
	var head := 0
	var solution := -1
	var fail := -1
	while head < queue.size():
		var snap: Dictionary = queue[head]
		head += 1
		puzzle.restore(snap)
		if puzzle.is_win():
			if solution < 0:
				solution = puzzle.moves_done
			continue
		if puzzle.is_soft_fail():
			if fail < 0:
				fail = puzzle.moves_done
			continue
		if solution >= 0 and fail >= 0:
			break
		for move in puzzle.legal_moves(allow_hold):
			puzzle.restore(snap)
			var err: String = puzzle.apply_move(move)
			if err != "":
				continue
			var key := puzzle.state_key()
			if seen.has(key):
				continue
			seen[key] = true
			queue.append(puzzle.snapshot())
			if solution >= 0 and fail >= 0:
				break
	return {"solution": solution, "fail": fail, "seen": seen.size()}


func _level1_win() -> Array:
	var moves: Array = []
	for _n in 3:
		moves.append({"op": "deck_berth", "col": 0, "berth": 0})
	for _n in 3:
		moves.append({"op": "deck_berth", "col": 1, "berth": 1})
	for _n in 3:
		moves.append({"op": "deck_berth", "col": 2, "berth": 2})
	return moves


func _level2_win() -> Array:
	return [
		{"op": "deck_berth", "col": 0, "berth": 0},
		{"op": "deck_berth", "col": 0, "berth": 1},
		{"op": "deck_berth", "col": 0, "berth": 0},
		{"op": "deck_berth", "col": 1, "berth": 1},
		{"op": "deck_hold", "col": 1},
		{"op": "deck_berth", "col": 1, "berth": 1},
		{"op": "deck_berth", "col": 2, "berth": 1},
		{"op": "deck_berth", "col": 2, "berth": 0},
		{"op": "deck_berth", "col": 2, "berth": 1},
		{"op": "hold_berth", "berth": 1},
	]


func _level2_fail() -> Array:
	return [
		{"op": "deck_berth", "col": 0, "berth": 0},
		{"op": "deck_hold", "col": 0},
		{"op": "deck_berth", "col": 0, "berth": 1},
	]


func _level3_win() -> Array:
	return [
		{"op": "deck_berth", "col": 0, "berth": 0},
		{"op": "deck_berth", "col": 0, "berth": 1},
		{"op": "deck_berth", "col": 1, "berth": 0},
		{"op": "deck_hold", "col": 2},
		{"op": "deck_berth", "col": 2, "berth": 1},
		{"op": "deck_berth", "col": 2, "berth": 0},
		{"op": "deck_berth", "col": 0, "berth": 0},
		{"op": "deck_berth", "col": 1, "berth": 0},
		{"op": "deck_berth", "col": 1, "berth": 1},
		{"op": "hold_berth", "berth": 0},
	]


func _level3_fail() -> Array:
	return [
		{"op": "deck_berth", "col": 0, "berth": 0},
		{"op": "deck_hold", "col": 0},
		{"op": "deck_berth", "col": 1, "berth": 1},
	]


func _check_scoring_and_save() -> void:
	_check(ProgressScript.stars_for(0, 0, false) == 3, "zero undos is 3 stars")
	_check(ProgressScript.stars_for(0, 0, true) == 2, "temp slot blocks 3 stars")
	_check(ProgressScript.stars_for(2, 0, false) == 2, "two extra undos is a light assist")
	_check(ProgressScript.stars_for(3, 0, false) == 1, "three extra undos is 1 star")
	_check(ProgressScript.stars_for(1, 1, false) == 3, "within the level limit is 3 stars")
	var path := "user://m2_rules_progress.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var saved = ProgressScript.new()
	saved.path = path
	saved.load_file()
	_check(saved.coins == 0 and saved.unlocked_through == 1, "fresh progress")
	var first: Dictionary = saved.record_clear(0, 1, 3, 0, 0, false)
	_check(int(first["stars"]) == 3 and int(first["coins"]) == 30, "level 1 pays 30")
	_check(saved.unlocked_through == 2 and saved.best_for(1) == 3, "clear unlocks the next level")
	var again: Dictionary = saved.record_clear(0, 1, 3, 4, 0, false)
	_check(int(again["stars"]) == 1 and int(again["coins"]) == 0 and saved.best_for(1) == 3, "a worse replay pays 0 and keeps the best stars")
	var replay: Dictionary = saved.record_clear(0, 1, 3, 0, 0, false)
	_check(int(replay["stars"]) == 3 and int(replay["coins"]) == 0, "replaying a 3-star clear pays 0")
	_check(saved.coins == 30, "replays do not add coins")
	var loaded = ProgressScript.new()
	loaded.path = path
	loaded.load_file()
	_check(loaded.coins == 30 and loaded.unlocked_through == 2 and loaded.best_for(1) == 3, "progress reloads from disk")
	loaded.sound_on = false
	loaded.haptics_on = false
	loaded.save_file()
	var toggles = ProgressScript.new()
	toggles.path = path
	toggles.load_file()
	_check(not toggles.sound_on and not toggles.haptics_on, "settings reload from disk")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_progress_to_30() -> void:
	var path := "user://m3b_progress.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var saved = ProgressScript.new()
	saved.path = path
	for i in 30:
		var result: Dictionary = saved.record_clear(i, i + 1, 30, 0, 0, false)
		_check(int(result["coins"]) == 30, "first clear of level %d pays 30" % (i + 1))
	_check(saved.unlocked_through == 30, "clearing through level 30 unlocks 30")
	var again: Dictionary = saved.record_clear(29, 30, 30, 0, 0, false)
	_check(int(again["coins"]) == 0, "replaying level 30 at 3 stars pays 0")
	saved.mark_ftue(1)
	saved.save_file()
	var loaded = ProgressScript.new()
	loaded.path = path
	loaded.load_file()
	_check(loaded.unlocked_through == 30 and loaded.best_for(30) == 3, "level 30 progress reloads")
	_check(loaded.seen_ftue(1), "skipped tutorial is remembered")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_m4(level1: Dictionary, level3: Dictionary) -> void:
	for slot in 7:
		var mapped = ProgressScript.new()
		mapped.test_utc_day = 70 + slot
		_check(mapped.daily_level_id() == 18 + slot, "UTC day slot %d uses level %d" % [slot, 18 + slot])
	var early = ProgressScript.new()
	early.test_utc_day = 3
	var closed: Dictionary = early.record_daily_clear()
	_check(not bool(closed["paid"]) and early.coins == 0 and early.daily_cleared_day < 0, "daily stays closed before level 5")
	var daily = ProgressScript.new()
	daily.path = "user://m4_daily.cfg"
	daily.test_utc_day = 14
	daily.best_stars = {"5": 3, "18": 1}
	daily.unlocked_through = 8
	daily.coins = 5
	var first: Dictionary = daily.record_daily_clear()
	_check(bool(first["paid"]) and daily.coins == 35, "first daily clear pays 30")
	_check(daily.best_for(18) == 1 and daily.best_for(19) == 0 and daily.unlocked_through == 8, "daily does not change main stars or unlocks")
	var repeat: Dictionary = daily.record_daily_clear()
	_check(not bool(repeat["paid"]) and daily.coins == 35, "the same UTC day pays 0")
	daily.save_file()
	var reloaded = ProgressScript.new()
	reloaded.path = daily.path
	reloaded.test_utc_day = 14
	reloaded.load_file()
	var replay: Dictionary = reloaded.record_daily_clear()
	_check(not bool(replay["paid"]) and reloaded.coins == 35 and reloaded.best_for(18) == 1, "reloading the same UTC day does not pay again")
	reloaded.test_utc_day = 15
	_check(reloaded.daily_level_id() == 19, "the next UTC day uses level 19")
	var nxt: Dictionary = reloaded.record_daily_clear()
	_check(bool(nxt["paid"]) and reloaded.coins == 65 and reloaded.best_for(19) == 0 and reloaded.unlocked_through == 8, "a new UTC day pays 30 without main rewards")
	var offer = ProgressScript.new()
	offer.path = "user://m4_hold.cfg"
	offer.coins = 500
	var locked: Dictionary = offer.buy_second_hold()
	_check(not bool(locked["ok"]) and offer.coins == 500 and not offer.second_hold, "the hold cannot be bought before level 15")
	offer.record_clear(14, 15, 30, 0, 3, false)
	_check(offer.upgrade_unlocked and not offer.second_hold, "the first level 15 clear unlocks the offer")
	offer.coins = 299
	var poor: Dictionary = offer.buy_second_hold()
	_check(not bool(poor["ok"]) and offer.coins == 299 and not offer.second_hold, "299 coins does not debit or grant the hold")
	offer.coins = 300
	var bought: Dictionary = offer.buy_second_hold()
	_check(bool(bought["ok"]) and offer.coins == 0 and offer.second_hold, "300 coins buys the hold once")
	var twice: Dictionary = offer.buy_second_hold()
	_check(not bool(twice["ok"]) and offer.coins == 0, "a repeat tap does not debit again")
	var held = ProgressScript.new()
	held.path = offer.path
	held.load_file()
	var after: Dictionary = held.buy_second_hold()
	_check(held.second_hold and held.coins == 0 and not bool(after["ok"]) and held.upgrade_unlocked, "the purchase reloads once")
	var legacy_path := "user://m4_legacy.cfg"
	var old := ConfigFile.new()
	old.set_value("player", "coins", 40)
	old.set_value("player", "unlocked_through", 6)
	old.set_value("player", "stars", {"1": 3, "5": 1, "15": 2})
	old.save(legacy_path)
	var legacy = ProgressScript.new()
	legacy.path = legacy_path
	legacy.load_file()
	_check(legacy.coins == 40 and legacy.unlocked_through == 6 and legacy.best_for(1) == 3 and legacy.best_for(15) == 2, "a legacy save keeps stars, coins, and unlocks")
	_check(legacy.upgrade_unlocked and not legacy.second_hold and legacy.freeze_tokens == 0, "a legacy level 15 clear offers the hold and grants nothing else")
	var streak = ProgressScript.new()
	streak.path = "user://m4_streak.cfg"
	streak.test_utc_day = 200
	streak.on_hub_visit()
	_check(streak.coins == 10 and streak.streak_next == 2, "the first hub visit credits streak day 1")
	streak.on_hub_visit()
	_check(streak.coins == 10, "the same UTC day does not credit the streak again")
	for step in 6:
		streak.test_utc_day = 201 + step
		streak.on_hub_visit()
	_check(streak.freeze_tokens == 1 and streak.streak_next == 1, "day 7 grants one freeze token and the next step is day 1")
	var before_cycle: int = streak.coins
	streak.test_utc_day = 207
	streak.on_hub_visit()
	_check(streak.coins == before_cycle + 10 and streak.freeze_tokens == 1 and streak.streak_next == 2, "the day after day 7 starts a new day 1 and stays at one token")
	for step in 6:
		streak.test_utc_day = 208 + step
		streak.on_hub_visit()
	_check(streak.freeze_tokens == 1, "completing day 7 again does not raise the token above 1")
	var missed = ProgressScript.new()
	missed.test_utc_day = 10
	missed.on_hub_visit()
	missed.test_utc_day = 11
	missed.on_hub_visit()
	missed.test_utc_day = 12
	missed.on_hub_visit()
	var missed_coins: int = missed.coins
	missed.test_utc_day = 14
	missed.on_hub_visit()
	_check(missed.freeze_tokens == 0 and missed.streak_next == 2 and missed.coins == missed_coins + 10, "one missed day without a token restarts at day 1")
	var kept = ProgressScript.new()
	kept.test_utc_day = 10
	kept.on_hub_visit()
	kept.test_utc_day = 11
	kept.on_hub_visit()
	kept.test_utc_day = 12
	kept.on_hub_visit()
	kept.freeze_tokens = 1
	var kept_coins: int = kept.coins
	kept.test_utc_day = 14
	kept.on_hub_visit()
	_check(kept.freeze_tokens == 0 and kept.streak_next == 5 and kept.coins == kept_coins + 15, "one missed day spends the token and continues the next step")
	var wide = ProgressScript.new()
	wide.test_utc_day = 10
	wide.on_hub_visit()
	wide.test_utc_day = 11
	wide.on_hub_visit()
	wide.test_utc_day = 12
	wide.on_hub_visit()
	wide.freeze_tokens = 1
	var wide_coins: int = wide.coins
	wide.test_utc_day = 15
	wide.on_hub_visit()
	_check(wide.freeze_tokens == 1 and wide.streak_next == 2 and wide.coins == wide_coins + 10, "two missed days reset to day 1 and keep the token")
	var back = ProgressScript.new()
	back.test_utc_day = 50
	back.best_stars = {"5": 3}
	back.on_hub_visit()
	var paid: Dictionary = back.record_daily_clear()
	var back_coins: int = back.coins
	_check(bool(paid["paid"]), "daily can pay on the observed day")
	back.test_utc_day = 40
	back.on_hub_visit()
	var denied: Dictionary = back.record_daily_clear()
	_check(back.coins == back_coins and not bool(denied["paid"]) and back.highest_utc_day == 50 and back.streak_last_day == 50, "a backward clock creates no new claim")
	var puzzle = PuzzleScript.new()
	puzzle.setup(level1)
	_check(puzzle.permanent_slots == 1, "a fresh puzzle has one hold for the solver")
	puzzle.permanent_slots = 2
	var parked: String = puzzle.move_column_to_hold(0, 1)
	_check(parked == "" and puzzle.hold2 != "" and puzzle.hold == "" and not puzzle.temp_slot_used, "the second hold parks a container and is not a temporary slot")
	_check(puzzle.undo() and puzzle.hold2 == "" and puzzle.hold == "", "undo restores the second hold")
	puzzle.permanent_slots = 2
	puzzle.move_column_to_hold(0, 1)
	_check(ProgressScript.stars_for(puzzle.undos_used, puzzle.undo_limit, puzzle.temp_slot_used) == 3, "using the permanent second hold still scores 3 stars")
	puzzle.setup(level1)
	_check(puzzle.hold == "" and puzzle.hold2 == "" and puzzle.permanent_slots == 1, "restart clears both holds")
	var wide_hold = PuzzleScript.new()
	wide_hold.setup(level3)
	wide_hold.permanent_slots = 2
	for move in _level2_fail():
		wide_hold.apply_move(move)
	_check(not wide_hold.is_soft_fail(), "an empty second permanent hold is still a legal move")
	for path in ["user://m4_daily.cfg", "user://m4_hold.cfg", "user://m4_legacy.cfg", "user://m4_streak.cfg"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_m5() -> void:
	var offers = OffersScript.new()
	var started: Dictionary = offers.begin_rewarded("demo", 4)
	_check(bool(started["ok"]), "a local test reward can start")
	var busy: Dictionary = offers.begin_rewarded("demo", 4)
	_check(not bool(busy["ok"]) and str(busy["reason"]) == "busy", "a busy provider does not start a second reward")
	var cancelled: Dictionary = offers.resolve_rewarded(int(started["id"]), "cancelled", 4)
	_check(not bool(cancelled["granted"]), "cancel grants nothing")
	var again: Dictionary = offers.resolve_rewarded(int(started["id"]), "completed", 4)
	_check(not bool(again["granted"]) and str(again["reason"]) == "duplicate", "a second callback grants nothing")
	var failed_start: Dictionary = offers.begin_rewarded("demo", 4)
	var failed: Dictionary = offers.resolve_rewarded(int(failed_start["id"]), "failed", 4)
	_check(not bool(failed["granted"]), "failure grants nothing")
	var unavailable_start: Dictionary = offers.begin_rewarded("demo", 4)
	var unavailable: Dictionary = offers.resolve_rewarded(int(unavailable_start["id"]), "unavailable", 4)
	_check(not bool(unavailable["granted"]), "unavailable grants nothing")
	var ok_start: Dictionary = offers.begin_rewarded("double_coins", 7)
	var stale: Dictionary = offers.resolve_rewarded(int(ok_start["id"]), "completed", 8)
	_check(not bool(stale["granted"]) and str(stale["reason"]) == "stale", "an old level callback does not grant")
	var once_start: Dictionary = offers.begin_rewarded("double_coins", 9)
	var once: Dictionary = offers.resolve_rewarded(int(once_start["id"]), "completed", 9)
	_check(bool(once["granted"]), "one completed callback grants once")
	var held: Dictionary = offers.purchase("pack-1", "cancelled", true, 50)
	_check(not bool(held["ok"]) and int(held["coins"]) == 0, "a cancelled purchase grants nothing")
	var pack: Dictionary = offers.purchase("pack-1", "completed", true, 50)
	_check(bool(pack["ok"]) and int(pack["coins"]) == 50, "a completed test purchase reports its coins once")
	var pack_again: Dictionary = offers.purchase("pack-1", "completed", true, 50)
	_check(not bool(pack_again["ok"]) and int(pack_again["coins"]) == 0, "the same transaction does not pay twice")
	var entitlement: Dictionary = offers.purchase("ads-1", "completed", false, 100)
	_check(bool(entitlement["ok"]) and offers.no_forced_ads and int(entitlement["coins"]) == 0, "No forced ads adds no coins")
	var restored: Dictionary = offers.restore()
	_check(bool(restored["no_forced_ads"]) and int(restored["coins"]) == 0, "restore returns the entitlement and no coins")
	_check(not offers.may_show_interstitial("break", "completed"), "no interstitial without an approved cadence")
	offers.cadence_enabled = true
	_check(not offers.may_show_interstitial("break", "completed"), "No forced ads suppresses the interstitial")
	offers.no_forced_ads = false
	_check(not offers.may_show_interstitial("puzzle", "completed"), "no interstitial mid-puzzle")
	_check(not offers.may_show_interstitial("open", "completed"), "no interstitial on open")
	_check(not offers.may_show_interstitial("exit", "failed"), "no interstitial on exit")
	_check(offers.may_show_interstitial("break", "completed"), "a natural break can show when cadence is enabled in a test")
	offers.note_break(true)
	_check(not offers.may_show_interstitial("break", "failed"), "interstitials are not back to back")
	offers.note_break(false)
	_check(offers.may_show_interstitial("break", "failed"), "a later break can show after one was skipped")
	var wallet = ProgressScript.new()
	wallet.path = "user://m5_wallet.cfg"
	wallet.coins = 20
	_check(not wallet.try_spend(-5) and wallet.coins == 20, "a negative spend does not change coins")
	_check(not wallet.try_spend(21) and wallet.coins == 20, "an unaffordable spend does not change coins")
	_check(wallet.try_spend(5) and wallet.coins == 15, "an affordable spend debits once")
	var legacy = ProgressScript.new()
	legacy.path = "user://m5_legacy.cfg"
	var old := ConfigFile.new()
	old.set_value("player", "coins", 80)
	old.set_value("player", "unlocked_through", 4)
	old.set_value("player", "stars", {"2": 3})
	old.save(legacy.path)
	legacy.load_file()
	_check(legacy.coins == 80 and legacy.unlocked_through == 4 and legacy.best_for(2) == 3 and not legacy.test_no_forced_ads, "a legacy save ignores the local test ledger")
	for path in ["user://m5_wallet.cfg", "user://m5_legacy.cfg"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(cond: bool, message: String) -> void:
	if cond:
		print("ok: ", message)
	else:
		failures += 1
		print("FAIL: ", message)
