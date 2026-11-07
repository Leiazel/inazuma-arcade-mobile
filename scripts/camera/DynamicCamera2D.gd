class_name DynamicCamera2D
extends Camera2D

## Frame-rate independent dynamic tracking camera for Inazuma Inspired Arcade Soccer.
## Centered smoothly between carrier and ball with dynamic zoom and procedural trauma shake.

@export_group("Tracking")
@export var follow_speed: float = 8.5
@export var field_half_width: float = 1800.0
@export var field_half_height: float = 1080.0

@export_group("Dynamic Zoom")
@export var zoom_close: float = 0.68
@export var zoom_wide: float = 0.46
@export var speed_threshold_min: float = 120.0
@export var speed_threshold_max: float = 1450.0
@export var zoom_out_rate: float = 4.8
@export var zoom_in_rate: float = 1.6

@export_group("Camera Shake")
@export var trauma_decay: float = 1.65
@export var max_offset: Vector2 = Vector2(28.0, 20.0)
@export var max_roll_deg: float = 2.2

@export_group("Target Nodes")
@export var target_ball: Node2D = null
@export var target_carrier: CharacterBody2D = null
@export var active_player: CharacterBody2D = null

var trauma: float = 0.0
var noise: FastNoiseLite = null
var noise_y: float = 0.0

func _init() -> void:
	zoom = Vector2(zoom_close, zoom_close)

func _ready() -> void:
	position_smoothing_enabled = false # Custom decoupled exponential decay lerp
	zoom = Vector2(zoom_close, zoom_close)
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.045
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

## Injects trauma for procedural shake (e.g. on super shot, collision, or tackle)
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	
	# Auto-locate targets if not explicitly bound
	var ball_node = target_ball
	if not is_instance_valid(ball_node):
		var balls = get_tree().get_nodes_in_group("ball")
		if balls.size() > 0:
			ball_node = balls[0] as Node2D

	var carrier_node = target_carrier
	if is_instance_valid(ball_node) and ball_node.get("carrier") != null:
		carrier_node = ball_node.get("carrier")

	var act_node = active_player
	if not is_instance_valid(act_node):
		var players = get_tree().get_nodes_in_group("players")
		for p in players:
			if is_instance_valid(p) and p.get("is_user_controlled") == true:
				act_node = p as CharacterBody2D
				break

	update_camera(delta, ball_node, carrier_node, act_node)

## Frame-rate independent camera update step
func update_camera(delta: float, ball: Node2D = null, carrier: CharacterBody2D = null, active_p: CharacterBody2D = null) -> void:
	# 1. Calculate target focus point
	var target_pos := global_position
	var ball_speed: float = 0.0
	var carrier_speed: float = 0.0

	if is_instance_valid(ball):
		if ball is CharacterBody2D:
			ball_speed = (ball as CharacterBody2D).velocity.length()

		var is_controlled: bool = false
		if ball.get("current_state") != null:
			# Ball.State.CONTROLADA == 1
			is_controlled = (int(ball.get("current_state")) == 1)

		if is_controlled and is_instance_valid(carrier):
			carrier_speed = carrier.velocity.length()
			target_pos = carrier.global_position.lerp(ball.global_position, 0.42)
		elif is_instance_valid(active_p):
			target_pos = active_p.global_position.lerp(ball.global_position, 0.65)
		else:
			target_pos = ball.global_position
	elif is_instance_valid(active_p):
		target_pos = active_p.global_position
	elif is_instance_valid(carrier):
		target_pos = carrier.global_position

	# 2. Viewport-aware field clamping
	var vp = get_viewport()
	if vp:
		var vp_rect = vp.get_visible_rect()
		var cur_z = zoom.x if zoom.x > 0.001 else 1.0
		var max_cam_x = maxf(0.0, field_half_width - (vp_rect.size.x * 0.5 / cur_z))
		var max_cam_y = maxf(0.0, field_half_height - (vp_rect.size.y * 0.5 / cur_z))
		target_pos.x = clampf(target_pos.x, -max_cam_x, max_cam_x)
		target_pos.y = clampf(target_pos.y, -max_cam_y, max_cam_y)

	# 3. Position interpolation via exponential decay
	var pos_weight = 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(target_pos, pos_weight)

	# 4. Speed-based dynamic zoom with Hermite smoothstep
	var eff_speed = (ball_speed * 0.75) + (carrier_speed * 0.25)
	var t_v = clampf((eff_speed - speed_threshold_min) / (speed_threshold_max - speed_threshold_min), 0.0, 1.0)
	var smooth_t = t_v * t_v * (3.0 - 2.0 * t_v)
	var target_zoom_val = lerpf(zoom_close, zoom_wide, smooth_t)

	var zoom_rate = zoom_out_rate if target_zoom_val < zoom.x else zoom_in_rate
	var new_zoom = lerpf(zoom.x, target_zoom_val, 1.0 - exp(-zoom_rate * delta))
	zoom = Vector2(new_zoom, new_zoom)

	# 5. Procedural camera shake
	if trauma > 0.0:
		trauma = maxf(0.0, trauma - trauma_decay * delta)
		noise_y += delta * 140.0
		var shake_intensity = trauma * trauma

		var n_x = noise.get_noise_2d(noise_y, 0.0) if noise else (randf() * 2.0 - 1.0)
		var n_y = noise.get_noise_2d(0.0, noise_y) if noise else (randf() * 2.0 - 1.0)
		var n_r = noise.get_noise_2d(noise_y, 100.0) if noise else 0.0

		var offset_x = max_offset.x * shake_intensity * n_x
		var offset_y = max_offset.y * shake_intensity * n_y
		var roll = deg_to_rad(max_roll_deg) * shake_intensity * n_r

		offset = Vector2(offset_x, offset_y)
		rotation = roll
	else:
		offset = Vector2.ZERO
		rotation = 0.0
