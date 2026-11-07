extends Control

const PuzzleScript := preload("res://scripts/puzzle.gd")
const Glyph := preload("res://scripts/glyph_button.gd")
const Berth := preload("res://scripts/berth_button.gd")

const HARBOUR := Color("1b3a4b")
const CREAM := Color("f6efe2")
const INK := Color("1a120f")
const GOLD := Color("f0b429")
const DECK := Color("c4a574")
const DOCK := Color("31464c")
const PALETTE := {
	"coral": Color("e25d45"),
	"teal": Color("1f8a80"),
	"gold": Color("f0b429"),
}
const GLYPHS := {
	"coral": "circle",
	"teal": "square",
	"gold": "triangle",
}

var levels: Array = []
var level_index := 0
var puzzle
var deck_height := 0
var sel_kind := ""
var sel_index := -1
var modal_mode := ""

var margin: MarginContainer
var level_label: Label
var title_label: Label
var blurb_label: Label
var status_label: Label
var moves_label: Label
var deck_row: HBoxContainer
var stack_row: HBoxContainer
var hold_button
var column_cells: Array = []
var berth_buttons: Array = []

var modal: Control
var modal_title: Label
var modal_body: Label
var primary_button: Button
var secondary_button: Button


func _ready() -> void:
	DisplayServer.window_set_title("Dockside Sort: Cargo Puzzle")
	_build_chrome()
	for path in PuzzleScript.list_level_paths():
		var data: Dictionary = PuzzleScript.load_level(path)
		if not data.is_empty():
			levels.append(data)
	if levels.is_empty():
		_set_status("No levels in res://levels.")
		return
	_load_current()
	resized.connect(_apply_safe_margins)
	_apply_safe_margins()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and margin != null:
		_apply_safe_margins()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).keycode
	if modal != null and modal.visible:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			_on_primary()
		elif key == KEY_ESCAPE and modal_mode == "fail":
			_undo()
		return
	if key >= KEY_1 and key <= KEY_9:
		_select_column(key - KEY_1)
	elif key == KEY_H:
		_on_hold()
	elif key == KEY_Q:
		_on_berth(0)
	elif key == KEY_W:
		_on_berth(1)
	elif key == KEY_E:
		_on_berth(2)
	elif key == KEY_U or key == KEY_Z:
		_undo()
	elif key == KEY_R or key == KEY_BACKSPACE:
		_restart()


func _load_current(announce := "") -> void:
	if modal != null:
		modal.visible = false
	sel_kind = ""
	sel_index = -1
	puzzle = PuzzleScript.new()
	puzzle.setup(levels[level_index])
	level_label.text = "Level %d of %d" % [level_index + 1, levels.size()]
	title_label.text = puzzle.title
	blurb_label.text = puzzle.blurb
	_rebuild_board()
	if announce == "":
		_set_status("Tap the top container, then a stack or the hold.")
	else:
		_set_status(announce)


func _select_column(col: int) -> void:
	if puzzle == null or col < 0 or col >= puzzle.columns.size():
		return
	var stack: Array = puzzle.columns[col]
	if stack.is_empty():
		_set_status("That column is empty.")
		_refresh()
		return
	var empties := deck_height - stack.size()
	_on_cell(col, empties)


func _on_cell(col: int, row: int) -> void:
	if _modal_blocking():
		return
	var stack: Array = puzzle.columns[col]
	if stack.is_empty() or row < deck_height - stack.size():
		_set_status("Empty cell.")
		return
	if row != deck_height - stack.size():
		_set_status("Only the top container can move.")
		return
	if sel_kind == "column" and sel_index == col:
		sel_kind = ""
		sel_index = -1
		_set_status("Selection cleared.")
	else:
		sel_kind = "column"
		sel_index = col
		_set_status("%s selected. Tap a stack, or the hold." % puzzle.pretty(str(stack[0])))
	_refresh()


func _on_berth(berth: int) -> void:
	if _modal_blocking() or puzzle == null:
		return
	if berth < 0 or berth >= puzzle.berths.size():
		return
	if sel_kind == "":
		_set_status("Select a container first.")
		return
	var err := ""
	if sel_kind == "column":
		err = puzzle.move_column_to_berth(sel_index, berth)
	elif sel_kind == "hold":
		err = puzzle.move_hold_to_berth(berth)
	if err != "":
		_set_status(err)
		return
	sel_kind = ""
	sel_index = -1
	_after_successful_move()


func _on_hold() -> void:
	if _modal_blocking() or puzzle == null:
		return
	if sel_kind == "column":
		var err: String = puzzle.move_column_to_hold(sel_index)
		if err != "":
			_set_status(err)
			return
		sel_kind = ""
		sel_index = -1
		_after_successful_move("in the hold")
		return
	if puzzle.hold == "":
		_set_status("Select a container, then tap the hold.")
		return
	if sel_kind == "hold":
		sel_kind = ""
		sel_index = -1
		_set_status("Selection cleared.")
	else:
		sel_kind = "hold"
		sel_index = -1
		_set_status("%s in the hold. Tap a stack." % puzzle.pretty(puzzle.hold))
	_refresh()


func _after_successful_move(how := "stacked") -> void:
	if puzzle.last_shipped != "":
		_set_status("%s shipped." % puzzle.pretty(puzzle.last_shipped))
	elif how == "in the hold":
		_set_status("Parked in the hold.")
	else:
		_set_status("Stacked.")
	_refresh()
	if puzzle.is_win():
		_show_modal("win")
	elif puzzle.is_soft_fail():
		_show_modal("fail")


func _undo() -> void:
	if puzzle == null:
		return
	if modal != null and modal.visible and modal_mode == "win":
		return
	if not puzzle.undo():
		_set_status("Nothing to undo.")
		return
	sel_kind = ""
	sel_index = -1
	_set_status("Undid the last move.")
	_refresh()
	if modal != null and modal.visible and not puzzle.is_soft_fail():
		modal.visible = false


func _restart() -> void:
	_load_current("Restarted. Free retry.")


func _next_level() -> void:
	if levels.is_empty():
		return
	level_index = (level_index + 1) % levels.size()
	_load_current()


func _on_primary() -> void:
	if modal_mode == "win":
		_next_level()
	else:
		_undo()


func _on_secondary() -> void:
	_restart()


func _show_modal(mode: String) -> void:
	modal_mode = mode
	if mode == "win":
		modal_title.text = "Deck clear"
		modal_body.text = "Everything shipped."
		primary_button.text = "Back to level 1" if level_index == levels.size() - 1 else "Next level"
		secondary_button.text = "Replay"
	else:
		modal_title.text = "No moves left"
		var stuck := "The hold is full and nothing can stack."
		if puzzle.hold == "":
			stuck = "Nothing left can move."
		modal_body.text = "%s Undo, or restart for free." % stuck
		primary_button.text = "Undo"
		secondary_button.text = "Restart"
	secondary_button.visible = true
	modal.visible = true


func _modal_blocking() -> bool:
	return modal != null and modal.visible


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _refresh() -> void:
	if puzzle == null:
		return
	moves_label.text = "Moves %d" % puzzle.moves_done
	for c in puzzle.columns.size():
		var stack: Array = puzzle.columns[c]
		var empties := deck_height - stack.size()
		for r in deck_height:
			var cell = column_cells[c][r]
			if r < empties:
				cell.clear_face(Color(0.45, 0.32, 0.16, 0.28))
				cell.set_selected(false)
				cell.modulate = Color.WHITE
				cell.tooltip_text = "Empty cell"
			else:
				var color_name := str(stack[r - empties])
				cell.show_cargo(PALETTE[color_name], GLYPHS[color_name])
				var is_top := r == empties
				cell.modulate = Color.WHITE if is_top else Color(0.66, 0.66, 0.66)
				cell.set_selected(is_top and sel_kind == "column" and sel_index == c)
				cell.tooltip_text = puzzle.pretty(color_name)
	for b in puzzle.berths.size():
		var berth = berth_buttons[b]
		berth.set_state(str(puzzle.locks[b]), puzzle.berths[b], puzzle.capacity, PALETTE, GLYPHS)
		berth.set_selected(false)
	if puzzle.hold == "":
		hold_button.clear_face(Color("f7f1e4"))
		hold_button.tooltip_text = "Hold — empty"
	else:
		hold_button.show_cargo(PALETTE[puzzle.hold], GLYPHS[puzzle.hold])
		hold_button.tooltip_text = "Hold — %s" % puzzle.pretty(puzzle.hold)
	hold_button.set_selected(sel_kind == "hold")


func _rebuild_board() -> void:
	_free_children(deck_row)
	_free_children(stack_row)
	column_cells.clear()
	berth_buttons.clear()
	deck_height = 0
	for col in puzzle.columns:
		deck_height = max(deck_height, (col as Array).size())
	for c in puzzle.columns.size():
		var col_box := VBoxContainer.new()
		col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_box.add_theme_constant_override("separation", 8)
		var caption := _label("Col %d" % (c + 1), 22, CREAM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_box.add_child(caption)
		var cells: Array = []
		for r in deck_height:
			var cell: Button = Glyph.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cell.custom_minimum_size = Vector2(108, 108)
			cell.pressed.connect(_on_cell.bind(c, r))
			col_box.add_child(cell)
			cells.append(cell)
		deck_row.add_child(col_box)
		column_cells.append(cells)
	for b in puzzle.berths.size():
		var wrap := VBoxContainer.new()
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.add_theme_constant_override("separation", 6)
		var berth: Button = Berth.new()
		berth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		berth.custom_minimum_size = Vector2(120, 228)
		berth.pressed.connect(_on_berth.bind(b))
		var name := "Stack %d" % (b + 1)
		if str(puzzle.locks[b]) != "":
			name = puzzle.pretty(str(puzzle.locks[b]))
		var caption := _label(name, 22, CREAM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wrap.add_child(berth)
		wrap.add_child(caption)
		stack_row.add_child(wrap)
		berth_buttons.append(berth)
	_refresh()


func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.color = HARBOUR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation", 12)
	margin.add_child(root_box)

	var kicker := _label("DOCKSIDE SORT", 18, GOLD)
	root_box.add_child(kicker)

	var info := HBoxContainer.new()
	level_label = _label("Level", 26, CREAM)
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moves_label = _label("Moves 0", 26, GOLD)
	moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(level_label)
	info.add_child(moves_label)
	root_box.add_child(info)

	title_label = _label("Morning Shift", 40, CREAM)
	root_box.add_child(title_label)
	blurb_label = _label("", 22, Color("f6efe2cc"))
	blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(blurb_label)

	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _box(CREAM, INK, 0, 14, 12))
	status_label = _label("", 22, INK)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel.add_child(status_label)
	root_box.add_child(status_panel)

	var deck_panel := PanelContainer.new()
	deck_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_panel.add_theme_stylebox_override("panel", _box(DECK, Color("6e5230"), 4, 22, 14))
	deck_row = HBoxContainer.new()
	deck_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_row.add_theme_constant_override("separation", 14)
	deck_panel.add_child(deck_row)
	root_box.add_child(deck_panel)

	var stack_panel := PanelContainer.new()
	stack_panel.add_theme_stylebox_override("panel", _box(DOCK, Color("10181c"), 4, 22, 12))
	stack_row = HBoxContainer.new()
	stack_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_row.add_theme_constant_override("separation", 14)
	stack_panel.add_child(stack_row)
	root_box.add_child(stack_panel)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	root_box.add_child(bottom)

	var hold_wrap := VBoxContainer.new()
	hold_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold_wrap.add_theme_constant_override("separation", 4)
	var hold_caption := _label("HOLD", 20, GOLD)
	hold_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hold_button = Glyph.new()
	hold_button.custom_minimum_size = Vector2(132, 132)
	hold_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold_button.pressed.connect(_on_hold)
	hold_wrap.add_child(hold_caption)
	hold_wrap.add_child(hold_button)
	bottom.add_child(hold_wrap)

	bottom.add_child(_bottom_action("Undo", GOLD, INK, _undo))
	bottom.add_child(_bottom_action("Restart", Color("d7e4ea"), INK, _restart))

	_build_modal()


func _build_modal() -> void:
	modal = Control.new()
	modal.visible = false
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.09, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", _box(CREAM, INK, 6, 28, 28))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	modal_title = _label("", 40, INK)
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_body = _label("", 24, INK)
	modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_body.custom_minimum_size = Vector2(460, 0)
	box.add_child(modal_title)
	box.add_child(modal_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	primary_button = _action_button("Next level", GOLD, INK)
	primary_button.custom_minimum_size = Vector2(210, 96)
	primary_button.pressed.connect(_on_primary)
	secondary_button = _action_button("Restart", Color("d7e4ea"), INK)
	secondary_button.custom_minimum_size = Vector2(210, 96)
	secondary_button.pressed.connect(_on_secondary)
	row.add_child(primary_button)
	row.add_child(secondary_button)
	box.add_child(row)


func _bottom_action(text: String, fill: Color, ink: Color, handler: Callable) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 4)
	var spacer := _label(" ", 20, HARBOUR)
	spacer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var button := _action_button(text, fill, ink)
	button.pressed.connect(handler)
	wrap.add_child(spacer)
	wrap.add_child(button)
	return wrap


func _action_button(text: String, fill: Color, ink: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 132)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)
	var normal := _box(fill, INK, 6, 22, 8)
	var pressed := _box(fill.darkened(0.08), INK, 6, 22, 8)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_stylebox_override("disabled", normal)
	return button


func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label


func _box(fill: Color, border: Color, width: int, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


func _apply_safe_margins() -> void:
	if margin == null:
		return
	var inset := _safe_insets()
	margin.add_theme_constant_override("margin_left", int(maxf(inset.x, 20.0)))
	margin.add_theme_constant_override("margin_top", int(maxf(inset.y, 36.0)))
	margin.add_theme_constant_override("margin_right", int(maxf(inset.z, 20.0)))
	margin.add_theme_constant_override("margin_bottom", int(maxf(inset.w, 28.0)))


func _safe_insets() -> Vector4:
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0 or size.x <= 0.0 or size.y <= 0.0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var left := float(safe.position.x)
	var top := float(safe.position.y)
	var right := float(maxi(0, screen.x - safe.position.x - safe.size.x))
	var bottom := float(maxi(0, screen.y - safe.position.y - safe.size.y))
	return Vector4(left * size.x / float(screen.x), top * size.y / float(screen.y), right * size.x / float(screen.x), bottom * size.y / float(screen.y))


func _free_children(node: Node) -> void:
	while node.get_child_count() > 0:
		var child := node.get_child(0)
		node.remove_child(child)
		child.free()
