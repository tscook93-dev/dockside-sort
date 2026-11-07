extends RefCounted

## Shared toy-harbour drawing. One kit for the Sydney yard and the cargo blocks.
## Faces are lighter and darker versions of the same fill, so a colour stays itself.

const INK := Color("1a120f")
const CREAM := Color("f6efe2")
const GOLD := Color("f0b429")
const WATER := Color("1f6f86")
const WATER_DEEP := Color("164e63")
const SKY := Color("8ec4d4")
const QUAY := Color("c4a574")
const SHED := Color("f3e6cf")
const SHED_ROOF := Color("e25d45")


static func draw_extruded(item: CanvasItem, rect: Rect2, fill: Color, ink: Color = INK) -> void:
	var depth := minf(18.0, minf(rect.size.x, rect.size.y) * 0.22)
	if depth < 3.0:
		item.draw_rect(rect, fill)
		return
	var front := Rect2(rect.position.x, rect.position.y + depth, rect.size.x - depth, rect.size.y - depth)
	var shift := Vector2(depth * 0.9, -depth)
	var top := PackedVector2Array([
		front.position,
		Vector2(front.end.x, front.position.y),
		Vector2(front.end.x, front.position.y) + shift,
		front.position + shift,
	])
	var side := PackedVector2Array([
		Vector2(front.end.x, front.position.y),
		Vector2(front.end.x, front.position.y) + shift,
		Vector2(front.end.x, front.end.y) + shift,
		Vector2(front.end.x, front.end.y),
	])
	item.draw_colored_polygon(top, fill.lightened(0.28))
	item.draw_colored_polygon(side, fill.darkened(0.32))
	item.draw_rect(front, fill)
	var outline := PackedVector2Array([
		front.position,
		Vector2(front.end.x, front.position.y),
		Vector2(front.end.x, front.end.y),
		Vector2(front.position.x, front.end.y),
		front.position,
		front.position + shift,
		Vector2(front.end.x, front.position.y) + shift,
		Vector2(front.end.x, front.end.y) + shift,
		Vector2(front.end.x, front.end.y),
	])
	item.draw_polyline(outline, ink, 4.0, true)
	item.draw_line(Vector2(front.end.x, front.position.y), Vector2(front.end.x, front.position.y) + shift, ink, 4.0)


static func front_rect(rect: Rect2) -> Rect2:
	var depth := minf(18.0, minf(rect.size.x, rect.size.y) * 0.22)
	if depth < 3.0:
		return rect
	return Rect2(rect.position.x, rect.position.y + depth, rect.size.x - depth, rect.size.y - depth)


static func draw_sydney(item: CanvasItem, area: Rect2) -> void:
	item.draw_rect(area, SKY)
	var water := Rect2(area.position.x, area.position.y + area.size.y * 0.56, area.size.x, area.size.y * 0.44)
	item.draw_rect(water, WATER)
	for i in 4:
		var y := water.position.y + 18.0 + float(i) * (water.size.y - 28.0) / 4.0
		item.draw_line(Vector2(water.position.x + 12.0, y), Vector2(water.end.x - 12.0, y), WATER_DEEP, 6.0)
	var quay := Rect2(area.position.x + area.size.x * 0.05, area.position.y + area.size.y * 0.40, area.size.x * 0.90, area.size.y * 0.24)
	draw_extruded(item, quay, QUAY)
	var shed := Rect2(quay.position.x + 18.0, quay.position.y - quay.size.y * 0.95, quay.size.x * 0.28, quay.size.y * 0.95)
	draw_extruded(item, shed, SHED)
	var roof := Rect2(shed.position.x - 8.0, shed.position.y - shed.size.y * 0.28, shed.size.x + 22.0, shed.size.y * 0.34)
	draw_extruded(item, roof, SHED_ROOF)
	_draw_crane(item, Rect2(quay.end.x - quay.size.x * 0.42, area.position.y + 8.0, quay.size.x * 0.38, quay.position.y - area.position.y))
	var bollard_y := quay.end.y - 8.0
	for i in 3:
		var x := quay.position.x + 36.0 + float(i) * (quay.size.x * 0.22)
		draw_extruded(item, Rect2(x, bollard_y - 28.0, 22.0, 36.0), CREAM)
	var cargo_y := quay.position.y + 16.0
	var cargo_h := maxf(36.0, quay.size.y * 0.55)
	draw_extruded(item, Rect2(quay.position.x + quay.size.x * 0.36, cargo_y, cargo_h, cargo_h), Color("e25d45"))
	draw_extruded(item, Rect2(quay.position.x + quay.size.x * 0.36 + cargo_h + 10.0, cargo_y, cargo_h, cargo_h), Color("1f8a80"))
	draw_extruded(item, Rect2(quay.position.x + quay.size.x * 0.36 + (cargo_h + 10.0) * 2.0, cargo_y, cargo_h, cargo_h), GOLD)


static func _draw_crane(item: CanvasItem, rect: Rect2) -> void:
	var mast := Rect2(rect.position.x + rect.size.x * 0.55, rect.position.y + rect.size.y * 0.18, rect.size.x * 0.16, rect.size.y * 0.82)
	draw_extruded(item, mast, GOLD)
	var jib := Rect2(rect.position.x, mast.position.y, rect.size.x * 0.92, rect.size.y * 0.12)
	draw_extruded(item, jib, GOLD)
	var hook_x := jib.position.x + 18.0
	item.draw_line(Vector2(hook_x, jib.end.y), Vector2(hook_x, jib.end.y + rect.size.y * 0.28), INK, 5.0)
	item.draw_arc(Vector2(hook_x, jib.end.y + rect.size.y * 0.34), 10.0, 0.2, PI - 0.2, 12, INK, 4.0, true)
