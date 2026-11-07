extends Button

const Kit := preload("res://scripts/harbour_kit.gd")

var fill := Color(0, 0, 0, 0)
var border := Color("1a120f")
var border_px := 6
var radius := 16
var glyph := ""
var mark_selected := false
var show_lock := false
var order_mark := ""

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true

func show_cargo(fill_c: Color, glyph_name: String, locked := false) -> void:
	fill = fill_c
	glyph = glyph_name
	show_lock = locked
	queue_redraw()

func set_order_mark(mark: String) -> void:
	order_mark = mark
	queue_redraw()

func clear_face(fill_c: Color) -> void:
	fill = fill_c
	glyph = ""
	show_lock = false
	order_mark = ""
	queue_redraw()

func set_selected(on: bool) -> void:
	mark_selected = on
	queue_redraw()

func _draw() -> void:
	var whole := Rect2(Vector2.ZERO, size)
	if glyph == "" and not show_lock:
		draw_rect(whole, fill)
		draw_rect(whole.grow(-6), Color(fill.r, fill.g, fill.b, minf(fill.a, 0.35)))
		if mark_selected:
			draw_rect(whole, Color("fff8e8"), false, 8.0)
		return
	Kit.draw_extruded(self, whole, fill, Color("fff8e8") if mark_selected else border)
	var face := Kit.front_rect(whole)
	if glyph != "":
		paint_glyph(self, face, glyph, Color("1a120f"))
	if show_lock:
		var ink := Color("1a120f")
		var body := minf(face.size.x, face.size.y)
		var cx := face.position.x + face.size.x * 0.5
		var cy := face.position.y + face.size.y * 0.48
		draw_arc(Vector2(cx, cy - body * 0.06), body * 0.16, PI, TAU, 16, ink, 7.0, true)
		draw_rect(Rect2(cx - body * 0.18, cy, body * 0.36, body * 0.28), ink)
		draw_circle(Vector2(cx, cy + body * 0.12), body * 0.045, fill)
	if order_mark != "":
		var font := ThemeDB.fallback_font
		var mark_size := int(maxf(16.0, minf(face.size.x, face.size.y) * 0.22))
		draw_string(font, Vector2(face.position.x, face.end.y - 6.0), order_mark, HORIZONTAL_ALIGNMENT_CENTER, face.size.x, mark_size, Color("1a120f"))

static func paint_glyph(control: Control, rect: Rect2, glyph_name: String, ink: Color) -> void:
	if glyph_name == "":
		return
	var center := rect.position + rect.size * 0.5
	var r := minf(rect.size.x, rect.size.y) * 0.22
	if glyph_name == "circle":
		control.draw_circle(center, r, ink)
	elif glyph_name == "square":
		var h := r * 0.92
		control.draw_rect(Rect2(center - Vector2(h, h), Vector2(h, h) * 2.0), ink)
	elif glyph_name == "triangle":
		control.draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -r * 1.15),
			center + Vector2(r * 1.2, r * 0.9),
			center + Vector2(-r * 1.2, r * 0.9),
		]), ink)
	elif glyph_name == "diamond":
		control.draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -r * 1.25),
			center + Vector2(r, 0),
			center + Vector2(0, r * 1.25),
			center + Vector2(-r, 0),
		]), ink)
	elif glyph_name == "key":
		control.draw_circle(center + Vector2(0, -r * 0.35), r * 0.55, ink)
		control.draw_rect(Rect2(center + Vector2(-r * 0.16, r * 0.1), Vector2(r * 0.32, r)), ink)
