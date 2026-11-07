extends SceneTree

const PuzzleScript := preload("res://scripts/puzzle.gd")


func _init() -> void:
	var paths := PuzzleScript.list_level_paths()
	if paths.size() != 17:
		print("EXPECTED 17 LEVELS, got ", paths.size())
		quit(1)
		return
	var failed := 0
	for path in paths:
		var data: Dictionary = PuzzleScript.load_level(path)
		var id := int(data.get("id", 0))
		var reason := _check_shape(data)
		if reason != "":
			print("LEVEL %d SHAPE: %s" % [id, reason])
			failed += 1
			continue
		var puzzle = PuzzleScript.new()
		puzzle.setup(data)
		var length := _shortest(puzzle)
		if length < 0:
			print("LEVEL %d UNSOLVABLE with 1 hold and no undos" % id)
			failed += 1
		else:
			print("level %d solvable in %d moves, 0 undos, 1 hold" % [id, length])
	if failed > 0:
		print("SOLVER FAILED: %d" % failed)
		quit(1)
	else:
		print("ALL 17 LEVELS SOLVABLE")
		quit(0)


func _check_shape(data: Dictionary) -> String:
	var id := int(data.get("id", 0))
	var capacity := int(data.get("capacity", 0))
	if id >= 1 and id <= 17 and capacity != 3:
		return "capacity %d, want 3" % capacity
	var counts := {}
	var keys := 0
	var locked := 0
	var columns: Array = data.get("columns", [])
	for col in columns:
		for token in col:
			var name := str(token)
			if name == "key":
				keys += 1
			elif name.begins_with("locked:"):
				locked += 1
				var color := name.substr(7)
				counts[color] = int(counts.get(color, 0)) + 1
			else:
				counts[name] = int(counts.get(name, 0)) + 1
	for color in counts:
		if int(counts[color]) % capacity != 0:
			return "%s count %d is not a multiple of %d" % [color, int(counts[color]), capacity]
	if locked > 0 and keys < 1:
		return "locked containers but no key"
	var doubles: Array = data.get("double_high", [])
	for entry in doubles:
		var index := int(entry)
		if index < 0 or index >= columns.size() or (columns[index] as Array).size() != 2:
			return "double-high column %d is not exactly two containers" % index
	if id <= 2:
		for berth in data.get("berths", []):
			if str(berth) == "":
				return "levels 1-2 must be pinned"
	if id == 11 or id == 12:
		var saw := false
		for col in columns:
			for token in col:
				if str(token).contains("indigo"):
					saw = true
		if not saw:
			return "missing indigo"
	return ""


func _shortest(puzzle) -> int:
	var origin: Dictionary = puzzle.snapshot()
	var queue: Array = [origin]
	var seen := {puzzle.state_key(): true}
	var head := 0
	while head < queue.size():
		var snap: Dictionary = queue[head]
		head += 1
		puzzle.restore(snap)
		if puzzle.is_win():
			return int(puzzle.moves_done)
		for move in puzzle.legal_moves(true):
			puzzle.restore(snap)
			if puzzle.apply_move(move) != "":
				continue
			var state_name: String = puzzle.state_key()
			if seen.has(state_name):
				continue
			seen[state_name] = true
			queue.append(puzzle.snapshot())
	return -1
