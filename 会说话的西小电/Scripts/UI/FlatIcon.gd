extends Control

var icon_name: StringName = &"store"
var icon_color := Color("#5f55a8")
var soft_color := Color("#e8e3f6")


func setup(name: StringName, color: Color, soft: Color = Color("#e8e3f6")) -> void:
	icon_name = name
	icon_color = color
	soft_color = soft
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var unit := minf(size.x, size.y)
	if unit <= 1.0:
		return
	var scale_factor := unit / 48.0
	var offset := (size - Vector2.ONE * unit) * 0.5
	match icon_name:
		&"store":
			_line([Vector2(8, 21), Vector2(13, 10), Vector2(35, 10), Vector2(40, 21)], scale_factor, offset)
			_line([Vector2(7, 21), Vector2(41, 21), Vector2(39, 26), Vector2(9, 26), Vector2(7, 21)], scale_factor, offset)
			_rect(Rect2(11, 26, 26, 17), scale_factor, offset)
			_line([Vector2(20, 43), Vector2(20, 32), Vector2(28, 32), Vector2(28, 43)], scale_factor, offset)
			_line([Vector2(11, 32), Vector2(37, 32)], scale_factor, offset, 1.5)
		&"backpack":
			_rect(Rect2(11, 15, 26, 28), scale_factor, offset)
			_line([Vector2(16, 16), Vector2(18, 9), Vector2(30, 9), Vector2(32, 16)], scale_factor, offset)
			_rect(Rect2(15, 26, 18, 12), scale_factor, offset)
			_line([Vector2(24, 26), Vector2(24, 30)], scale_factor, offset, 1.4)
		&"compass":
			_circle(Vector2(24, 24), 17, scale_factor, offset)
			_polygon([Vector2(29, 14), Vector2(25, 26), Vector2(17, 33)], scale_factor, offset, soft_color)
			_line([Vector2(29, 14), Vector2(25, 26), Vector2(17, 33), Vector2(23, 21), Vector2(29, 14)], scale_factor, offset)
			_circle(Vector2(24, 24), 2.2, scale_factor, offset, icon_color, true)
		&"run":
			_circle(Vector2(31, 9), 4.0, scale_factor, offset, soft_color, true)
			_line([Vector2(28, 16), Vector2(22, 25), Vector2(29, 30), Vector2(26, 40)], scale_factor, offset, 2.5)
			_line([Vector2(22, 25), Vector2(14, 22), Vector2(9, 28)], scale_factor, offset, 2.5)
			_line([Vector2(29, 30), Vector2(37, 26), Vector2(41, 30)], scale_factor, offset, 2.5)
			_line([Vector2(26, 40), Vector2(19, 44)], scale_factor, offset, 2.5)
			_line([Vector2(26, 40), Vector2(34, 43)], scale_factor, offset, 2.5)
		&"mail":
			_line([Vector2(8, 13), Vector2(40, 13), Vector2(40, 37), Vector2(8, 37), Vector2(8, 13)], scale_factor, offset)
			_line([Vector2(9, 15), Vector2(24, 28), Vector2(39, 15)], scale_factor, offset)
			_line([Vector2(9, 36), Vector2(20, 25)], scale_factor, offset, 1.6)
			_line([Vector2(39, 36), Vector2(28, 25)], scale_factor, offset, 1.6)
		&"album":
			_line([Vector2(12, 9), Vector2(36, 9), Vector2(36, 39), Vector2(12, 39), Vector2(12, 9)], scale_factor, offset)
			_line([Vector2(17, 9), Vector2(17, 39)], scale_factor, offset, 1.5)
			_circle(Vector2(28, 20), 5.5, scale_factor, offset, soft_color, true)
			_line([Vector2(21, 32), Vector2(24, 28), Vector2(27, 31), Vector2(30, 27), Vector2(34, 32)], scale_factor, offset, 1.6)
		&"star":
			_polygon([Vector2(24, 6), Vector2(29, 18), Vector2(42, 19), Vector2(32, 27), Vector2(35, 41), Vector2(24, 34), Vector2(13, 41), Vector2(16, 27), Vector2(6, 19), Vector2(19, 18)], scale_factor, offset, soft_color)
			_line([Vector2(24, 6), Vector2(29, 18), Vector2(42, 19), Vector2(32, 27), Vector2(35, 41), Vector2(24, 34), Vector2(13, 41), Vector2(16, 27), Vector2(6, 19), Vector2(19, 18), Vector2(24, 6)], scale_factor, offset)
		&"close":
			_line([Vector2(13, 13), Vector2(35, 35)], scale_factor, offset, 2.5)
			_line([Vector2(35, 13), Vector2(13, 35)], scale_factor, offset, 2.5)
		&"back":
			_line([Vector2(29, 10), Vector2(15, 24), Vector2(29, 38)], scale_factor, offset, 2.5)
			_line([Vector2(16, 24), Vector2(38, 24)], scale_factor, offset, 2.5)
		&"plus":
			_line([Vector2(24, 11), Vector2(24, 37)], scale_factor, offset, 2.5)
			_line([Vector2(11, 24), Vector2(37, 24)], scale_factor, offset, 2.5)
		&"minus":
			_line([Vector2(11, 24), Vector2(37, 24)], scale_factor, offset, 2.5)
		&"check":
			_line([Vector2(9, 25), Vector2(20, 36), Vector2(39, 12)], scale_factor, offset, 2.8)
		&"food_rice":
			_polygon([Vector2(10, 26), Vector2(15, 14), Vector2(33, 14), Vector2(38, 26), Vector2(34, 38), Vector2(14, 38)], scale_factor, offset, soft_color)
			_line([Vector2(10, 26), Vector2(15, 14), Vector2(33, 14), Vector2(38, 26), Vector2(34, 38), Vector2(14, 38), Vector2(10, 26)], scale_factor, offset)
			_line([Vector2(14, 29), Vector2(34, 29)], scale_factor, offset, 1.8)
		&"food_milk":
			_polygon([Vector2(15, 10), Vector2(32, 10), Vector2(36, 16), Vector2(36, 40), Vector2(12, 40), Vector2(12, 16)], scale_factor, offset, soft_color)
			_line([Vector2(15, 10), Vector2(32, 10), Vector2(36, 16), Vector2(36, 40), Vector2(12, 40), Vector2(12, 16), Vector2(15, 10)], scale_factor, offset)
			_line([Vector2(12, 21), Vector2(36, 21)], scale_factor, offset, 1.8)
			_circle(Vector2(24, 30), 4, scale_factor, offset, icon_color, true)
		&"food_cookie":
			_circle(Vector2(24, 24), 16, scale_factor, offset, soft_color, true)
			_circle(Vector2(24, 24), 16, scale_factor, offset)
			_circle(Vector2(18, 18), 2.0, scale_factor, offset, icon_color, true)
			_circle(Vector2(29, 17), 2.0, scale_factor, offset, icon_color, true)
			_circle(Vector2(29, 29), 2.0, scale_factor, offset, icon_color, true)
			_circle(Vector2(18, 30), 2.0, scale_factor, offset, icon_color, true)
		&"food_bento":
			_rect(Rect2(9, 15, 30, 26), scale_factor, offset, soft_color)
			_line([Vector2(9, 23), Vector2(39, 23)], scale_factor, offset)
			_line([Vector2(9, 36), Vector2(39, 36)], scale_factor, offset, 1.6)
			_circle(Vector2(18, 30), 3.5, scale_factor, offset, icon_color, true)
			_circle(Vector2(30, 30), 3.5, scale_factor, offset, icon_color, true)
		&"food_drink":
			_rect(Rect2(14, 13, 20, 30), scale_factor, offset, soft_color)
			_line([Vector2(19, 8), Vector2(29, 8), Vector2(29, 13)], scale_factor, offset)
			_line([Vector2(14, 23), Vector2(34, 23)], scale_factor, offset, 1.8)
			_line([Vector2(21, 29), Vector2(27, 29)], scale_factor, offset, 1.8)
		&"food_book":
			_line([Vector2(10, 11), Vector2(22, 13), Vector2(24, 17), Vector2(26, 13), Vector2(38, 11), Vector2(38, 37), Vector2(26, 39), Vector2(24, 42), Vector2(22, 39), Vector2(10, 37), Vector2(10, 11)], scale_factor, offset)
			_line([Vector2(24, 17), Vector2(24, 42)], scale_factor, offset, 1.6)
			_line([Vector2(14, 19), Vector2(20, 20)], scale_factor, offset, 1.6)
			_line([Vector2(28, 20), Vector2(34, 19)], scale_factor, offset, 1.6)
		&"food_growth":
			_rect(Rect2(12, 9, 24, 31), scale_factor, offset, soft_color)
			_line([Vector2(17, 18), Vector2(31, 18)], scale_factor, offset, 1.6)
			_line([Vector2(17, 25), Vector2(31, 25)], scale_factor, offset, 1.6)
			_line([Vector2(17, 32), Vector2(27, 32)], scale_factor, offset, 1.6)
		&"souvenir":
			_circle(Vector2(24, 24), 14, scale_factor, offset, soft_color, true)
			_circle(Vector2(24, 24), 14, scale_factor, offset)
			_circle(Vector2(24, 24), 8, scale_factor, offset)
		&"route_nearby":
			_line([Vector2(7, 38), Vector2(18, 27), Vector2(24, 33), Vector2(35, 18), Vector2(42, 25)], scale_factor, offset)
			_circle(Vector2(35, 13), 3.0, scale_factor, offset, soft_color, true)
		&"route_city":
			_rect(Rect2(9, 18, 11, 22), scale_factor, offset)
			_rect(Rect2(22, 8, 15, 32), scale_factor, offset)
			for row in range(3):
				_line([Vector2(12, 23 + row * 6), Vector2(17, 23 + row * 6)], scale_factor, offset, 1.1)
				_line([Vector2(26, 15 + row * 7), Vector2(32, 15 + row * 7)], scale_factor, offset, 1.1)
		&"route_far":
			_line([Vector2(5, 38), Vector2(18, 20), Vector2(24, 28), Vector2(34, 10), Vector2(44, 38), Vector2(5, 38)], scale_factor, offset)
			_line([Vector2(27, 22), Vector2(34, 14), Vector2(39, 28)], scale_factor, offset, 1.6)
		&"settings":
			_circle(Vector2(24, 24), 15, scale_factor, offset)
			_circle(Vector2(24, 24), 5, scale_factor, offset)
			for angle in range(8):
				var rad := float(angle) * TAU / 8.0
				var start := Vector2(24, 24) + Vector2(cos(rad), sin(rad)) * 17.0
				var finish := Vector2(24, 24) + Vector2(cos(rad), sin(rad)) * 21.0
				_line([start, finish], scale_factor, offset, 2.0)
		_:
			_circle(Vector2(24, 24), 15, scale_factor, offset, soft_color, true)
			_circle(Vector2(24, 24), 15, scale_factor, offset)


func _line(points: Array, factor: float, origin: Vector2, width: float = 2.2) -> void:
	var converted := PackedVector2Array()
	for point in points:
		converted.append(origin + Vector2(point) * factor)
	draw_polyline(converted, icon_color, width * factor, true)


func _rect(rect: Rect2, factor: float, origin: Vector2, fill: Color = Color(0, 0, 0, 0)) -> void:
	var converted := Rect2(origin + rect.position * factor, rect.size * factor)
	if fill.a > 0.0:
		draw_rect(converted, fill, true)
	draw_rect(converted, icon_color, false, 2.2 * factor, true)


func _circle(center: Vector2, radius: float, factor: float, origin: Vector2, color: Color = Color(0, 0, 0, 0), filled: bool = false) -> void:
	var converted_center := origin + center * factor
	if filled and color.a > 0.0:
		draw_circle(converted_center, radius * factor, color)
	if not filled:
		draw_arc(converted_center, radius * factor, 0.0, TAU, 32, icon_color, 2.2 * factor, true)


func _polygon(points: Array, factor: float, origin: Vector2, fill: Color) -> void:
	var converted := PackedVector2Array()
	for point in points:
		converted.append(origin + Vector2(point) * factor)
	draw_colored_polygon(converted, fill)
