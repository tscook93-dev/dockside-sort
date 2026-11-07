extends Control

const Kit := preload("res://scripts/harbour_kit.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	Kit.draw_sydney(self, Rect2(Vector2.ZERO, size))
