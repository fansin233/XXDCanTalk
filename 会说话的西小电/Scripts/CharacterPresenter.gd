extends Node3D

const MODEL_SCENE: PackedScene = preload("res://Assests/Model/xxd2.gltf")

var _skeleton: Skeleton3D
var _bone_indices: Dictionary = {}
var _base_rotations: Dictionary = {}
var _base_global_bases: Dictionary = {}
var _rest_height := 0.0
var _state := "idle"
var _state_time := 0.0
var _clock := 0.0
var _right_shoulder_pose := deg_to_rad(58.0)
var _left_shoulder_pose := deg_to_rad(-58.0)
var _right_elbow_pose := 0.0
var _left_elbow_pose := 0.0


func _ready() -> void:
	_rest_height = position.y
	var model := MODEL_SCENE.instantiate()
	model.scale = Vector3.ONE * 0.62
	add_child(model)
	_skeleton = _find_skeleton(model)
	if _skeleton == null:
		return

	var bone_map := {
		"hips": "腰",
		"torso": "上半身",
		"neck": "首",
		"head": "頭",
		"shoulder_right": "肩.R",
		"shoulder_left": "肩.L",
		"right_elbow": "ひじ.R",
		"left_elbow": "ひじ.L",
	}
	for key in bone_map:
		var index := _skeleton.find_bone(bone_map[key])
		_bone_indices[key] = index
		if index >= 0:
			_base_rotations[index] = _skeleton.get_bone_pose_rotation(index)
			_base_global_bases[index] = _skeleton.get_bone_global_pose(index).basis


func _process(delta: float) -> void:
	_clock += delta
	_state_time += delta
	if _state == "petted" and _state_time > 1.65:
		set_state("idle")
	elif _state == "happy" and _state_time > 1.2:
		set_state("idle")

	var breathing := sin(_clock * 2.1) * 0.004
	var bob := 0.0
	var head_tilt := sin(_clock * 0.75) * 0.025
	var head_nod := sin(_clock * 1.4) * 0.018
	var torso_sway := sin(_clock * 0.65) * 0.018
	var right_shoulder_target := deg_to_rad(58.0) + sin(_clock * 1.45) * deg_to_rad(2.0)
	var left_shoulder_target := deg_to_rad(-58.0) - sin(_clock * 1.45) * deg_to_rad(2.0)
	var right_elbow_target := 0.0
	var left_elbow_target := 0.0
	var body_lean := sin(_clock * 0.65) * 0.012
	var body_turn := sin(_clock * 0.35) * 0.025
	var body_pitch := sin(_clock * 0.9) * 0.008

	match _state:
		"listening":
			head_tilt += deg_to_rad(-10.0)
			head_nod += sin(_state_time * 3.2) * 0.035
			torso_sway = sin(_state_time * 1.5) * 0.006
			body_lean -= deg_to_rad(1.8) + sin(_state_time * 2.0) * 0.008
			body_pitch = deg_to_rad(1.5) + sin(_state_time * 2.4) * 0.006
			body_turn = -0.035
			# Keep the everyday arm line down; the listening motion brings the
			# right hand up toward the ear with a broad, visible shoulder swing.
			right_shoulder_target = deg_to_rad(-58.0)
			right_elbow_target = deg_to_rad(-58.0)
		"repeating":
			head_nod += sin(_state_time * 16.0) * 0.075
			head_tilt += sin(_state_time * 9.0) * 0.035
			body_lean += sin(_state_time * 10.0) * 0.025
			bob = absf(sin(_state_time * 16.0)) * 0.018
			right_shoulder_target -= 0.06
			left_shoulder_target += 0.06
		"petted":
			var pet_motion := sin(_state_time * TAU * 1.35)
			var pet_envelope := _smoothstep(0.0, 0.16, _state_time)
			pet_envelope *= 1.0 - _smoothstep(1.28, 1.65, _state_time)
			head_nod += pet_motion * 0.10 * pet_envelope
			head_tilt += sin(_state_time * TAU * 0.9) * 0.06 * pet_envelope
			# Two light, upward bounces and a side-to-side head sway make a pat
			# feel lively while the envelope eases the pose in and out.
			bob = absf(pet_motion) * 0.018 * pet_envelope
			body_lean = sin(_state_time * TAU * 0.9) * 0.018 * pet_envelope
		"happy":
			bob = absf(sin(_state_time * 8.0)) * 0.07
			head_nod += sin(_state_time * 8.0) * 0.11
			body_lean = sin(_state_time * 8.0) * 0.035
			body_turn = sin(_state_time * 4.0) * 0.06
		"laughing":
			head_nod += sin(_state_time * 11.0) * 0.16
			head_tilt += sin(_state_time * 6.0) * 0.04
			body_pitch = deg_to_rad(4.0) + sin(_state_time * 10.0) * 0.025
			body_lean = sin(_state_time * 11.0) * 0.028
			body_turn = sin(_state_time * 5.0) * 0.045
			torso_sway = sin(_state_time * 11.0) * 0.02
			bob = absf(sin(_state_time * 12.0)) * 0.045
			right_shoulder_target = deg_to_rad(50.0)
			left_shoulder_target = deg_to_rad(-50.0)
			right_elbow_target = deg_to_rad(100.0)
			left_elbow_target = deg_to_rad(-100.0)
		"tickled":
			head_tilt += sin(_state_time * 12.0) * 0.15
			head_nod += sin(_state_time * 10.0) * 0.08
			body_pitch = deg_to_rad(3.0) + sin(_state_time * 12.0) * 0.035
			body_lean = sin(_state_time * 13.0) * 0.032
			bob = absf(sin(_state_time * 13.0)) * 0.035
			right_shoulder_target -= 0.18
			left_shoulder_target += 0.18
			right_elbow_target = deg_to_rad(35.0)
			left_elbow_target = deg_to_rad(-35.0)
		"resting":
			head_nod += 0.08
			torso_sway = sin(_clock * 0.8) * 0.008
			body_lean = deg_to_rad(3.0) + sin(_clock * 0.8) * 0.012
			body_pitch = deg_to_rad(2.0)
			breathing *= 0.65

	position.y = _rest_height + bob + breathing
	scale = Vector3.ONE
	rotation.x = body_pitch
	rotation.y = body_turn
	rotation.z = body_lean
	var pose_blend := 1.0 - exp(-delta * 9.0)
	_right_shoulder_pose = lerp_angle(_right_shoulder_pose, right_shoulder_target, pose_blend)
	_left_shoulder_pose = lerp_angle(_left_shoulder_pose, left_shoulder_target, pose_blend)
	_right_elbow_pose = lerpf(_right_elbow_pose, right_elbow_target, pose_blend)
	_left_elbow_pose = lerpf(_left_elbow_pose, left_elbow_target, pose_blend)
	_apply_bone_rotation("shoulder_right", Vector3.BACK, _right_shoulder_pose)
	_apply_bone_rotation("shoulder_left", Vector3.BACK, _left_shoulder_pose)
	_apply_bone_rotation("right_elbow", Vector3.FORWARD, _right_elbow_pose)
	_apply_bone_rotation("left_elbow", Vector3.FORWARD, _left_elbow_pose)
	_apply_bone_rotation_pair("head", Vector3.BACK, head_tilt, Vector3.RIGHT, head_nod)
	_apply_bone_rotation("neck", Vector3.BACK, head_tilt * -0.28)
	_apply_bone_rotation("torso", Vector3.BACK, torso_sway)


func set_state(next_state: String) -> void:
	if _state == next_state:
		return
	_state = next_state
	_state_time = 0.0


func tap() -> void:
	if _state != "listening" and _state != "repeating" and _state != "resting":
		if _state == "petted":
			_state_time = 0.0
		else:
			set_state("petted")


func play_laugh() -> void:
	set_state("laughing")


func play_tickled() -> void:
	set_state("tickled")


func finish_feedback_animation() -> void:
	if _state == "laughing" or _state == "tickled":
		set_state("idle")


func celebrate() -> void:
	set_state("happy")


func set_resting(resting: bool) -> void:
	set_state("resting" if resting else "idle")


func get_state() -> String:
	return _state


func _smoothstep(edge_0: float, edge_1: float, value: float) -> float:
	var t := clampf((value - edge_0) / maxf(edge_1 - edge_0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _apply_bone_rotation(channel: String, axis: Vector3, angle: float) -> void:
	_apply_bone_rotation_pair(channel, axis, angle, Vector3.ZERO, 0.0)


func _apply_bone_rotation_pair(
	channel: String,
	first_axis: Vector3,
	first_angle: float,
	second_axis: Vector3,
	second_angle: float
) -> void:
	if _skeleton == null:
		return
	var index := int(_bone_indices.get(channel, -1))
	if index < 0:
		return
	var base_rotation: Quaternion = _base_rotations.get(index, Quaternion.IDENTITY)
	var base_global_basis: Basis = _base_global_bases.get(index, Basis.IDENTITY)
	var first_axis_in_skeleton := _skeleton.global_transform.basis.inverse() * (global_transform.basis * first_axis)
	var first_axis_in_bone := base_global_basis.inverse() * first_axis_in_skeleton
	var target_rotation := base_rotation
	if first_axis_in_bone.length_squared() >= 0.0001 and absf(first_angle) > 0.0001:
		target_rotation = target_rotation * Quaternion(first_axis_in_bone.normalized(), first_angle)
	if second_axis.length_squared() >= 0.0001 and absf(second_angle) > 0.0001:
		var second_axis_in_skeleton := _skeleton.global_transform.basis.inverse() * (global_transform.basis * second_axis)
		var second_axis_in_bone := base_global_basis.inverse() * second_axis_in_skeleton
		if second_axis_in_bone.length_squared() >= 0.0001:
			target_rotation = target_rotation * Quaternion(second_axis_in_bone.normalized(), second_angle)
	_skeleton.set_bone_pose_rotation(index, target_rotation)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
