extends RefCounted

## Colour-stack rules for Dockside Sort (Milestone 1).
##
## Deck columns are top-first: index 0 is the only container that can move.
## A berth accepts a container when it is under capacity and either empty
## (any colour, or the pinned colour) or its top container is the same colour.
## A berth ships — containers leave play and the berth clears — when it
## reaches capacity. Mixed colours cannot be stacked, so a full berth is
## always one colour. The hold stores one container and is not a berth.

const HISTORY_LIMIT := 40

var id := 0
var title := ""
var blurb := ""
var capacity := 3
var columns: Array = []
var locks: Array = []
var berths: Array = []
var hold := ""
var history: Array = []
var moves_done := 0
var last_shipped := ""

static func list_level_paths() -> PackedStringArray:
	var dir := DirAccess.open("res://levels")
	var names: Array[String] = []
	if dir == null:
		return PackedStringArray()
	for file in dir.get_files():
		var name := str(file)
		if name.ends_with(".json.remap"):
			name = name.trim_suffix(".remap")
		if not name.ends_with(".json"):
			continue
		if not names.has(name):
			names.append(name)
	names.sort()
	var out := PackedStringArray()
	for name in names:
		out.append("res://levels/%s" % name)
	return out

static func load_level(path: String) -> Dictionary:
	var res: Variant = load(path)
	if res is JSON:
		var data: Variant = (res as JSON).data
		if typeof(data) == TYPE_DICTIONARY:
			return data
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	push_error("Could not read level %s" % path)
	return {}

func setup(data: Dictionary) -> void:
	id = int(data.get("id", 0))
	title = str(data.get("title", "Level"))
	blurb = str(data.get("blurb", ""))
	capacity = int(data.get("capacity", 3))
	columns = []
	for col in data.get("columns", []):
		var stack: Array = []
		for color in col:
			stack.append(str(color))
		columns.append(stack)
	locks = []
	berths = []
	for entry in data.get("berths", []):
		locks.append(str(entry))
		berths.append([])
	hold = ""
	history = []
	moves_done = 0
	last_shipped = ""

func can_accept(color: String, berth: int) -> bool:
	if berth < 0 or berth >= berths.size():
		return false
	var stack: Array = berths[berth]
	if stack.size() >= capacity:
		return false
	if stack.is_empty():
		var lock: String = locks[berth]
		return lock == "" or lock == color
	return str(stack.back()) == color

func reject_reason(color: String, berth: int) -> String:
	if berth < 0 or berth >= berths.size():
		return "That stack is not on the dock."
	var stack: Array = berths[berth]
	if stack.size() >= capacity:
		return "Stack %d is full." % (berth + 1)
	if stack.is_empty():
		var lock: String = locks[berth]
		if lock != "" and lock != color:
			return "Stack %d only takes %s." % [berth + 1, pretty(lock)]
		return "That stack cannot take %s." % pretty(color)
	return "Stack %d is %s. %s cannot go on it." % [berth + 1, pretty(str(stack.back())), pretty(color)]

func move_column_to_berth(col: int, berth: int) -> String:
	var color := _column_top(col)
	if color == "":
		return "Nothing on that column to move."
	if not can_accept(color, berth):
		return reject_reason(color, berth)
	_push_history()
	(columns[col] as Array).pop_front()
	(berths[berth] as Array).append(color)
	_ship_if_full(berth)
	moves_done += 1
	return ""

func move_column_to_hold(col: int) -> String:
	var color := _column_top(col)
	if color == "":
		return "Nothing on that column to move."
	if hold != "":
		return "The hold already has a container."
	_push_history()
	(columns[col] as Array).pop_front()
	hold = color
	last_shipped = ""
	moves_done += 1
	return ""

func move_hold_to_berth(berth: int) -> String:
	if hold == "":
		return "The hold is empty."
	if not can_accept(hold, berth):
		return reject_reason(hold, berth)
	var color := hold
	_push_history()
	hold = ""
	(berths[berth] as Array).append(color)
	_ship_if_full(berth)
	moves_done += 1
	return ""

func undo() -> bool:
	if history.is_empty():
		return false
	var snap: Dictionary = history.pop_back()
	_restore_snap(snap)
	return true

func is_win() -> bool:
	if hold != "":
		return false
	for col in columns:
		if not (col as Array).is_empty():
			return false
	for stack in berths:
		if not (stack as Array).is_empty():
			return false
	return true

func is_soft_fail() -> bool:
	if is_win():
		return false
	if hold == "" and _any_column():
		return false
	if hold != "" and _any_berth_accepts(hold):
		return false
	for col in columns:
		var stack: Array = col
		if stack.is_empty():
			continue
		if _any_berth_accepts(str(stack[0])):
			return false
	return true

func legal_moves(allow_hold: bool = true) -> Array:
	var out: Array = []
	for i in columns.size():
		var stack: Array = columns[i]
		if stack.is_empty():
			continue
		var color := str(stack[0])
		for j in berths.size():
			if can_accept(color, j):
				out.append({"op": "deck_berth", "col": i, "berth": j})
		if allow_hold and hold == "":
			out.append({"op": "deck_hold", "col": i})
	if allow_hold and hold != "":
		for j in berths.size():
			if can_accept(hold, j):
				out.append({"op": "hold_berth", "berth": j})
	return out

func apply_move(move: Dictionary) -> String:
	match str(move.get("op", "")):
		"deck_berth":
			return move_column_to_berth(int(move["col"]), int(move["berth"]))
		"deck_hold":
			return move_column_to_hold(int(move["col"]))
		"hold_berth":
			return move_hold_to_berth(int(move["berth"]))
	return "Unknown move."

func state_key() -> String:
	var parts: PackedStringArray = []
	for col in columns:
		parts.append(",".join(col))
		parts.append("/")
	parts.append("#")
	for stack in berths:
		parts.append(",".join(stack))
		parts.append("/")
	parts.append("~")
	parts.append(hold)
	return "".join(parts)

func snapshot() -> Dictionary:
	return {
		"columns": _clone(columns),
		"berths": _clone(berths),
		"hold": hold,
		"moves_done": moves_done,
	}

func restore(snap: Dictionary) -> void:
	_restore_snap(snap)
	history.clear()

func pretty(color: String) -> String:
	if color == "":
		return "Empty"
	return color.substr(0, 1).to_upper() + color.substr(1)

func _column_top(col: int) -> String:
	if col < 0 or col >= columns.size():
		return ""
	var stack: Array = columns[col]
	if stack.is_empty():
		return ""
	return str(stack[0])

func _any_column() -> bool:
	for col in columns:
		if not (col as Array).is_empty():
			return true
	return false

func _any_berth_accepts(color: String) -> bool:
	for j in berths.size():
		if can_accept(color, j):
			return true
	return false

func _ship_if_full(berth: int) -> void:
	var stack: Array = berths[berth]
	last_shipped = ""
	if stack.size() == capacity:
		last_shipped = str(stack[0])
		berths[berth] = []

func _push_history() -> void:
	history.append(snapshot())
	if history.size() > HISTORY_LIMIT:
		history.pop_front()

func _restore_snap(snap: Dictionary) -> void:
	columns = _clone(snap["columns"])
	berths = _clone(snap["berths"])
	hold = str(snap["hold"])
	moves_done = int(snap["moves_done"])
	last_shipped = ""

func _clone(src: Array) -> Array:
	var out: Array = []
	for item in src:
		out.append((item as Array).duplicate())
	return out
