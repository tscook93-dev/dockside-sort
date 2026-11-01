extends SceneTree

const PuzzleScript := preload("res://scripts/puzzle.gd")
const ProgressScript := preload("res://scripts/progress.gd")

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
	_check(paths.size() == 3, "three level files, got %d" % paths.size())
	if paths.size() != 3:
		return
	var levels: Array = []
	for path in paths:
		levels.append(PuzzleScript.load_level(path))
	_check(str(levels[0].get("title", "")) == "Morning Shift", "level 1 title")
	_check(str(levels[1].get("title", "")) == "Tight Berth", "level 2 title")
	_check(str(levels[2].get("title", "")) == "Cross Load", "level 3 title")

	_play_script(levels[0], _level1_win(), true, false, "level 1 scripted win")
	_play_script(levels[1], _level2_win(), true, false, "level 2 scripted win")
	_play_script(levels[1], _level2_fail(), false, true, "level 2 scripted soft fail")
	_play_script(levels[2], _level3_win(), true, false, "level 3 scripted win")
	_play_script(levels[2], _level3_fail(), false, true, "level 3 scripted soft fail")
	_check_undo_depth(levels[1])
	_check_illegal_does_not_record(levels[0])
	_check_scoring_and_save()

	var open1 := _search(levels[0], true)
	_check(int(open1["solution"]) == 9, "level 1 solution length %s" % str(open1["solution"]))
	_check(int(open1["fail"]) < 0, "level 1 has no reachable soft fail")
	var no_hold1 := _search(levels[0], false)
	_check(int(no_hold1["solution"]) == 9, "level 1 solvable without the hold")

	for i in [1, 2]:
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
	_check(int(again["stars"]) == 1 and saved.best_for(1) == 3, "a worse clear keeps the best stars")
	_check(saved.coins == 40, "a replay still pays its own coins")
	var loaded = ProgressScript.new()
	loaded.path = path
	loaded.load_file()
	_check(loaded.coins == 40 and loaded.unlocked_through == 2 and loaded.best_for(1) == 3, "progress reloads from disk")
	loaded.sound_on = false
	loaded.haptics_on = false
	loaded.save_file()
	var toggles = ProgressScript.new()
	toggles.path = path
	toggles.load_file()
	_check(not toggles.sound_on and not toggles.haptics_on, "settings reload from disk")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(cond: bool, message: String) -> void:
	if cond:
		print("ok: ", message)
	else:
		failures += 1
		print("FAIL: ", message)
