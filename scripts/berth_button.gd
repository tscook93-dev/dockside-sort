extends Button

const Glyph := preload("res://scripts/glyph_button.gd")
const Kit := preload("res://scripts/harbour_kit.gd")

var capacity := 3
var lock_color := ""
var stack: Array = []
var palette: Dictionary = {}
var glyphs: Dictionary = {}
var mark_selected := false

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true

func set_state(lock: String, contents: Array, cap: int, colors: Dictionary, glyph_map: Dictionary) -> void:
	lock_color = lock
	stack = contents.duplicate()
	capacity = cap
	palette = colors
	glyphs = glyph_map
	queue_redraw()

func set_selected(on: bool) -> void:
	mark_selected = on
	queue_redraw()

func _draw() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("24383f")
	frame.border_color = Color("fff8e8") if mark_selected else Color("10181c")
	frame.set_border_width_all(8 if mark_selected else 6)
	frame.set_corner_radius_all(22)
	frame.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	if capacity <= 0:
		return
	var gap := 8.0
	var pad := 12.0
	var slot_h := (size.y - pad * 2.0 - gap * float(capacity - 1)) / float(capacity)
	var slot_w := size.x - pad * 2.0
	var empties := capacity - stack.size()
	for i in capacity:
		var rect := Rect2(Vector2(pad, pad + i * (slot_h + gap)), Vector2(slot_w, slot_h))
		var slot := StyleBoxFlat.new()
		slot.set_corner_radius_all(14)
		slot.set_border_width_all(4)
		if i < empties:
			var wash := Color("1b282d")
			if lock_color != "" and palette.has(lock_color):
				wash = palette[lock_color]
				wash.a = 0.33
			slot.bg_color = wash
			slot.border_color = Color("10181c")
			slot.draw(get_canvas_item(), rect)
			if stack.is_empty() and lock_color != "" and i == capacity - 1:
				var ghost: Color = Color("1a120f")
				ghost.a = 0.45
				Glyph.paint_glyph(self, rect, str(glyphs.get(lock_color, "")), ghost)
		else:
			var idx := stack.size() - 1 - (i - empties)
			var color_name := str(stack[idx])
			Kit.draw_extruded(self, rect, palette[color_name])
			Glyph.paint_glyph(self, Kit.front_rect(rect), str(glyphs.get(color_name, "")), Color("1a120f"))
