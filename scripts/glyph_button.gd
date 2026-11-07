extends Button

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
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = Color("fff8e8") if mark_selected else border
	sb.set_border_width_all(10 if mark_selected else border_px)
	sb.set_corner_radius_all(radius)
	sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	if glyph != "":
		paint_glyph(self, Rect2(Vector2.ZERO, size), glyph, Color("1a120f"))
	if show_lock:
		var ink := Color("1a120f")
		var body := minf(size.x, size.y)
		var cx := size.x * 0.5
		var cy := size.y * 0.52
		draw_arc(Vector2(cx, cy - body * 0.06), body * 0.16, PI, TAU, 16, ink, 7.0, true)
		draw_rect(Rect2(cx - body * 0.18, cy, body * 0.36, body * 0.28), ink)
		draw_circle(Vector2(cx, cy + body * 0.12), body * 0.045, fill)
	if order_mark != "":
		var font := ThemeDB.fallback_font
		var mark_size := int(maxf(18.0, minf(size.x, size.y) * 0.2))
		draw_string(font, Vector2(0, size.y - 8), order_mark, HORIZONTAL_ALIGNMENT_CENTER, size.x, mark_size, Color("1a120f"))

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
