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
## Second permanent hold. Stays empty unless permanent_slots is 2. Not a temporary assist.
var hold2 := ""
var permanent_slots := 1
var history: Array = []
var moves_done := 0
var undos_used := 0
var undo_limit := 0
## Reserved for the temporary hold slot. Nothing sets this true until M5.
var temp_slot_used := false
var double_high: Array = []
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
	undo_limit = int(data.get("undo_limit", 0))
	double_high = []
	for entry in data.get("double_high", []):
		double_high.append(int(entry))
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
	hold2 = ""
	permanent_slots = 1
	history = []
	moves_done = 0
	undos_used = 0
	temp_slot_used = false
	last_shipped = ""

static func is_key(token: String) -> bool:
	return token == "key"


static func is_locked(token: String) -> bool:
	return token.begins_with("locked:")


static func cargo_color(token: String) -> String:
	if token.begins_with("locked:"):
		return token.substr(7)
	return token


func deck_has_key() -> bool:
	for col in columns:
		for token in col:
			if str(token) == "key":
				return true
	return false


func is_double_column(col: int) -> bool:
	return double_high.has(col)


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
	var token := _column_top(col)
	var blocked := _blocked_reason(token)
	if blocked != "":
		return blocked
	var color := cargo_color(token)
	if not can_accept(color, berth):
		return reject_reason(color, berth)
	_push_history()
	(columns[col] as Array).pop_front()
	(berths[berth] as Array).append(color)
	_ship_if_full(berth)
	moves_done += 1
	return ""

func hold_color(slot: int) -> String:
	return hold2 if slot == 1 else hold


func move_column_to_hold(col: int, slot: int = 0) -> String:
	var token := _column_top(col)
	var blocked := _blocked_reason(token)
	if blocked != "":
		return blocked
	if slot == 1 and permanent_slots < 2:
		return "The second hold is not open."
	if hold_color(slot) != "":
		return "That hold already has a container."
	_push_history()
	(columns[col] as Array).pop_front()
	var color := cargo_color(token)
	if slot == 1:
		hold2 = color
	else:
		hold = color
	last_shipped = ""
	moves_done += 1
	return ""

func collect_key(col: int) -> String:
	if _column_top(col) != "key":
		return "That is not a key."
	_push_history()
	(columns[col] as Array).pop_front()
	last_shipped = ""
	moves_done += 1
	return ""

func move_hold_to_berth(berth: int, slot: int = 0) -> String:
	var color := hold_color(slot)
	if color == "":
		return "The hold is empty."
	if not can_accept(color, berth):
		return reject_reason(color, berth)
	_push_history()
	if slot == 1:
		hold2 = ""
	else:
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
	undos_used += 1
	return true

func is_win() -> bool:
	if hold != "" or hold2 != "":
		return false
	for col in columns:
		if not (col as Array).is_empty():
			return false
	for stack in berths:
		if not (stack as Array).is_empty():
			return false
	return true

func is_soft_fail() -> bool:
	return not is_win() and legal_moves(true).is_empty()

func legal_moves(allow_hold: bool = true) -> Array:
	var out: Array = []
	var key_blocks := deck_has_key()
	for i in columns.size():
		var stack: Array = columns[i]
		if stack.is_empty():
			continue
		var token := str(stack[0])
		if token == "key":
			out.append({"op": "collect", "col": i})
			continue
		if is_locked(token) and key_blocks:
			continue
		var color := cargo_color(token)
		for j in berths.size():
			if can_accept(color, j):
				out.append({"op": "deck_berth", "col": i, "berth": j})
		if allow_hold and hold == "":
			out.append({"op": "deck_hold", "col": i, "slot": 0})
		if allow_hold and permanent_slots >= 2 and hold2 == "":
			out.append({"op": "deck_hold", "col": i, "slot": 1})
	if allow_hold and hold != "":
		for j in berths.size():
			if can_accept(hold, j):
				out.append({"op": "hold_berth", "berth": j, "slot": 0})
	if allow_hold and hold2 != "":
		for j in berths.size():
			if can_accept(hold2, j):
				out.append({"op": "hold_berth", "berth": j, "slot": 1})
	return out

func apply_move(move: Dictionary) -> String:
	match str(move.get("op", "")):
		"deck_berth":
			return move_column_to_berth(int(move["col"]), int(move["berth"]))
		"deck_hold":
			return move_column_to_hold(int(move["col"]), int(move.get("slot", 0)))
		"hold_berth":
			return move_hold_to_berth(int(move["berth"]), int(move.get("slot", 0)))
		"collect":
			return collect_key(int(move["col"]))
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
	parts.append("|")
	parts.append(hold2)
	return "".join(parts)

func snapshot() -> Dictionary:
	return {
		"columns": _clone(columns),
		"berths": _clone(berths),
		"hold": hold,
		"hold2": hold2,
		"moves_done": moves_done,
	}

func restore(snap: Dictionary) -> void:
	_restore_snap(snap)
	history.clear()

func pretty(color: String) -> String:
	if color == "":
		return "Empty"
	return color.substr(0, 1).to_upper() + color.substr(1)

func _blocked_reason(token: String) -> String:
	if token == "":
		return "Nothing on that column to move."
	if token == "key":
		return "Tap the key to collect it."
	if is_locked(token) and deck_has_key():
		return "That container is locked. Collect the key first."
	return ""


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
	hold2 = str(snap.get("hold2", ""))
	moves_done = int(snap["moves_done"])
	last_shipped = ""

func _clone(src: Array) -> Array:
	var out: Array = []
	for item in src:
		out.append((item as Array).duplicate())
	return out
