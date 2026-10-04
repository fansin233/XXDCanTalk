extends RefCounted

const DESIGN_SIZE := Vector2(720.0, 1280.0)


static func get_safe_rect(root: CanvasItem, design_height: float) -> Rect2:
	var bounds := Rect2(Vector2.ZERO, Vector2(DESIGN_SIZE.x, design_height))
	if not OS.has_feature("mobile"):
		return bounds

	var screen_safe := DisplayServer.get_display_safe_area()
	if screen_safe.size.x <= 0 or screen_safe.size.y <= 0:
		return bounds
	var local_to_screen := root.get_screen_transform()
	if absf(local_to_screen.determinant()) < 0.00001:
		return bounds
	var inverse := local_to_screen.affine_inverse()
	var screen_origin := Vector2(screen_safe.position)
	var screen_size := Vector2(screen_safe.size)
	var screen_points: Array[Vector2] = [
		screen_origin,
		screen_origin + Vector2(screen_size.x, 0.0),
		screen_origin + screen_size,
		screen_origin + Vector2(0.0, screen_size.y),
	]
	var first: Vector2 = inverse * screen_points[0]
	var local_min: Vector2 = first
	var local_max: Vector2 = first
	for index in range(1, screen_points.size()):
		var local_point: Vector2 = inverse * screen_points[index]
		local_min = local_min.min(local_point)
		local_max = local_max.max(local_point)
	var converted := Rect2(local_min, local_max - local_min)
	var clipped := bounds.intersection(converted)
	if clipped.size.x < bounds.size.x * 0.55 or clipped.size.y < bounds.size.y * 0.55:
		return bounds
	return clipped
